import AgentDomain
import Foundation
import PhloxCore
import Testing
@testable import Features

/// Thinking インジケータの活動状態（orb の 6 状態）の導出規則。macOS ChatRecap と同じ意味論。
@Suite("ChatRecapIOS 活動状態の導出")
struct ChatActivityStateIOSTests {
    func user(_ id: String = "u") -> ChatMessage { .user(id: id, text: "hi") }
    func reasoning(_ id: String = "r") -> ChatMessage { .reasoning(id: id, text: "検討中") }
    func command(_ cmd: String?, _ id: String = "c") -> ChatMessage {
        .command(id: id, command: cmd, output: "")
    }
    func file(_ id: String = "f") -> ChatMessage {
        .fileChange(id: id, changes: [ChatFileChange(path: "a.swift", diff: "")])
    }
    func agent(_ id: String = "a") -> ChatMessage { .agent(id: id, text: "回答") }

    @Test("承認待ちは実行中の項目より優先して waiting")
    func awaitingApprovalWins() {
        let messages = [user(), command("swift build")]
        let state = ChatRecapIOS.deriveActivityState(
            messages: messages,
            status: .awaitingApproval(prompt: "続行?")
        )
        #expect(state == .waiting)
    }

    @Test("読み取りツールの直後は searching")
    func lastReadToolIsSearching() {
        let messages = [user(), reasoning(), command("Read /tmp/a.swift")]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .searching)
    }

    @Test("コマンド実行の直後は running")
    func lastShellCommandIsRunning() {
        let messages = [user(), command("swift build")]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .running)
    }

    @Test("ファイル変更の直後は editing")
    func lastFileChangeIsEditing() {
        let messages = [user(), command("Read a.swift"), file()]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .editing)
    }

    @Test("回答テキストの出力中は writing")
    func lastAgentMessageIsWriting() {
        let messages = [user(), file(), agent()]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .writing)
    }

    @Test("推論だけなら thinking")
    func reasoningOnlyIsThinking() {
        let messages = [user(), reasoning()]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .thinking)
    }

    @Test("項目が無ければ thinking")
    func emptyTranscriptIsThinking() {
        #expect(ChatRecapIOS.deriveActivityState(messages: [], status: .running) == .thinking)
    }

    @Test("直前ターンの項目は見ない（最後のユーザー入力以降だけを見る）")
    func scopeStartsAfterLastUserMessage() {
        let messages = [user("u1"), file("f1"), user("u2"), command("Grep foo")]
        #expect(ChatRecapIOS.deriveActivityState(messages: messages, status: .running) == .searching)
    }
}
