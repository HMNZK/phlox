import Foundation
import Testing
import PhloxCore
@testable import Features

// task-4 契約の凍結受け入れテスト（PM 著・実装役は編集禁止）。
// 契約の正本: tasks/task-4.md。ハーネス欠陥を見つけたら PM に報告し承認を得てからハーネス部分のみ修理してよい。
// SessionStatus は PhloxCore が AgentDomain を再エクスポートするため import PhloxCore で参照可能。

@Suite("ChatRecapIOS.derive 受け入れ")
struct IOSChatRecapAcceptanceTests {
    let threshold: TimeInterval = 5

    func user(_ id: String = "u") -> ChatMessage { .user(id: id, text: "やって") }
    func reasoning(_ text: String, _ id: String = "r") -> ChatMessage { .reasoning(id: id, text: text) }
    func command(_ cmd: String, _ id: String = "c") -> ChatMessage { .command(id: id, command: cmd, output: "") }
    func file(_ path: String, _ id: String = "f") -> ChatMessage { .fileChange(id: id, changes: [ChatFileChange(path: path, diff: "")]) }

    @Test("running でなければ nil")
    func gateNotRunning() {
        #expect(ChatRecapIOS.derive(messages: [user(), command("swift build")], status: .idle, elapsed: 10, threshold: threshold) == nil)
    }

    @Test("経過が閾値未満は nil")
    func gateBelowThreshold() {
        #expect(ChatRecapIOS.derive(messages: [user(), command("swift build")], status: .running, elapsed: 2, threshold: threshold) == nil)
    }

    @Test("reasoning の見出しから要約")
    func fromReasoningHeading() {
        let r = ChatRecapIOS.derive(messages: [user(), reasoning("## 認証を設計\n詳細")], status: .running, elapsed: 10, threshold: threshold)
        #expect(r == "認証を設計")
    }

    @Test("command は実行ラベル")
    func fromCommand() {
        #expect(ChatRecapIOS.derive(messages: [user(), command("swift build")], status: .running, elapsed: 10, threshold: threshold) == "swift build を実行中")
    }

    @Test("fileChange は編集ラベル")
    func fromFileChange() {
        #expect(ChatRecapIOS.derive(messages: [user(), file("Foo.swift")], status: .running, elapsed: 10, threshold: threshold) == "Foo.swift を編集中")
    }

    @Test("最新活動が優先（command の後の fileChange）")
    func newestWins() {
        let msgs = [user(), command("cat a"), file("B.swift")]
        #expect(ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold) == "B.swift を編集中")
    }

    @Test("最後の user 以降だけを対象にする")
    func scopeAfterLastUser() {
        let msgs = [command("swift run"), user(), command("ls")]
        #expect(ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold) == "ls を読み込み中")
    }
}
