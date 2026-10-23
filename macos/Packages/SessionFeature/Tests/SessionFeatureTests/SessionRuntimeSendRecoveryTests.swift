import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

private enum RuntimeSendTestError: Error { case rejected }

private actor RuntimeSendGateClient: StructuredAgentClient {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private var gate: CheckedContinuation<Void, Error>?
    private var released = false
    private var sendCount = 0
    nonisolated let sends: AsyncStream<Void>
    private let sendContinuation: AsyncStream<Void>.Continuation

    init() {
        let stream = AsyncStream<NormalizedChatEvent>.makeStream()
        events = stream.stream
        eventContinuation = stream.continuation
        let entered = AsyncStream<Void>.makeStream()
        sends = entered.stream
        sendContinuation = entered.continuation
    }

    func start() async {}
    func resume(sessionRef: String) async throws {}
    func turnStart(_ input: [ChatInput]) async throws {
        sendCount += 1
        sendContinuation.yield(())
        guard !released else { return }
        try await withCheckedThrowingContinuation { gate = $0 }
    }
    func reject() {
        released = true
        gate?.resume(throwing: RuntimeSendTestError.rejected)
        gate = nil
    }
    func release() {
        released = true
        gate?.resume()
        gate = nil
    }
    func interrupt() async throws { release() }
    func close() async { release(); eventContinuation.finish() }
}

private actor RuntimeSkillGateClient: StructuredAgentClient, CodexSkillSelectionClient {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let skillEvents: AsyncStream<ThreadEvent>
    nonisolated let entered: AsyncStream<Void>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let skillContinuation: AsyncStream<ThreadEvent>.Continuation
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private var gate: CheckedContinuation<SkillsListResponse, Error>?
    private(set) var startedTurns = 0

    init() {
        let events = AsyncStream<NormalizedChatEvent>.makeStream()
        self.events = events.stream
        eventContinuation = events.continuation
        let skills = AsyncStream<ThreadEvent>.makeStream()
        skillEvents = skills.stream
        skillContinuation = skills.continuation
        let entered = AsyncStream<Void>.makeStream()
        self.entered = entered.stream
        enteredContinuation = entered.continuation
    }

    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        try await withCheckedThrowingContinuation {
            gate = $0
            enteredContinuation.yield(())
        }
    }
    func releaseSkills() {
        gate?.resume(returning: SkillsListResponse(data: [SkillsListEntry(cwd: "/workspace", errors: [],
            skills: [SkillMetadata(description: "test", enabled: true, name: "skill",
                path: "/unused-after-cancellation/SKILL.md", scope: .user)])]))
        gate = nil
    }
    func start() async {}
    func resume(sessionRef: String) async throws {}
    func turnStart(_ input: [ChatInput]) async throws { startedTurns += 1 }
    func interrupt() async throws {}
    func close() async { releaseSkills(); eventContinuation.finish(); skillContinuation.finish() }
}

@MainActor
struct SessionRuntimeSendRecoveryTests {
    @Test func runtimeAcknowledgesRetainedSendBeforeTheProviderTurnCompletes() async throws {
        let client = RuntimeSendGateClient()
        let viewModel = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.cursor),
            client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            await client.release()
        }
        do {
            let result = try await viewModel.performRuntimeCommand(
                .send(text: "request", submit: true, attachments: [], skill: nil),
                expectedExecutionID: viewModel.executionID)
            guard case .accepted = result else {
                Issue.record("A retained send must return an acceptance receipt")
                watchdog.cancel()
                await viewModel.terminate()
                return
            }
            #expect(!watchdog.isCancelled)
            #expect(await client.isReleased == false)
            await #expect(throws: ChatSessionViewModel.ControlImageSendError.self) {
                _ = try await viewModel.performRuntimeCommand(
                    .send(text: "second", submit: true, attachments: [], skill: nil),
                    expectedExecutionID: viewModel.executionID)
            }
            watchdog.cancel()
            await viewModel.turnInterrupt()
            await viewModel.terminate()
        } catch {
            watchdog.cancel()
            await viewModel.terminate()
            throw error
        }
    }

    @Test func failedLaunchRestoresTextAndPNGOnceAcrossTheWire() async throws {
        let client = RuntimeSendGateClient()
        let owned = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode),
            client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let attachment = ComposerAttachment(data: png, mediaType: "image/png", filename: "pixel.png")
        let text = "failed first message [Image #1]"
        owned.prepareFirstMessage(text, attachments: [attachment])
        owned.markLaunchFailed(.processFailed("launch failed"), restoringDraft: text)
        let snapshot = try JSONDecoder().decode(SessionRuntimeChatSnapshot.self,
            from: JSONEncoder().encode(owned.makeRuntimeSnapshot()))
        _ = try #require(snapshot.draftRecoveryID)
        let acknowledgements = AsyncStream<Void>.makeStream()
        var fetches = 0
        var acknowledgementCount = 0
        let projection = ChatSessionViewModel(projection: snapshot) { executionID, command in
            if case .recoverLaunchDraft = command { fetches += 1 }
            let wireCommand = try JSONDecoder().decode(SessionRuntimeSessionCommand.self,
                from: JSONEncoder().encode(command))
            let response = try await owned.performRuntimeCommand(wireCommand, expectedExecutionID: executionID)
            let wireResponse = try JSONDecoder().decode(SessionRuntimeSessionCommandResult.self,
                from: JSONEncoder().encode(response))
            if case .acknowledgeRecoveredDraft = command {
                acknowledgementCount += 1
                acknowledgements.continuation.yield(())
            }
            return wireResponse
        }
        var iterator = acknowledgements.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(projection.draft == text)
        #expect(projection.composerAttachments.map(\.data) == [png])
        #expect(projection.composerAttachments.map(\.filename) == ["pixel.png"])
        projection.draft = "new local editing"
        for _ in 0..<200 {
            try projection.applyRuntimeSnapshot(snapshot)
            await Task.yield()
        }
        #expect(projection.draft == "new local editing")
        #expect(fetches == 1)
        #expect(acknowledgementCount == 1)
        let reconnectedAcknowledgements = AsyncStream<Void>.makeStream()
        let reconnected = ChatSessionViewModel(projection: owned.makeRuntimeSnapshot()) { executionID, command in
            let response = try await owned.performRuntimeCommand(command, expectedExecutionID: executionID)
            let decoded = try JSONDecoder().decode(SessionRuntimeSessionCommandResult.self,
                from: JSONEncoder().encode(response))
            if case .acknowledgeRecoveredDraft = command { reconnectedAcknowledgements.continuation.yield(()) }
            return decoded
        }
        var reconnectedIterator = reconnectedAcknowledgements.stream.makeAsyncIterator()
        _ = await reconnectedIterator.next()
        #expect(reconnected.draft == text)
        #expect(reconnected.composerAttachments.map(\.data) == [png])
        await owned.terminate()
    }

    @Test func stopBeforeTheAcceptedTaskRunsCannotStartAProviderTurn() async throws {
        let client = RuntimeSendGateClient()
        let owned = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.cursor),
            client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
        _ = try owned.acceptRuntimeSend(text: "request", submit: true, attachments: [], skill: nil)
        await owned.turnInterrupt()
        #expect(await client.startedSendCount == 0)
        await owned.terminate()
    }

    @Test func rejectedAcceptedSendPublishesRecoverableOriginalInput() async throws {
        let client = RuntimeSendGateClient()
        let owned = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode),
            client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
        do {
            let result = try await owned.performRuntimeCommand(
                .send(text: "original request", submit: true, attachments: [], skill: nil),
                expectedExecutionID: owned.executionID)
            guard case .accepted = result else { Issue.record("Send was not accepted"); await owned.terminate(); return }
            var entered = client.sends.makeAsyncIterator()
            _ = await entered.next()
            await client.reject()
            var snapshot = owned.makeRuntimeSnapshot()
            for _ in 0..<150 where snapshot.draftRecoveryID == nil {
                try await Task.sleep(for: .milliseconds(10))
                snapshot = owned.makeRuntimeSnapshot()
            }
            let recoveryID = try #require(snapshot.draftRecoveryID)
            let recovered = try await owned.performRuntimeCommand(.recoverLaunchDraft(recoveryID),
                expectedExecutionID: owned.executionID)
            guard case .draft(let text, _) = recovered else { Issue.record("No recoverable draft"); await owned.terminate(); return }
            #expect(text == "original request")
            #expect(snapshot.sendFailure != nil)
            await owned.terminate()
        } catch { await owned.terminate(); throw error }
    }

    @Test func cancellingInitialSendWhileSkillsLoadCannotResurrectTheTurn() async {
        let client = RuntimeSkillGateClient()
        let owned = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex),
            client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: "/workspace")
        let first = Task {
            await owned.sendFirstMessage("request", attachments: [],
                selectedSkill: SkillIdentity(name: "skill", path: "/unused-after-cancellation/SKILL.md"))
        }
        var entered = client.entered.makeAsyncIterator()
        _ = await entered.next()
        first.cancel()
        await client.releaseSkills()
        await first.value
        #expect(await client.startedTurns == 0)
        #expect(owned.makeRuntimeSnapshot().draftRecoveryID == nil)
        await owned.terminate()
    }

    @Test func failedRecoveryAcknowledgementRetriesWithoutRefetchingOrReplacingLocalEdits() async throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: nil)
        snapshot.draftRecoveryID = UUID()
        let attempted = AsyncStream<Void>.makeStream()
        var fetches = 0
        var acknowledgements = 0
        let projection = ChatSessionViewModel(projection: snapshot) { _, command in
            switch command {
            case .recoverLaunchDraft:
                fetches += 1
                return .draft(text: "failed request", attachments: [])
            case .acknowledgeRecoveredDraft:
                acknowledgements += 1
                attempted.continuation.yield(())
                if acknowledgements == 1 { throw RuntimeSendTestError.rejected }
                return .none
            default: throw SessionRuntimeProjectionError.unsupportedCommand
            }
        }
        var iterator = attempted.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(projection.draft == "failed request")
        projection.draft = "local edit after recovery"
        for _ in 0..<200 {
            try projection.applyRuntimeSnapshot(snapshot)
            await Task.yield()
        }
        #expect(fetches == 1)
        #expect(acknowledgements == 2)
        #expect(projection.draft == "local edit after recovery")
    }
}

extension RuntimeSendGateClient {
    var isReleased: Bool { released }
    var startedSendCount: Int { sendCount }
}
