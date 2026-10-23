import AgentDomain
import CodexAppServerKit
import Foundation
import HookServer
import PTYKit
import TerminalUI
import Testing
@testable import SessionFeature

@MainActor
struct SessionRuntimeProjectionTests {
    @Test func applyingRemoteStateDoesNotRunLocalStatusOrPersistenceObservers() throws {
        let id = SessionID()
        var initial = SessionRuntimeChatSnapshot(id: id, startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: "/workspace")
        initial.status = .running
        let viewModel = ChatSessionViewModel(projection: initial) { _, _ in .none }
        var titleWrites = 0
        var attentionWrites = 0
        viewModel.titleStateDidChange = { _ in titleWrites += 1 }
        viewModel.unseenCompletionDidChange = { attentionWrites += 1 }
        viewModel.draft = "unsent local draft"
        var changed = initial
        changed.status = .awaitingApproval(prompt: "allow?")
        changed.statusEnteredAt = .distantPast
        changed.titleState = .legacy(name: "remote title")
        changed.hasUnseenCompletion = false
        try viewModel.applyRuntimeSnapshot(changed)
        #expect(viewModel.statusEnteredAt == .distantPast)
        #expect(!viewModel.hasUnseenCompletion)
        #expect(titleWrites == 0)
        #expect(attentionWrites == 0)
        #expect(viewModel.draft == "unsent local draft")
    }

    @Test func projectionForwardsExactRequestIdentityWithoutInventingAProvider() async throws {
        let requestID = UUID()
        let snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: nil)
        var commands: [SessionRuntimeSessionCommand] = []
        var receivedExecutionIDs: [UUID] = []
        let viewModel = ChatSessionViewModel(projection: snapshot) { executionID, command in
            receivedExecutionIDs.append(executionID)
            commands.append(command)
            return .bool(true)
        }
        await viewModel.respondToApproval(requestID, decision: .accept)
        let answered = await viewModel.respondToUserQuestion(requestId: "wire-request-7", answers: ["question-3": ["yes"]])
        #expect(answered)
        #expect(commands.count == 2)
        #expect(receivedExecutionIDs == [snapshot.executionID, snapshot.executionID])
        guard case .approval(let receivedID, _) = commands[0],
              case .question(let receivedRequest, let answers) = commands[1] else {
            Issue.record("Approval and question must remain distinct typed commands")
            return
        }
        #expect(receivedID == requestID)
        #expect(receivedRequest == "wire-request-7")
        #expect(answers == ["question-3": ["yes"]])
    }

    @Test func wrongSessionSnapshotIsRejectedBeforeChangingVisibleState() throws {
        let snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: nil)
        let viewModel = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var other = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: nil)
        other.status = .completed(exitCode: 99)
        #expect(throws: SessionRuntimeProjectionError.self) { try viewModel.applyRuntimeSnapshot(other) }
        #expect(viewModel.status == .starting)
    }

    @Test func richTranscriptAndPendingIdentitySurviveWireRoundTrip() throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = [.userMessage(id: "u1", text: "日本語 🪷", timestamp: .distantPast,
            attachments: [ChatUserAttachment(filename: "image.png", mediaType: "image/png")])]
        snapshot.pendingApprovals = [ChatApprovalRequest(id: UUID(), kind: .command,
            threadId: "thread", turnId: "turn", itemId: "item", prompt: "permission")]
        let decoded = try JSONDecoder().decode(SessionRuntimeSessionSnapshot.self,
            from: JSONEncoder().encode(SessionRuntimeSessionSnapshot.chat(snapshot)))
        guard case .chat(let result) = decoded else { Issue.record("Session kind changed"); return }
        #expect(result.transcript == snapshot.transcript)
        #expect(result.pendingApprovals == snapshot.pendingApprovals)
    }

    @Test func snapshotDuringPendingSendCannotReopenTheComposerSendGate() async throws {
        let snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: nil)
        let entered = AsyncStream<Void>.makeStream()
        var gate: CheckedContinuation<SessionRuntimeSessionCommandResult, Error>?
        let viewModel = ChatSessionViewModel(projection: snapshot) { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                gate = continuation
                entered.continuation.yield(())
            }
        }
        let sending = Task { try await viewModel.sendText("first", submit: true) }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        try viewModel.applyRuntimeSnapshot(snapshot)
        #expect(viewModel.inFlightText == "first")
        await #expect(throws: ChatSessionViewModel.ControlImageSendError.self) {
            try await viewModel.sendText("second", submit: true)
        }
        gate?.resume(returning: .accepted(UUID()))
        gate = nil
        try await sending.value
        #expect(viewModel.inFlightText == nil)
    }

    @Test func projectedSkillSelectionUsesTheRuntimeFingerprintWithoutOpeningLocalFiles() {
        let skill = SkillMetadata(description: "skill", enabled: true, name: "test-skill",
            path: "/not-a-local-skill/SKILL.md", scope: .user)
        let snapshot = SessionRuntimeSkillSnapshot(skills: [skill], fingerprints: [skill.path: "runtime-fingerprint"],
            isLoading: false, isStale: false, errorMessage: nil)
        let state = CodexSkillSelectionState(projection: snapshot, sessionCWD: "/workspace", refresh: {})
        #expect(state.select(skill))
        #expect(state.runtimeSelectionIdentity?.runtimeFingerprint == "runtime-fingerprint")
        #expect(state.canSendSelectedSkill)
        var changed = snapshot
        changed.fingerprints[skill.path] = "replacement-fingerprint"
        state.applyRuntimeSnapshot(changed)
        #expect(!state.canSendSelectedSkill)
        #expect(state.requiresReselection)
    }

    @Test func releasingProjectionDoesNotSendAStopOrAnswerCommand() {
        var commands = 0
        let snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: nil)
        var viewModel: ChatSessionViewModel? = ChatSessionViewModel(projection: snapshot) { _, _ in
            commands += 1
            return .none
        }
        weak var released = viewModel
        viewModel = nil
        #expect(released == nil)
        #expect(commands == 0)
    }

    @Test func queuedCommandKeepsItsOriginalExecutionInsteadOfFollowingARestart() async throws {
        let snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: nil)
        let sent = AsyncStream<UUID>.makeStream()
        let viewModel = ChatSessionViewModel(projection: snapshot) { executionID, _ in
            sent.continuation.yield(executionID)
            return .none
        }
        viewModel.name = "rename requested before restart"
        var restarted = snapshot
        restarted.executionID = UUID()
        try viewModel.applyRuntimeSnapshot(restarted)
        var iterator = sent.stream.makeAsyncIterator()
        #expect(await iterator.next() == snapshot.executionID)
        #expect(viewModel.executionID == restarted.executionID)
    }

    @Test func runtimeResizeUpdatesTheParserAndTheRealPTYWithoutResettingInputModes() async throws {
        let manager = PTYManager()
        let coordinator = TerminalCoordinator()
        let hooks = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let viewModel = SessionViewModel(id: SessionID(), ptyManager: manager,
            hookEvents: hooks.stream, terminalCoordinator: coordinator,
            spawnRequest: .init(command: "/bin/cat", args: [], env: [:], workingDirectory: nil))
        await viewModel.spawnEager()
        do {
            _ = try #require(await manager.getWinsize(viewModel.id))
            coordinator.feed(Data("\u{1b}[?1h\u{1b}[?2004h".utf8))
            let projection = try TerminalCoordinator(runtimeProjection: coordinator.makeRuntimeDisplaySnapshot())
            var resizeEchoes = 0
            var parserReplies = 0
            projection.onResize = { _, _ in resizeEchoes += 1 }
            projection.onInput = { _ in parserReplies += 1 }

            _ = try await viewModel.performRuntimeCommand(.resize(cols: 191, rows: 47),
                expectedExecutionID: viewModel.executionID)
            let snapshot = try viewModel.makeRuntimeSnapshot()
            let winsize = try #require(await manager.getWinsize(viewModel.id))
            #expect(snapshot.display.columns == 191)
            #expect(snapshot.display.rows == 47)
            #expect(winsize.cols == 191)
            #expect(winsize.rows == 47)
            #expect(snapshot.display.applicationCursor)
            #expect(snapshot.display.bracketedPaste)

            try projection.applyRuntimeDisplaySnapshot(snapshot.display)
            #expect(projection.currentCols == 191)
            #expect(projection.currentRows == 47)
            #expect(resizeEchoes == 0)
            #expect(parserReplies == 0)
            await viewModel.kill()
        } catch {
            await viewModel.kill()
            throw error
        }
    }
}
