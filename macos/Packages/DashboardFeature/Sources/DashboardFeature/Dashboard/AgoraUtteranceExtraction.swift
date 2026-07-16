import Foundation
import SessionFeature

/// 討論参加者（appServer チャット）の transcript から「このターンの発言」を切り出す純関数群
/// （task-2 契約・AcceptanceAgoraUtteranceTests が凍結）。セマンティクスの正本は tasks/task-2.md。
public enum AgoraUtteranceExtraction {
    /// afterItemID より後（nil は全件・未発見はフォールバックで全件）の .agentMessage のみを
    /// 出現順に "\n\n" 区切りで結合して返す。該当なしは nil。
    public static func utterance(transcript: [ChatItem], afterItemID: String?) -> String? {
        let startIndex: [ChatItem].Index
        if let afterItemID,
           let boundaryIndex = transcript.lastIndex(where: { $0.id == afterItemID }) {
            startIndex = transcript.index(after: boundaryIndex)
        } else {
            startIndex = transcript.startIndex
        }

        let texts = transcript[startIndex...].compactMap { item -> String? in
            if case .agentMessage(_, let text, _) = item {
                return text
            }
            return nil
        }

        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    /// trim 後に大文字小文字無視で "PASS" と完全一致する時のみ true。
    public static func isPass(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("PASS") == .orderedSame
    }

    /// MessagingService の制御文字拒否に合わせた1行整形（改行連続→" ⏎ "・制御文字除去）。
    public static func sanitizedLine(_ text: String) -> String {
        var segments: [String] = []
        var currentSegment = ""
        var isInsideNewlineRun = false

        for scalar in text.unicodeScalars {
            if scalar == "\r" || scalar == "\n" {
                if !isInsideNewlineRun {
                    segments.append(currentSegment)
                    currentSegment = ""
                }
                isInsideNewlineRun = true
                continue
            }

            isInsideNewlineRun = false
            if isRejectedControlCharacter(scalar) {
                continue
            }
            currentSegment.append(String(scalar))
        }
        segments.append(currentSegment)

        let visibleSegments = segments.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return visibleSegments.joined(separator: " ⏎ ")
    }

    private static func isRejectedControlCharacter(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        if scalar == "\u{1B}" {
            return true
        }
        if value == 0x7F {
            return true
        }
        return value < 0x20 && value != 0x09
    }
}
