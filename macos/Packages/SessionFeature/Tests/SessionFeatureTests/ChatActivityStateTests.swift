import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

/// Thinking インジケータの活動状態（orb の 6 状態）の導出規則。
@Suite("ChatRecap 活動状態の導出")
struct ChatActivityStateTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    func user(_ id: String = "u") -> ChatItem { .userMessage(id: id, text: "hi", timestamp: t0) }
    func reasoning(_ id: String = "r") -> ChatItem { .reasoning(id: id, text: "検討中", timestamp: t0) }
    func command(_ cmd: String?, _ id: String = "c") -> ChatItem {
        .commandExecution(id: id, command: cmd, output: "", timestamp: t0)
    }
    func file(_ id: String = "f") -> ChatItem {
        .fileChange(id: id, changes: [FilePatchChange(path: "a.swift", diff: "")], timestamp: t0)
    }
    func agent(_ id: String = "a") -> ChatItem { .agentMessage(id: id, text: "回答", timestamp: t0) }

    @Test("承認待ちは実行中の項目より優先して waiting")
    func awaitingApprovalWins() {
        let transcript = [user(), command("swift build")]
        let state = ChatRecap.deriveActivityState(
            transcript: transcript,
            status: .awaitingApproval(prompt: "続行?")
        )
        #expect(state == .waiting)
    }

    @Test("読み取りツールの直後は searching")
    func lastReadToolIsSearching() {
        let transcript = [user(), reasoning(), command("Read /tmp/a.swift")]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .searching)
    }

    @Test("コマンド実行の直後は running")
    func lastShellCommandIsRunning() {
        let transcript = [user(), command("swift build")]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .running)
    }

    @Test("ファイル変更の直後は editing")
    func lastFileChangeIsEditing() {
        let transcript = [user(), command("Read a.swift"), file()]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .editing)
    }

    @Test("回答テキストの出力中は writing")
    func lastAgentMessageIsWriting() {
        let transcript = [user(), file(), agent()]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .writing)
    }

    @Test("推論だけなら thinking")
    func reasoningOnlyIsThinking() {
        let transcript = [user(), reasoning()]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .thinking)
    }

    @Test("項目が無ければ thinking")
    func emptyTranscriptIsThinking() {
        #expect(ChatRecap.deriveActivityState(transcript: [], status: .running) == .thinking)
    }

    @Test("直前ターンの項目は見ない（最後のユーザー入力以降だけを見る）")
    func scopeStartsAfterLastUserMessage() {
        let transcript = [user("u1"), file("f1"), user("u2"), command("Grep foo")]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .searching)
    }

    @Test("ツール後に推論へ戻れば thinking に戻る")
    func laterReasoningOverridesEarlierTool() {
        let transcript = [user(), command("swift build"), reasoning("r2")]
        #expect(ChatRecap.deriveActivityState(transcript: transcript, status: .running) == .thinking)
    }
}
