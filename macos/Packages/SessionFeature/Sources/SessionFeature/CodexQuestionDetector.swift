// マーカー文字列（いずれも実機の Codex 出力で確認済み・2系統）:
// - "press enter to confirm": 選択式プロンプト(プラン承認等)のフッタ。
//   実機: "Press enter to confirm or esc to go back"。
// - "submit answer" + 補強シグナル: elicitation 質問UI。
//   実機: "Question 1/1 (1 unanswered) ... tab to add notes | enter to submit answer | esc to interrupt"。
// TODO(平文質問・別系統): モデルが構造化UIではなく平文で質問する系統は未カバー。
//   同じ idle 固着が起き得るが、確実なマーカーが無く別途要検討。

import Foundation

internal enum CodexQuestionDetector {
    /// 実機確認済み: 選択式プロンプト(プラン承認等)のフッタ。
    private static let confirmFooter = "press enter to confirm"
    /// 実機確認済み: elicitation 質問UI の主アンカー。
    private static let primaryAnchor = "submit answer"
    private static let reinforcingSignals = [
        "unanswered",
        "question",
        "tab to add notes",
    ]

    /// Codex の対話的プロンプト(承認/質問)が可視テキストに表示されているかを判定する純粋関数。
    static func isQuestionVisible(in text: String) -> Bool {
        let normalized = text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        // 主軸: 選択式プロンプトのフッタ（実機確認済み）。
        if normalized.contains(confirmFooter) { return true }

        // 副系統: elicitation 質問UI（暫定マーカー）。
        guard normalized.contains(primaryAnchor) else { return false }
        return reinforcingSignals.contains { normalized.contains($0) }
    }
}
