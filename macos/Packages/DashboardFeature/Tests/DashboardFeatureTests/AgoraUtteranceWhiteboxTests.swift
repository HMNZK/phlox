import Foundation
import Testing
import SessionFeature
@testable import DashboardFeature

private let agoraUtteranceWhiteboxDate = Date(timeIntervalSince1970: 2_000_000)

private func whiteboxAgent(_ id: String, _ text: String) -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: agoraUtteranceWhiteboxDate)
}

@Suite("AgoraUtteranceExtraction whitebox (task-2)")
struct AgoraUtteranceWhiteboxTests {
    @Test func afterItemID_が末尾なら_nil_を返す() {
        let transcript: [ChatItem] = [
            whiteboxAgent("a1", "old"),
            whiteboxAgent("a2", "tail"),
        ]

        #expect(AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "a2") == nil)
    }

    @Test func afterItemID_が重複する場合は最後の出現を排他境界にする() {
        let transcript: [ChatItem] = [
            whiteboxAgent("dup", "old duplicate"),
            whiteboxAgent("a1", "between duplicates"),
            whiteboxAgent("dup", "latest duplicate"),
            whiteboxAgent("a2", "after latest duplicate"),
        ]

        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: "dup")

        #expect(result == "after latest duplicate")
    }

    @Test func 絵文字や結合文字を含む_text_をそのまま結合する() {
        let transcript: [ChatItem] = [
            whiteboxAgent("a1", "👩🏽‍💻 cafe\u{301}"),
            whiteboxAgent("a2", "次の発言 🚀"),
        ]

        let result = AgoraUtteranceExtraction.utterance(transcript: transcript, afterItemID: nil)

        #expect(result == "👩🏽‍💻 cafe\u{301}\n\n次の発言 🚀")
    }

    @Test func 空_transcript_は_nil_を返す() {
        #expect(AgoraUtteranceExtraction.utterance(transcript: [], afterItemID: "missing") == nil)
    }
}
