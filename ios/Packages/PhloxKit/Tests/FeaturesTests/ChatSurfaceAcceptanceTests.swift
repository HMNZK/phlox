import Foundation
import Testing
import PhloxCore
import Features

/// task-8 受け入れテスト（PM 著・実装役は編集禁止）。
/// チャット面 UX パリティ: ①送信完了バナー廃止（送信成功後は idle に戻る）
/// ②自動追従スクロールの判定 ③メッセージコピー文字列。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
@MainActor
struct SentBannerRemovalAcceptanceTests {
    private func makeSession() -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .running,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("SessionDetail: 送信成功後は sent 状態を経ず idle に戻る（完了バナー廃止）")
    func sessionDetailSendReturnsToIdle() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "こんにちは"

        await vm.sendMessage()

        #expect(vm.sendState == .idle, "送信完了ステータスは表示しない（バナー廃止）")
        #expect(vm.inputText.isEmpty, "楽観更新のクリアは維持する")
    }

    @Test("SessionDetail: 送信失敗の表示（failed）は維持する")
    func sessionDetailSendFailureIsKept() async {
        let api = MockAPI(sendOutcome: .failure(.unreachable))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "こんにちは"

        await vm.sendMessage()

        guard case .failed = vm.sendState else {
            Issue.record("送信失敗は failed のまま表示する（巻き添え禁止）: \(vm.sendState)")
            return
        }
        #expect(vm.inputText == "こんにちは", "失敗時のテキスト復元は維持する")
    }

    @Test("ChatAnswer: 送信成功後は sent 状態を経ず idle に戻る（完了バナー廃止）")
    func chatAnswerSendReturnsToIdle() async {
        let session = Session(
            id: "s1", name: "Tulip", agent: .codex,
            status: .awaitingApproval(prompt: "どちらにしますか？"),
            subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
        )
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = ChatAnswerViewModel(session: session, api: api)
        vm.inputText = "A で進めてください"

        await vm.sendAnswer()

        #expect(vm.sendState == .idle, "送信完了ステータスは表示しない（バナー廃止）")
    }
}

struct ChatAutoFollowPolicyAcceptanceTests {
    @Test("最下部（距離0）と閾値以内は追従する")
    func followsNearBottom() {
        #expect(ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 0))
        #expect(ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 79))
        #expect(ChatAutoFollowPolicy.shouldFollowBottom(
            distanceFromBottom: ChatAutoFollowPolicy.followThreshold
        ), "閾値ちょうどは追従する")
    }

    @Test("閾値を超えて上に読み戻っていたら追従しない")
    func doesNotFollowWhenScrolledUp() {
        #expect(!ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 81))
        #expect(!ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 5000))
    }
}

struct ChatMessageCopyTextAcceptanceTests {
    @Test("user/agent/reasoning/subAgent は text 全文をコピーする")
    func copiesPlainTexts() {
        #expect(ChatMessageCopyText.copyText(for: .user(id: "m", text: "質問です")) == "質問です")
        #expect(ChatMessageCopyText.copyText(for: .agent(id: "m", text: "回答 **強調**")) == "回答 **強調**")
        #expect(ChatMessageCopyText.copyText(for: .reasoning(id: "m", text: "考え中")) == "考え中")
        #expect(ChatMessageCopyText.copyText(for: .subAgent(id: "m", text: "explore 起動")) == "explore 起動")
    }

    @Test("command は $ コマンド + 出力、error は message をコピーする")
    func copiesCommandAndError() {
        #expect(ChatMessageCopyText.copyText(
            for: .command(id: "m", command: "ls -la", output: "a.txt\nb.txt")
        ) == "$ ls -la\na.txt\nb.txt")
        #expect(ChatMessageCopyText.copyText(
            for: .command(id: "m", command: nil, output: "raw output")
        ) == "raw output")
        #expect(ChatMessageCopyText.copyText(for: .error(id: "m", message: "失敗しました")) == "失敗しました")
    }

    @Test("fileChange は path と diff を空行区切りで連結する")
    func copiesFileChanges() {
        let message = ChatMessage.fileChange(id: "m", changes: [
            ChatFileChange(path: "a.swift", diff: "+let a = 1", kind: nil),
            ChatFileChange(path: "b.swift", diff: "-let b = 2", kind: nil),
        ])
        #expect(ChatMessageCopyText.copyText(for: message) == "a.swift\n+let a = 1\n\nb.swift\n-let b = 2")
    }

    @Test("空・空白のみのメッセージは nil（コピーボタンを出さない）")
    func emptyMessagesAreNil() {
        #expect(ChatMessageCopyText.copyText(for: .agent(id: "m", text: "")) == nil)
        #expect(ChatMessageCopyText.copyText(for: .agent(id: "m", text: "  \n ")) == nil)
    }
}
