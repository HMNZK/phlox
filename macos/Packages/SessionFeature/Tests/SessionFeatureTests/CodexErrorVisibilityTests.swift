import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Codex error visibility")
@MainActor
struct CodexErrorVisibilityTests {
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
