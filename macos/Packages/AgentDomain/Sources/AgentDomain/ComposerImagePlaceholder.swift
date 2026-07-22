import Foundation

// task-1 契約の PM スタブ。API 表面は受け入れテスト
// ComposerImagePlaceholderAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-1.md
//
// macOS アプリ（SessionFeature）と iOS アプリ（PhloxKit）の双方が参照する共有面。
// 「本文へ埋め込む画像プレースホルダ」の表記と挿入・削除の規則をここ1箇所で決める。

/// 本文テキストに埋め込む画像プレースホルダ（`[Image #1]`）の生成・挿入・削除。
/// すべて純関数（グローバル状態・日時・乱数に依存しない）。
public enum ComposerImagePlaceholder {
    /// 番号 `number` のプレースホルダ文字列。
    public static func text(for number: Int) -> String {
        "[Image #\(number)]"
    }

    /// 既存の番号列から次に振る番号を決める。欠番は詰めない。
    public static func nextNumber(after existingNumbers: [Int]) -> Int {
        (existingNumbers.max() ?? 0) + 1
    }

    /// `cursorUTF16` の位置にプレースホルダを挿入し、挿入後のテキストとカーソル位置を返す。
    public static func inserting(
        number: Int,
        into text: String,
        cursorUTF16: Int
    ) -> (text: String, cursorUTF16: Int) {
        let insertIndex = characterBoundaryIndex(atUTF16Offset: cursorUTF16, in: text)
        let insertUTF16 = text.utf16.distance(from: text.utf16.startIndex, to: insertIndex)

        let lead = leadingSpace(before: insertIndex, in: text)
        let trail = trailingSpace(after: insertIndex, in: text)
        let insertion = lead + Self.text(for: number) + trail

        var result = text
        result.insert(contentsOf: insertion, at: insertIndex)

        let newCursorUTF16 = insertUTF16 + insertion.utf16.count
        return (result, newCursorUTF16)
    }

    // task-4 契約の PM スタブ。API 表面は受け入れテスト
    // ComposerImagePlaceholderAcceptanceTests が凍結している（シグネチャ変更禁止）。
    // 実装契約の正本: tasks/task-4.md

    /// 本文に番号 `number` のプレースホルダが含まれるか（トークン全体の一致で判定する）。
    public static func contains(number: Int, in text: String) -> Bool {
        false
    }

    /// 本文の編集で消えたプレースホルダの番号を返す。
    /// **oldText に無かった番号は決して返さない**（本文に紐づかない添付を誤って外さないための安全弁）。
    public static func numbersRemoved(from oldText: String, to newText: String, among numbers: [Int]) -> [Int] {
        []
    }

    /// 本文から番号 `number` のプレースホルダを1つ取り除く。
    public static func removing(number: Int, from text: String) -> String {
        let token = Self.text(for: number)
        guard let range = text.range(of: token) else {
            return text
        }

        let deletionUTF16 = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
        var result = text
        result.removeSubrange(range)

        return collapseAdjacentSpace(atDeletionUTF16: deletionUTF16, in: result)
    }

    // MARK: - Insertion helpers

    private static func characterBoundaryIndex(atUTF16Offset offset: Int, in text: String) -> String.Index {
        let clamped = max(0, min(offset, text.utf16.count))
        if clamped == 0 {
            return text.startIndex
        }
        if clamped >= text.utf16.count {
            return text.endIndex
        }

        let index = String.Index(utf16Offset: clamped, in: text)
        let charRange = text.rangeOfComposedCharacterSequence(at: index)
        if charRange.lowerBound == index {
            return index
        }
        return charRange.lowerBound
    }

    private static func leadingSpace(before index: String.Index, in text: String) -> String {
        guard index > text.startIndex else { return "" }
        let previousIndex = text.index(before: index)
        let previous = text[previousIndex]
        if isWhitespaceOrNewline(previous) {
            return ""
        }
        return " "
    }

    private static func trailingSpace(after index: String.Index, in text: String) -> String {
        guard index < text.endIndex else { return " " }
        let next = text[index]
        if isWhitespaceOrNewline(next) {
            return ""
        }
        return " "
    }

    private static func isWhitespaceOrNewline(_ character: Character) -> Bool {
        character == " " || character == "\n" || character == "\t" || character.isWhitespace
    }

    // MARK: - Removal helpers

    private static func collapseAdjacentSpace(atDeletionUTF16 deletionUTF16: Int, in text: String) -> String {
        var result = text
        let utf16Count = result.utf16.count

        // 規則A: 削除位置の直後が半角スペースで、先頭または直前が空白・改行ならそのスペースを削除
        if deletionUTF16 < utf16Count {
            let index = String.Index(utf16Offset: deletionUTF16, in: result)
            if result[index] == " " {
                let beforeIsWhitespaceOrNewline: Bool
                if deletionUTF16 == 0 {
                    beforeIsWhitespaceOrNewline = true
                } else {
                    let beforeIndex = String.Index(utf16Offset: deletionUTF16 - 1, in: result)
                    beforeIsWhitespaceOrNewline = isWhitespaceOrNewline(result[beforeIndex])
                }

                if beforeIsWhitespaceOrNewline {
                    result.remove(at: index)
                    return result
                }
            }
        }

        // 規則B: 削除位置が末尾で直前が半角スペースならそのスペースを削除
        if deletionUTF16 >= utf16Count, deletionUTF16 > 0 {
            let beforeIndex = String.Index(utf16Offset: deletionUTF16 - 1, in: result)
            if result[beforeIndex] == " " {
                result.remove(at: beforeIndex)
            }
        }

        return result
    }
}
