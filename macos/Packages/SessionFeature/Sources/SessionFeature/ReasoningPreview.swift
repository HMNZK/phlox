import Foundation

// task-5 契約の PM スタブ。API 表面は受け入れテスト
// ReasoningPreviewAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-5.md

/// 実行中の Thinking 表示に添える推論テキストのプレビュー（末尾 N 行）。
enum ReasoningPreview {
    /// 空白のみの行を除いた末尾 maxLines 行を `\n` 結合で返す。全体が空なら ""。
    static func tail(_ text: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        let nonBlankLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonBlankLines.isEmpty else { return "" }
        return nonBlankLines.suffix(maxLines).joined(separator: "\n")
    }
}
