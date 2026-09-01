import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Codex error visibility")
@MainActor
struct CodexErrorVisibilityTests {
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
