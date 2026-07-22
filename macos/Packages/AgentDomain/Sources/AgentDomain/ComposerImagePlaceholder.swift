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
        text.contains(Self.text(for: number))
    }

    /// 本文の編集で消えたプレースホルダの番号を返す。
    /// **oldText に無かった番号は決して返さない**（本文に紐づかない添付を誤って外さないための安全弁）。
    public static func numbersRemoved(from oldText: String, to newText: String, among numbers: [Int]) -> [Int] {
        numbers.filter { number in
            contains(number: number, in: oldText) && !contains(number: number, in: newText)
        }
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

    // task-5 契約の PM スタブ。API 表面は受け入れテスト
    // ComposerImagePlaceholderAcceptanceTests が凍結している（シグネチャ変更禁止）。
    // 実装契約の正本: tasks/task-5.md

    /// トークン単位削除の方向。
    public enum DeleteDirection {
        /// Backspace。カーソル直前のトークンを対象にする。
        case backward
        /// Delete（前方削除）。カーソル直後のトークンを対象にする。
        case forward
    }

    /// 本文中の番号 `number` のプレースホルダが占める UTF-16 範囲（最初の1件）。
    public static func tokenRangeUTF16(of number: Int, in text: String) -> Range<Int>? {
        guard let range = text.range(of: Self.text(for: number)) else { return nil }
        let lower = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
        let upper = text.utf16.distance(from: text.utf16.startIndex, to: range.upperBound)
        return lower..<upper
    }

    /// Backspace / Delete で「まとめて消す」範囲（隣接スペースの畳み込みを含む）。
    /// カーソルがどのトークンにも掛かっていなければ nil（＝通常の1文字削除に委ねる）。
    public static func deletionRangeUTF16(
        at cursorUTF16: Int,
        in text: String,
        numbers: [Int],
        direction: DeleteDirection
    ) -> Range<Int>? {
        let hit = numbers.compactMap { tokenRangeUTF16(of: $0, in: text) }.first { range in
            switch direction {
            case .backward:
                // カーソルがトークンの先頭にあるときは対象外（直前の1文字を消す通常動作）。
                return cursorUTF16 > range.lowerBound && cursorUTF16 <= range.upperBound
            case .forward:
                return cursorUTF16 >= range.lowerBound && cursorUTF16 < range.upperBound
            }
        }
        guard let hit else { return nil }
        return spaceCollapsedRange(forToken: hit, in: text)
    }

    /// 選択の端 `edgeUTF16` がプレースホルダを分断しているか（トークンの内側・両端は含まない）。
    /// 分断している間は選択の移動を繰り返して、トークンの外へ抜けさせる。
    public static func selectionEdgeSplitsPlaceholder(
        _ edgeUTF16: Int,
        in text: String,
        numbers: [Int]
    ) -> Bool {
        numbers.compactMap { tokenRangeUTF16(of: $0, in: text) }.contains {
            edgeUTF16 > $0.lowerBound && edgeUTF16 < $0.upperBound
        }
    }

    /// 編集でトークンが壊れたとき、残骸ごと取り除いた本文とカーソル位置を返す。
    /// 打鍵を横取りできない iOS の入力欄で「まとめて消えた」ように見せるための後追い修復。
    /// - Parameter preserving: 本文に無傷で残っている他の番号。差分推定を誤って
    ///   これらを壊す修復になる場合は、修復せず nil を返す（残骸が残る方がまだ安全なため）。
    public static func repairingBrokenPlaceholder(
        number: Int,
        oldText: String,
        newText: String,
        preserving otherNumbers: [Int] = []
    ) -> (text: String, cursorUTF16: Int)? {
        guard let token = tokenRangeUTF16(of: number, in: oldText) else { return nil }
        let old = Array(oldText.utf16)
        let new = Array(newText.utf16)

        // 編集されていない共通の接頭・接尾を求め、間に挟まれた範囲を「ユーザーの編集」とみなす。
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        // サロゲートペアの途中で切ると U+FFFD になるので、境界まで戻す。
        if prefix > 0, isHighSurrogate(old[prefix - 1]) {
            prefix -= 1
        }
        if suffix > 0, suffix < old.count, isLowSurrogate(old[old.count - suffix]) {
            suffix -= 1
        }
        let oldEditEnd = old.count - suffix
        let newEditEnd = new.count - suffix
        guard prefix <= oldEditEnd, prefix <= newEditEnd else { return nil }

        // 編集範囲とトークン範囲の和を丸ごと落とす（＝トークンの残骸を残さない）。
        let deleteStart = min(token.lowerBound, prefix)
        let deleteEnd = max(token.upperBound, oldEditEnd)
        let inserted = Array(new[prefix..<newEditEnd])

        let units = Array(old[0..<deleteStart]) + inserted + Array(old[deleteEnd...])
        var cursor = deleteStart + inserted.count
        var result = String(decoding: units, as: UTF16.self)

        // ユーザーの編集がトークンを丸ごと消していれば残骸は無い＝修復不要。
        // ここで抜けないと、無関係な範囲削除のたびに区切りスペースを勝手に畳んでしまう。
        guard result != newText else { return nil }

        // 文字を打ち込んだ編集では区切りを畳まない（削除のときだけ）。
        if inserted.isEmpty {
            let collapsed = collapseAdjacentSpace(atDeletionUTF16: deleteStart, in: result)
            if collapsed != result {
                if cursor > deleteStart { cursor -= 1 }
                result = collapsed
            }
        }

        // 差分推定は「消された文字列が周囲と似ている」ときに外れる。無傷で残っている他の
        // プレースホルダを壊す結果になったら、その推定は信用せず修復を諦める。
        for other in otherNumbers where contains(number: other, in: newText) {
            guard contains(number: other, in: result) else { return nil }
        }

        return (result, max(0, min(cursor, result.utf16.count)))
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
    private static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }

    /// トークン範囲に、`removing(number:from:)` と同じ規則で隣接スペース1つを含めた範囲。
    private static func spaceCollapsedRange(forToken token: Range<Int>, in text: String) -> Range<Int> {
        let units = Array(text.utf16)
        let space = UInt16(UnicodeScalar(" ").value)

        // 規則A: 直後が半角スペースで、先頭または直前が空白・改行ならそのスペースも消す。
        if token.upperBound < units.count, units[token.upperBound] == space {
            let beforeIsBoundary = token.lowerBound == 0
                || isWhitespaceOrNewlineUnit(units[token.lowerBound - 1])
            if beforeIsBoundary {
                return token.lowerBound..<(token.upperBound + 1)
            }
        }
        // 規則B: 末尾で直前が半角スペースならそのスペースも消す。
        if token.upperBound >= units.count, token.lowerBound > 0, units[token.lowerBound - 1] == space {
            return (token.lowerBound - 1)..<token.upperBound
        }
        return token
    }

    private static func isWhitespaceOrNewlineUnit(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return Character(scalar).isWhitespace
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
