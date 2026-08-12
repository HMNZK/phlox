import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Codex error visibility")
@MainActor
struct CodexErrorVisibilityTests {
    @Test("履歴 read/resume の失敗は空一覧でも状態へ残る")
    func historyFailuresRemainObservable() async {
        let history = CodexSessionHistory(
            client: FailingHistoryClient(),
            workingDirectory: "/workspace"
        )

        #expect(await history.readIfPossible(threadID: "thread-1") == nil)
        #expect(history.errorMessage?.contains("history-read") == true)
        #expect(await history.resumeIfPossible(threadID: "thread-1") == nil)
        #expect(history.errorMessage?.contains("history-resume") == true)
    }

    @Test("背景端末の停止失敗は対象を保持しエラーを状態へ残す")
    func backgroundTerminationFailureRemainsObservable() async {
        let state = CodexBackgroundTerminalState(
            client: FailingBackgroundClient(),
            threadId: "thread-1"
        )

        await state.refresh()
        #expect(state.items.map(\.itemId) == ["item-1"])
        #expect(await state.stop(itemId: "item-1") == false)
        #expect(state.items.map(\.itemId) == ["item-1"])
        #expect(state.errorMessage?.contains("background-terminate") == true)
    }

    @Test("skill 取得失敗は空候補でも状態へ残る")
    func skillFailureRemainsObservable() async {
        let state = CodexSkillSelectionState(
            client: FailingSkillClient(),
            sessionCWD: "/workspace"
        )

        await state.refresh()
        #expect(state.filteredSkills.isEmpty)
        #expect(state.errorMessage != nil)
    }
}

private enum CodexErrorVisibilityTestError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value): value
        }
    }
}

private struct FailingHistoryClient: CodexSessionHistoryProviding {
    func threadList(_ params: ThreadListParams) async throws -> ThreadListResponse {
        throw CodexErrorVisibilityTestError.message("history-list")
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        throw CodexErrorVisibilityTestError.message("history-read")
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        throw CodexErrorVisibilityTestError.message("history-resume")
    }
}

private struct FailingSkillClient: CodexSkillSelectionClient {
    let skillEvents = AsyncStream<ThreadEvent> { continuation in
        continuation.finish()
    }

    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        throw CodexErrorVisibilityTestError.message("skill-list")
    }
}

private struct FailingBackgroundClient: CodexBackgroundTerminalProviding {
    func threadBackgroundTerminalsList(
        _ params: ThreadBackgroundTerminalsListParams
    ) async throws -> ThreadBackgroundTerminalsListResponse {
        ThreadBackgroundTerminalsListResponse(data: [
            ThreadBackgroundTerminal(
                itemId: "item-1",
                processId: "process-1",
                command: "swift test",
                cwd: "/workspace"
            ),
        ])
    }

    func threadBackgroundTerminalsTerminate(
        _ params: ThreadBackgroundTerminalsTerminateParams
    ) async throws -> ThreadBackgroundTerminalsTerminateResponse {
        throw CodexErrorVisibilityTestError.message("background-terminate")
    }
}
