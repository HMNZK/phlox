import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

// task-1 白箱テスト（実装役著述）。
// 契約: シングルビュー・ヘッダ行の共有定数と表示名のフォールバックを純関数経路で捕まえる。

@Suite("ChatSession header whitebox")
struct ChatSessionHeaderWhiteboxTests {

    @Test
    func headerHeightMatchesGridTileHeaderTarget() {
        #expect(SubAgentSplitLayout.headerHeight == 32)
    }

    @Test @MainActor
    func displayNameFallsBackToShortIDWhenNameIsBlank() {
        let id = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)
        let vm = makeViewModel(id: id)
        vm.name = "   "
        #expect(vm.displayName == "#F83921")
    }

    @Test @MainActor
    func displayNameUsesTrimmedSessionName() {
        let vm = makeViewModel()
        vm.name = "  My Session  "
        #expect(vm.displayName == "My Session")
    }
}

@MainActor
private func makeViewModel(id: SessionID = SessionID()) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: id,
        agentRef: .builtin(.claudeCode),
        client: HeaderWhiteboxStructuredClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp"
    )
}

private final class HeaderWhiteboxStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent>.makeStream().stream

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}
