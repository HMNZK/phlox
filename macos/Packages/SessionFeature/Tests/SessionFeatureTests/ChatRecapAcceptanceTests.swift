import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-3 契約の凍結受け入れテスト（PM 著・実装役は編集禁止）。
// 契約の正本: tasks/task-3.md。ハーネス欠陥を見つけたら PM に報告し承認を得てからハーネス部分のみ修理してよい。

@Suite("ChatRecap.derive 受け入れ")
struct ChatRecapAcceptanceTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var later: Date { t0.addingTimeInterval(10) }  // 10s 経過（閾値 5s 超）
    var soon: Date { t0.addingTimeInterval(2) }    // 2s（閾値未満）

    func user(_ id: String = "u") -> ChatItem { .userMessage(id: id, text: "やって", timestamp: t0) }
    func reasoning(_ text: String, _ id: String = "r") -> ChatItem { .reasoning(id: id, text: text, timestamp: t0) }
    func command(_ cmd: String, _ id: String = "c") -> ChatItem { .commandExecution(id: id, command: cmd, output: "", timestamp: t0) }
    func file(_ path: String, _ id: String = "f") -> ChatItem { .fileChange(id: id, changes: [FilePatchChange(path: path, diff: "")], timestamp: t0) }

    @Test("running でない、または turnStartedAt nil は nil")
    func gateNotRunning() {
        #expect(ChatRecap.derive(transcript: [user(), reasoning("## X")], status: .idle, turnStartedAt: t0, now: later) == nil)
        #expect(ChatRecap.derive(transcript: [user(), reasoning("## X")], status: .running, turnStartedAt: nil, now: later) == nil)
    }

    @Test("閾値未満は nil")
    func gateBelowThreshold() {
        #expect(ChatRecap.derive(transcript: [user(), command("swift build")], status: .running, turnStartedAt: t0, now: soon) == nil)
    }

    @Test("reasoning の見出しから要約")
    func fromReasoningHeading() {
        let r = ChatRecap.derive(transcript: [user(), reasoning("## 認証を設計\n詳細")], status: .running, turnStartedAt: t0, now: later)
        #expect(r == "認証を設計")
    }

    @Test("command は実行ラベル")
    func fromCommand() {
        #expect(ChatRecap.derive(transcript: [user(), command("swift build")], status: .running, turnStartedAt: t0, now: later) == "swift build を実行中")
    }

    @Test("fileChange は編集ラベル")
    func fromFileChange() {
        #expect(ChatRecap.derive(transcript: [user(), file("Foo.swift")], status: .running, turnStartedAt: t0, now: later) == "Foo.swift を編集中")
    }

    @Test("最新活動が優先（command の後の fileChange）")
    func newestWins() {
        let items = [user(), command("cat a"), file("B.swift")]
        #expect(ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later) == "B.swift を編集中")
    }

    @Test("最後の userMessage 以降だけを対象にする")
    func scopeAfterLastUser() {
        // userMessage 前の command は無視、後の ls（read 系）だけが対象
        let items = [command("swift run"), user(), command("ls")]
        #expect(ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later) == "ls を読み込み中")
    }
}
