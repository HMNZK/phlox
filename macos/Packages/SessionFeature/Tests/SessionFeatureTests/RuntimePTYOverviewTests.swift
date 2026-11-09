import AgentDomain
import Foundation
import HookServer
import PTYKit
import TerminalUI
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimePTYOverviewTests {
    @Test func overviewShowsMetadataWhileDisplayIsStillLoading() throws {
        let overview = makeOverview(executionID: UUID(uuidString: "9ED8B683-9CA9-4447-A18E-40F850D7F638")!, status: .idle)

        let session = try SessionViewModel(projection: overview) { _, _ in .none }

        #expect(session.agentRef == .builtin(.claudeCode))
        #expect(session.rawWorkspacePath == "/work/actual-project")
        #expect(session.isReadyForInput)
        #expect(session.status == .idle)
        #expect(!session.isRuntimeDisplayLoaded)
    }

    @Test func newExecutionHidesOldDisplayAndRejectsLateSnapshot() throws {
        let firstExecution = UUID(uuidString: "A4E3AD9D-ADBF-45B6-A8E9-B06A7A433CC8")!
        let nextExecution = UUID(uuidString: "5910B395-579F-4C70-BA95-F792900E28E0")!
        let first = makeOverview(executionID: firstExecution, status: .idle)
        let session = try SessionViewModel(projection: first) { _, _ in .none }
        let source = TerminalCoordinator()
        source.feed(Data("old terminal secret".utf8))
        var oldSnapshot = SessionRuntimePTYSnapshot(id: first.id, startedAt: first.startedAt,
            agentRef: first.agentRef, workingDirectory: "/work/actual-project",
            display: try source.makeRuntimeDisplaySnapshot())
        oldSnapshot.executionID = firstExecution

        try session.applyRuntimeContent(oldSnapshot, displayRevision: 1)
        try session.applyRuntimeOverview(makeOverview(executionID: nextExecution, status: .idle))

        #expect(!session.isRuntimeDisplayLoaded)
        #expect(session.executionID == nextExecution)
        #expect(!session.terminalCoordinator.visibleText().contains("old terminal secret"))
        do {
            try session.applyRuntimeContent(oldSnapshot, displayRevision: 2)
            Issue.record("前の実行世代の端末画面を受理した")
        } catch {
            guard let projectionError = error as? SessionRuntimeProjectionError,
                  case .staleExecution = projectionError else {
                Issue.record("予期しない拒否理由: \(error)")
                return
            }
        }
    }

    @Test func lateDisplayDoesNotRollBackNewerStatus() throws {
        let executionID = UUID(uuidString: "2503718B-EE72-4D81-A224-E9C4B5C4450B")!
        let session = try SessionViewModel(projection: makeOverview(executionID: executionID, status: .running)) { _, _ in .none }
        let source = TerminalCoordinator()
        source.feed(Data("terminal output".utf8))
        var delayed = SessionRuntimePTYSnapshot(id: session.id, startedAt: session.startedAt,
            agentRef: session.agentRef, workingDirectory: "/work/actual-project",
            display: try source.makeRuntimeDisplaySnapshot())
        delayed.executionID = executionID
        delayed.status = .running
        delayed.titleState = .legacy(name: "old title")

        try session.applyRuntimeOverview(makeOverview(executionID: executionID, status: .idle))
        try session.applyRuntimeSnapshot(delayed)

        #expect(session.status == .idle)
        #expect(session.name == "Existing PTY")
        #expect(session.terminalCoordinator.visibleText().contains("terminal output"))
    }

    @Test func outputAfterOverviewReturnsTheCapturedDisplayRevision() async throws {
        let coordinator = TerminalCoordinator()
        let hooks = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let session = SessionViewModel(id: SessionID(), ptyManager: PTYManager(),
            hookEvents: hooks.stream, terminalCoordinator: coordinator,
            spawnRequest: .init(command: "/bin/cat", args: [], env: [:],
                workingDirectory: "/work/actual-project"))
        let original = session.makeRuntimeOverview()
        guard case .pty(let originalState) = original.kind else {
            Issue.record("PTY overview was not returned")
            return
        }
        let request = SessionRuntimeContentRequest(sessionID: session.id,
            executionID: session.executionID,
            target: .ptySnapshot(displayRevision: originalState.displayRevision))

        _ = try await session.performRuntimeCommand(.resize(cols: 91, rows: 37),
            expectedExecutionID: session.executionID)
        let changed = session.makeRuntimeOverview()

        guard case .pty(let changedState) = changed.kind else {
            Issue.record("PTY overview was not returned")
            return
        }
        let response = try session.runtimeContent(for: request)
        guard case .ptySnapshot(let snapshot, let capturedRevision) = response else {
            Issue.record("PTY の表示内容が返りませんでした")
            return
        }
        #expect(changedState.displayRevision > originalState.displayRevision)
        #expect(capturedRevision == changedState.displayRevision)
        #expect(snapshot.display.columns == 91)
        #expect(snapshot.display.rows == 37)
    }

    @Test func olderDisplayResponseCannotReplaceNewerDisplayedOutput() throws {
        let executionID = UUID(uuidString: "2AEE160C-C8CE-4B77-817C-9F592FF4E568")!
        let overview = makeOverview(executionID: executionID, status: .running)
        let session = try SessionViewModel(projection: overview) { _, _ in .none }
        let newer = try makeDisplaySnapshot(overview: overview, text: "new terminal output")
        let older = try makeDisplaySnapshot(overview: overview, text: "old terminal output")

        try session.applyRuntimeContent(newer, displayRevision: 9)
        try session.applyRuntimeContent(older, displayRevision: 8)

        #expect(session.terminalCoordinator.visibleText().contains("new terminal output"))
        #expect(!session.terminalCoordinator.visibleText().contains("old terminal output"))
        #expect(session.runtimeDisplayedRevision == 9)
    }

    @Test func contentFailureRemainsVisibleAcrossOverviewRefresh() throws {
        let executionID = UUID(uuidString: "44F79BD1-268D-4326-B468-B77C35D55760")!
        let overview = makeOverview(executionID: executionID, status: .running)
        let session = try SessionViewModel(projection: overview) { _, _ in .none }

        session.reportRuntimeContentFailure(SessionRuntimeContentError.invalidRequest)
        try session.applyRuntimeOverview(overview)

        #expect(session.runtimeConnectionError == SessionRuntimeContentError.invalidRequest.localizedDescription)
    }

    private func makeDisplaySnapshot(overview: SessionRuntimeSessionOverview, text: String) throws -> SessionRuntimePTYSnapshot {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data(text.utf8))
        var snapshot = SessionRuntimePTYSnapshot(id: overview.id, startedAt: overview.startedAt,
            agentRef: overview.agentRef, workingDirectory: "/work/actual-project",
            display: try coordinator.makeRuntimeDisplaySnapshot())
        snapshot.executionID = overview.executionID
        return snapshot
    }

    private func makeOverview(executionID: UUID, status: SessionStatus) -> SessionRuntimeSessionOverview {
        SessionRuntimeSessionOverview(
            id: SessionID(rawValue: UUID(uuidString: "D03BFCA9-6129-46E6-841B-44602FC19623")!),
            startedAt: Date(timeIntervalSince1970: 1700000000),
            agentRef: .builtin(.claudeCode), workingDirectory: "/work/actual-project",
            executionID: executionID, title: "Existing PTY", projectID: nil,
            parentSessionID: nil, launchContext: .interactive,
            status: status, displayStatus: status,
            statusEnteredAt: Date(timeIntervalSince1970: 1700000010),
            displayStatusEnteredAt: Date(timeIntervalSince1970: 1700000010),
            hasUnseenCompletion: false, lastOutputAt: Date(timeIntervalSince1970: 1700000020),
            lastTurnCompletedAt: nil,
            kind: .pty(.init(completedTurnSeq: 7, hasProducedOutput: true,
                isRestored: true, isReadyForInput: true)))
    }
}
