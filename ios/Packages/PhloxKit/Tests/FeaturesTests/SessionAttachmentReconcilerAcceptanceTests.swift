import Foundation
import Testing
import PhloxCore
@testable import Features

/// wave-8 添付バッジの突き合わせ 凍結受け入れテスト（PM 著・実装役は編集禁止）。
/// 送信テキストで送信後スナップショットのユーザーメッセージへ添付枚数を割り当てる純関数を固定する。
@Suite("wave-8 添付バッジ突き合わせ 受け入れ")
struct SessionAttachmentReconcilerAcceptanceTests {

    private func preview(_ byte: UInt8) -> Data { Data([byte]) }

    @Test("送信テキストに一致する最新の未割当ユーザーメッセージへ枚数を割り当てる")
    func assignsToNewestMatchingUserMessage() {
        let messages: [ChatMessage] = [
            .user(id: "m1", text: "hi"),
            .agent(id: "a1", text: "ok"),
            .user(id: "m2", text: "hi"),
        ]
        let result = SessionAttachmentReconciler.reconcile(
            messages: messages,
            pending: [.init(text: "hi", previews: [preview(1), preview(2)])],
            assigned: [:]
        )
        #expect(result.assigned == ["m2": [preview(1), preview(2)]])
        #expect(result.remaining.isEmpty)
    }

    @Test("一致するユーザーメッセージがまだ無ければ pending を保持する")
    func keepsPendingWhenNoMatchYet() {
        let result = SessionAttachmentReconciler.reconcile(
            messages: [.agent(id: "a1", text: "hi")],
            pending: [.init(text: "hi", previews: [preview(1)])],
            assigned: [:]
        )
        #expect(result.assigned.isEmpty)
        #expect(result.remaining == [.init(text: "hi", previews: [preview(1)])])
    }

    @Test("既に割当済みのメッセージへは再割当せず pending を保持する")
    func doesNotReassignAlreadyMappedMessage() {
        let result = SessionAttachmentReconciler.reconcile(
            messages: [.user(id: "m1", text: "hi")],
            pending: [.init(text: "hi", previews: [preview(1), preview(2), preview(3)])],
            assigned: ["m1": [preview(9)]]
        )
        #expect(result.assigned == ["m1": [preview(9)]])
        #expect(result.remaining == [.init(text: "hi", previews: [preview(1), preview(2), preview(3)])])
    }
}
