// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — transcript からの発言切り出し・PASS 判定・1行整形。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import SessionFeature
@testable import DashboardFeature

// MARK: - fixtures

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func agent(_ id: String, _ text: String) -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: t0)
}

private func user(_ id: String, _ text: String) -> ChatItem {
    .userMessage(id: id, text: text, timestamp: t0)
}

@Suite("AgoraUtteranceExtraction acceptance (task-2)")
struct AcceptanceAgoraUtteranceTests {

    // MARK: - utterance(transcript:afterItemID:)

    @Test func afterItemID_が_nil_なら全_agentMessage_を空行区切りで結合する() {
        let transcript: [ChatItem] = [
            user("u1", "質問"),
            agent("a1", "第一段落"),
            .commandExecution(id: "c1", command: "ls", output: "x", timestamp: t0),
            agent("a2", "第二段落"),
        ]
        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: nil)
        #expect(result == "第一段落\n\n第二段落")
    }

    @Test func afterItemID_より後の_agentMessage_だけを対象にする() {
        let transcript: [ChatItem] = [
            agent("a1", "古い発言"),
            user("u1", "配送された議論"),
            agent("a2", "新しい発言"),
        ]
        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "u1")
        #expect(result == "新しい発言")
    }

    @Test func afterItemID_が_agentMessage_自身なら自身を含めない排他境界() {
        let transcript: [ChatItem] = [
            agent("a1", "前回の発言"),
            agent("a2", "今回の発言"),
        ]
        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "a1")
        #expect(result == "今回の発言")
    }

    @Test func agentMessage_以外の項目種別は結合に含めない() {
        let transcript: [ChatItem] = [
            user("u1", "ユーザー発言"),
            .reasoning(id: "r1", text: "内心の推論", timestamp: t0),
            .commandExecution(id: "c1", command: "swift test", output: "green", timestamp: t0),
            .error(id: "e1", message: "何かのエラー", timestamp: t0),
            .turnCost(id: "t1", costUSD: 0.01, timestamp: t0),
            .subAgentMarker(id: "s1", subagentType: "explore", description: "調査", status: .completed),
            agent("a1", "本文だけが残る"),
        ]
        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: nil)
        #expect(result == "本文だけが残る")
    }

    @Test func 対象範囲に_agentMessage_が無ければ_nil() {
        let transcript: [ChatItem] = [
            agent("a1", "古い発言"),
            user("u1", "新しい質問"),
        ]
        #expect(AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "u1") == nil)
        #expect(AgoraUtteranceExtraction.utterance(transcript: [], afterItemID: nil) == nil)
    }

    @Test func afterItemID_が見つからなければ全件対象のフォールバック() {
        let transcript: [ChatItem] = [
            agent("a1", "発言1"),
            agent("a2", "発言2"),
        ]
        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "存在しないID")
        #expect(result == "発言1\n\n発言2")
    }

    // MARK: - isPass

    @Test func isPass_は_trim_後の大文字小文字無視の完全一致のみ_true() {
        #expect(AgoraUtteranceExtraction.isPass("PASS"))
        #expect(AgoraUtteranceExtraction.isPass("pass"))
        #expect(AgoraUtteranceExtraction.isPass("Pass"))
        #expect(AgoraUtteranceExtraction.isPass("  PASS \n"))
        #expect(!AgoraUtteranceExtraction.isPass("PASS。"))
        #expect(!AgoraUtteranceExtraction.isPass("I pass"))
        #expect(!AgoraUtteranceExtraction.isPass("PASS したいが一点だけ補足する"))
        #expect(!AgoraUtteranceExtraction.isPass(""))
    }

    // MARK: - sanitizedLine

    @Test func sanitizedLine_は改行連続を単一の区切りに置換する() {
        #expect(AgoraUtteranceExtraction.sanitizedLine("a\nb") == "a ⏎ b")
        #expect(AgoraUtteranceExtraction.sanitizedLine("a\n\n\r\nb") == "a ⏎ b")
    }

    @Test func sanitizedLine_はタブ以外の制御文字を除去する() {
        let input = "a\u{1B}[31mb\u{7F}c\td"
        let result = AgoraUtteranceExtraction.sanitizedLine(input)
        #expect(result == "a[31mbc\td")
    }

    @Test func sanitizedLine_の結果が空白のみなら空文字列() {
        #expect(AgoraUtteranceExtraction.sanitizedLine("\n\n") == "")
        #expect(AgoraUtteranceExtraction.sanitizedLine("   ") == "")
    }
}
