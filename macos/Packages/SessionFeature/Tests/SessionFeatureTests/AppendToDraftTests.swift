import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class IdleClient: StructuredAgentClient, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent> { _ in }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
    func resetConversation() async {}
}

/// 送信の受付を止めておき、放すと失敗させる。
private final class GatedFailingClient: StructuredAgentClient, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent> { _ in }
    private(set) var gate: CheckedContinuation<Void, Never>?
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        await withCheckedContinuation { gate = $0 }
        throw CancellationError()
    }
    func release() { gate?.resume(); gate = nil }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
    func resetConversation() async {}
}

@MainActor
private func makeViewModel(_ client: any StructuredAgentClient = IdleClient()) -> ChatSessionViewModel {
    ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
                         approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp")
}

/// 他の画面から入力欄へ文を足す（シミュレーターの「エージェントに伝える」）。
@MainActor
struct AppendToDraftTests {
    @Test(arguments: [("", "文"), ("依頼\n", "依頼\n文"), ("依頼", "依頼\n文")])
    func 下書きの末尾に改行で区切って足しキャレットを末尾へ移す(draft: String, expected: String) {
        let vm = makeViewModel()
        vm.draft = draft
        let token = vm.composerFocusRequest.token
        #expect(vm.appendToDraft("文"))
        #expect(vm.draft == expected)
        #expect(vm.composerFocusRequest.token == token + 1)
        #expect(vm.composerFocusRequest.movesCaretToEnd)
    }

    @Test func 送信の受付待ちの間は足さず失敗時に戻す本文を消さない() async throws {
        let client = GatedFailingClient()
        let vm = makeViewModel(client)
        vm.draft = "依頼"
        let text = try #require(vm.consumeDraftForSend())
        let send = Task { try? await vm.sendText(text, submit: true) }
        while client.gate == nil { await Task.yield() }
        #expect(!vm.appendToDraft("文"))
        client.release()
        await send.value
        #expect(vm.draft == "依頼")
    }

    /// 単一表示では、会話のタブへ切り替わってから入力欄が作られる。それより前に出た要求を、作られたときに適用する。
    @Test(arguments: [(Optional(0), true), (nil, false), (Optional(1), false)])
    func 作られる前に出た未処理の要求だけを作られたときに適用する(handled: Int?, applies: Bool) async throws {
        let text = "対象の iOS シミュレーター"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        var handledByView: Int?
        let hosting = NSHostingView(rootView: IMESafeTextView(
            text: .constant(text), isComposing: .constant(false), measuredHeight: .constant(40),
            minHeight: 40, maxHeight: 160, suggestionController: nil, onSubmit: {},
            focusRequest: ComposerFocusRequest(token: 1, movesCaretToEnd: true),
            handledFocusToken: handled, onFocusRequestHandled: { handledByView = $0 }))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSTextView? {
            (view as? NSTextView) ?? view.subviews.lazy.compactMap(find).first
        }
        let textView = try #require(find(hosting))
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect((window.firstResponder === textView) == applies)
        #expect((handledByView == 1) == applies)
        if applies { #expect(textView.selectedRange() == NSRange(location: text.utf16.count, length: 0)) }
    }
}
