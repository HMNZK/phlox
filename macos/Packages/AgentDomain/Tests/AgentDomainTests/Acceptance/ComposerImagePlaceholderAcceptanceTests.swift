// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — 本文へ埋め込む画像プレースホルダ `[Image #N]` の
// 生成・採番・挿入・削除の純関数層。macOS / iOS 双方の共有面のため、
// ここで凍結した振る舞いは task-2 / task-3 の前提になる。
//
// アサーションは変更禁止。ただしテストハーネス自体の欠陥を見つけた場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import AgentDomain

@Suite("task-1: 画像プレースホルダの純関数層")
struct ComposerImagePlaceholderAcceptanceTests {

    // MARK: - text(for:)

    @Test
    func text_usesClaudeCodeStyleToken() {
        #expect(ComposerImagePlaceholder.text(for: 1) == "[Image #1]")
        #expect(ComposerImagePlaceholder.text(for: 4) == "[Image #4]")
        #expect(ComposerImagePlaceholder.text(for: 12) == "[Image #12]")
    }

    // MARK: - nextNumber(after:)

    @Test
    func nextNumber_startsAtOneAndNeverReusesGaps() {
        #expect(ComposerImagePlaceholder.nextNumber(after: []) == 1)
        #expect(ComposerImagePlaceholder.nextNumber(after: [1]) == 2)
        #expect(ComposerImagePlaceholder.nextNumber(after: [1, 2, 3]) == 4)
        // 欠番は詰めない: 2 を削除しても次は 4。
        #expect(ComposerImagePlaceholder.nextNumber(after: [1, 3]) == 4)
        #expect(ComposerImagePlaceholder.nextNumber(after: [3]) == 4)
    }

    // MARK: - inserting(number:into:cursorUTF16:)

    @Test
    func inserting_intoEmptyText_appendsTokenWithTrailingSpace() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "", cursorUTF16: 0)
        #expect(result.text == "[Image #1] ")
        #expect(result.cursorUTF16 == 11)
    }

    @Test
    func inserting_atEndAfterNonSpace_addsSpacesOnBothSides() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "見て", cursorUTF16: 2)
        #expect(result.text == "見て [Image #1] ")
        #expect(result.cursorUTF16 == 14)
    }

    @Test
    func inserting_inMiddle_addsSpacesOnBothSides() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "ab", cursorUTF16: 1)
        #expect(result.text == "a [Image #1] b")
        #expect(result.cursorUTF16 == 13)
    }

    @Test
    func inserting_whenNeighborsAreAlreadySpaces_doesNotDoubleThem() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "a  b", cursorUTF16: 2)
        #expect(result.text == "a [Image #1] b")
        #expect(result.cursorUTF16 == 12)
    }

    @Test
    func inserting_afterNewline_doesNotAddLeadingSpace() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "a\n", cursorUTF16: 2)
        #expect(result.text == "a\n[Image #1] ")
        #expect(result.cursorUTF16 == 13)
    }

    @Test
    func inserting_usesGivenNumber() {
        let result = ComposerImagePlaceholder.inserting(number: 3, into: "", cursorUTF16: 0)
        #expect(result.text == "[Image #3] ")
        #expect(result.cursorUTF16 == 11)
    }

    @Test
    func inserting_atSurrogatePairBoundary_roundsDownAndKeepsTextIntact() {
        // "🐶" は UTF-16 で2単位。境界を割る位置(1)は直前の文字境界(0)へ丸める。
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "🐶", cursorUTF16: 1)
        #expect(result.text == "[Image #1] 🐶")
        #expect(result.cursorUTF16 == 11)
    }

    @Test
    func inserting_afterEmoji_addsLeadingSpace() {
        let result = ComposerImagePlaceholder.inserting(number: 1, into: "🐶", cursorUTF16: 2)
        #expect(result.text == "🐶 [Image #1] ")
        #expect(result.cursorUTF16 == 14)
    }

    @Test
    func inserting_clampsOutOfRangeCursor() {
        let negative = ComposerImagePlaceholder.inserting(number: 1, into: "ab", cursorUTF16: -5)
        #expect(negative.text == "[Image #1] ab")
        #expect(negative.cursorUTF16 == 11)

        let tooLarge = ComposerImagePlaceholder.inserting(number: 1, into: "ab", cursorUTF16: 999)
        #expect(tooLarge.text == "ab [Image #1] ")
        #expect(tooLarge.cursorUTF16 == 14)
    }

    // MARK: - removing(number:from:)

    @Test
    func removing_collapsesTheSpaceItLeavesBehind() {
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "a [Image #1] b") == "a b")
    }

    @Test
    func removing_atStart_dropsTrailingSpace() {
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "[Image #1] ") == "")
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "[Image #1] rest") == "rest")
    }

    @Test
    func removing_atEnd_dropsLeadingSpace() {
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "a [Image #1]") == "a")
    }

    @Test
    func removing_afterNewline_dropsTrailingSpaceButKeepsNewline() {
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "a\n[Image #1] b") == "a\nb")
    }

    @Test
    func removing_whenNoAdjacentSpaces_touchesNothingElse() {
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "見て[Image #1]です") == "見てです")
        // 直前が非空白なら、直後のスペースは区切りとして残す。
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "a[Image #1] b") == "a b")
    }

    @Test
    func removing_missingNumber_returnsTextUnchanged() {
        #expect(ComposerImagePlaceholder.removing(number: 2, from: "a [Image #1] b") == "a [Image #1] b")
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "") == "")
    }

    @Test
    func removing_dropsOnlyTheFirstOccurrence() {
        #expect(
            ComposerImagePlaceholder.removing(number: 1, from: "[Image #1][Image #1]") == "[Image #1]"
        )
    }

    // MARK: - contains(number:in:) / numbersRemoved(from:to:among:)（task-4）

    @Test
    func contains_matchesWholeTokenOnly() {
        #expect(ComposerImagePlaceholder.contains(number: 1, in: "a [Image #1] b"))
        #expect(ComposerImagePlaceholder.contains(number: 1, in: "[Image #1]"))
        #expect(!ComposerImagePlaceholder.contains(number: 1, in: "a b"))
        #expect(!ComposerImagePlaceholder.contains(number: 1, in: ""))
        // "[Image #1]" は "[Image #12]" の一部として誤マッチしない。
        #expect(!ComposerImagePlaceholder.contains(number: 1, in: "[Image #12]"))
        #expect(ComposerImagePlaceholder.contains(number: 12, in: "[Image #12]"))
    }

    @Test
    func numbersRemoved_returnsOnlyPlaceholdersThatDisappeared() {
        let old = "[Image #1] [Image #2] hi"
        let new = "[Image #2] hi"
        #expect(ComposerImagePlaceholder.numbersRemoved(from: old, to: new, among: [1, 2]) == [1])
    }

    @Test
    func numbersRemoved_keepsTheGivenOrder() {
        let old = "[Image #1] [Image #2] [Image #3]"
        let new = "[Image #2]"
        #expect(ComposerImagePlaceholder.numbersRemoved(from: old, to: new, among: [1, 2, 3]) == [1, 3])
    }

    @Test
    func numbersRemoved_neverReportsNumbersThatWereNotInTheOldText() {
        // 本文に紐づいていない添付（例: Control API 経由で積まれた画像）を、
        // 無関係な編集で誤って外さないための安全弁。
        #expect(ComposerImagePlaceholder.numbersRemoved(from: "hi", to: "hello", among: [1, 2]).isEmpty)
        // 挿入直後（old に無く new に在る）も外さない。
        #expect(ComposerImagePlaceholder.numbersRemoved(from: "hi", to: "hi [Image #1] ", among: [1]).isEmpty)
    }

    @Test
    func numbersRemoved_isEmptyWhenNothingChanged() {
        let text = "[Image #1] hi"
        #expect(ComposerImagePlaceholder.numbersRemoved(from: text, to: text, among: [1]).isEmpty)
        #expect(ComposerImagePlaceholder.numbersRemoved(from: text, to: "", among: []).isEmpty)
    }

    @Test
    func numbersRemoved_detectsPartialDeletionOfTheToken() {
        // 末尾の "]" を1文字消しただけでもトークンとしては消えたとみなす。
        #expect(ComposerImagePlaceholder.numbersRemoved(from: "[Image #1] ", to: "[Image #1 ", among: [1]) == [1])
    }

    // MARK: - トークン単位削除（task-5）

    @Test
    func tokenRange_locatesTheTokenInUTF16() {
        #expect(ComposerImagePlaceholder.tokenRangeUTF16(of: 1, in: "a [Image #1] b") == 2..<12)
        // "見て" は UTF-16 で2単位。
        #expect(ComposerImagePlaceholder.tokenRangeUTF16(of: 2, in: "見て[Image #2]") == 2..<12)
        #expect(ComposerImagePlaceholder.tokenRangeUTF16(of: 3, in: "a b") == nil)
    }

    @Test
    func deletionRange_backspaceAtTheEndOfTheTokenTakesTheWholeToken() {
        // "[Image #1] テスト" の "]" の直後で Backspace → トークン全体＋畳んだスペース。
        let text = "[Image #1] テスト"
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 10, in: text, numbers: [1], direction: .backward
            ) == 0..<11
        )
    }

    @Test
    func deletionRange_backspaceInTheMiddleOfTheTokenTakesTheWholeToken() {
        let text = "a [Image #1] b"
        // "#1" の "1" の直後。
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 10, in: text, numbers: [1], direction: .backward
            ) == 2..<13
        )
    }

    @Test
    func deletionRange_backspaceAtTheTokenStart_isNotAtomic() {
        // トークンの手前の1文字を消す通常動作に委ねる。
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 2, in: "a [Image #1] b", numbers: [1], direction: .backward
            ) == nil
        )
    }

    @Test
    func deletionRange_forwardDeleteAtTheTokenStartTakesTheWholeToken() {
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 0, in: "[Image #1] テスト", numbers: [1], direction: .forward
            ) == 0..<11
        )
        // トークンの直後では対象外。
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 10, in: "[Image #1] テスト", numbers: [1], direction: .forward
            ) == nil
        )
    }

    @Test
    func deletionRange_outsideAnyToken_isNil() {
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 3, in: "abc", numbers: [1], direction: .backward
            ) == nil
        )
        // 番号が渡されていなければ対象にしない。
        #expect(
            ComposerImagePlaceholder.deletionRangeUTF16(
                at: 10, in: "[Image #1] ", numbers: [], direction: .backward
            ) == nil
        )
    }

    @Test
    func deletionRange_matchesWhatRemovingWouldProduce() {
        // 打鍵経路（トークン単位削除）とチップ × 経路（removing）の結果が食い違わないこと。
        let cases = ["a [Image #1] b", "[Image #1] rest", "a [Image #1]", "a\n[Image #1] b", "見て[Image #1]です"]
        for text in cases {
            let range = ComposerImagePlaceholder.deletionRangeUTF16(
                at: ComposerImagePlaceholder.tokenRangeUTF16(of: 1, in: text)!.upperBound,
                in: text,
                numbers: [1],
                direction: .backward
            )
            var units = Array(text.utf16)
            units.removeSubrange(range!)
            #expect(String(decoding: units, as: UTF16.self) == ComposerImagePlaceholder.removing(number: 1, from: text))
        }
    }

    // MARK: - 壊れたトークンの後追い修復（task-5 / iOS）

    @Test
    func repairing_afterDeletingTheClosingBracket_removesTheWholeToken() {
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "[Image #1] テスト", newText: "[Image #1 テスト"
        )
        #expect(repaired?.text == "テスト")
        #expect(repaired?.cursorUTF16 == 0)
    }

    @Test
    func repairing_afterDeletingACharInTheMiddle_removesTheWholeToken() {
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "a [Image #1] b", newText: "a [Image #] b"
        )
        #expect(repaired?.text == "a b")
        #expect(repaired?.cursorUTF16 == 2)
    }

    @Test
    func repairing_afterDeletingTheOpeningBracket_removesTheWholeToken() {
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "a [Image #1] b", newText: "a Image #1] b"
        )
        #expect(repaired?.text == "a b")
    }

    @Test
    func repairing_whenTheEditAlreadyRemovedTheWholeToken_isNil() {
        // 残骸が無いので修復不要。
        #expect(
            ComposerImagePlaceholder.repairingBrokenPlaceholder(
                number: 1, oldText: "a [Image #1] b", newText: "a  b"
            ) == nil
        )
    }

    @Test
    func repairing_whenTheTokenWasNotInTheOldText_isNil() {
        #expect(
            ComposerImagePlaceholder.repairingBrokenPlaceholder(
                number: 1, oldText: "hi", newText: "h"
            ) == nil
        )
    }

    @Test
    func repairing_keepsTypedTextAndDoesNotCollapseSpaces() {
        // トークンを選択して文字を打った場合、打った文字は残す。
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "a [Image #1] b", newText: "a X] b"
        )
        #expect(repaired?.text == "a X b")
    }

    @Test
    func repairing_leavesOtherPlaceholdersIntact() {
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "[Image #1] [Image #2] ", newText: "[Image #1 [Image #2] "
        )
        #expect(repaired?.text == "[Image #2] ")
    }

    // MARK: - トークン単位の選択（task-7）

    @Test
    func selectionEdgeSplitsPlaceholder_isTrueOnlyStrictlyInsideTheToken() {
        let text = "a [Image #1] b"
        #expect(ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(3, in: text, numbers: [1]))
        #expect(ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(11, in: text, numbers: [1]))
        // 両端は分断していない（そこで止まってよい）。
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(2, in: text, numbers: [1]))
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(12, in: text, numbers: [1]))
    }

    @Test
    func snappedSelection_extendsOverTheWholeToken() {
        let text = "x [Image #1] y"   // トークンは 2..<12
        // キャレット12から左へ伸ばすと、下端はトークンの左端まで一気に寄る。
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 12..<12, to: 11..<12, in: text, numbers: [1]
            ) == 2..<12
        )
        // キャレット2から右へ伸ばすと、上端はトークンの右端まで一気に寄る。
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 2..<2, to: 2..<3, in: text, numbers: [1]
            ) == 2..<12
        )
    }

    @Test
    func snappedSelection_shrinksBackTheSameWay() {
        let text = "x [Image #1] y"
        // 起点12・下端2の選択から下端を右へ戻すと、トークンの右端＝起点まで戻る（空選択）。
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 2..<12, to: 3..<12, in: text, numbers: [1]
            ) == 12..<12
        )
    }

    @Test
    func snappedSelection_whenTheAnchorSitsInsideAToken_swallowsTheWholeToken() {
        // 起点（動かなかった端）が内側に残っていたら、外側へ寄せてトークンを丸ごと含める。
        let text = "x [Image #1] y"
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 7..<7, to: 6..<7, in: text, numbers: [1]
            ) == 2..<12
        )
    }

    @Test
    func snappedSelection_dragOverAToken_swallowsItWhole() {
        // マウスのドラッグは追跡中に通知が来ず、確定の1回で「ドラッグ前の選択」が old に入る。
        // どちらの端も引き継いでいない＝新しく引かれた選択として扱い、掛かるトークンを丸ごと含める。
        let text = "x [Image #1] y"   // トークンは 2..<12
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 12..<12, to: 6..<14, in: text, numbers: [1]
            ) == 2..<14
        )
    }

    @Test
    func snappedSelection_doubleClickInsideAToken_selectsTheWholeToken() {
        let text = "x [Image #1] y"
        // "Image" をダブルクリックした相当（3..<8）。
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 12..<12, to: 3..<8, in: text, numbers: [1]
            ) == 2..<12
        )
    }

    @Test
    func snappedSelection_clickInsideAToken_placesTheCaretOutside() {
        let text = "x [Image #1] y"
        let result = ComposerImagePlaceholder.snappedSelectionUTF16(
            from: 0..<0, to: 7..<7, in: text, numbers: [1]
        )
        #expect(result.isEmpty)
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(
            result.lowerBound, in: text, numbers: [1]
        ))
    }

    @Test
    func snappedSelection_withAbsurdlyLongDigits_doesNotCrash() {
        // 選択が変わるたびに走る経路。長い数字列で桁を積み上げて Int があふれてはならない。
        let text = "[Image #" + String(repeating: "9", count: 40) + "] hi"
        _ = ComposerImagePlaceholder.snappedSelectionUTF16(
            from: 0..<0, to: 5..<5, in: text, numbers: [1, 999_999_999]
        )
        #expect(ComposerImagePlaceholder.tokenRangeUTF16(of: 1, in: text) == nil)
    }

    @Test
    func snappedSelection_doesNotTreatLeadingZeroAsTheSameNumber() {
        // `text(for:)` は `[Image #01]` を作らない。どの層も同じ表記だけをトークンとみなす。
        let text = "x [Image #01] y"
        #expect(!ComposerImagePlaceholder.contains(number: 1, in: text))
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 13..<13, to: 12..<13, in: text, numbers: [1]
            ) == 12..<13
        )
    }

    @Test
    func snappedSelection_leavesSelectionsThatDoNotSplitATokenAlone() {
        let text = "x [Image #1] y"
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 14..<14, to: 13..<14, in: text, numbers: [1]
            ) == 13..<14
        )
        // 番号が渡されていなければ特別扱いしない。
        #expect(
            ComposerImagePlaceholder.snappedSelectionUTF16(
                from: 12..<12, to: 11..<12, in: text, numbers: []
            ) == 11..<12
        )
    }

    @Test
    func selectionEdgeSplitsPlaceholder_isFalseOutsideAnyToken() {
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(1, in: "a [Image #1] b", numbers: [1]))
        // 番号が渡されていなければ特別扱いしない。
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(5, in: "a [Image #1] b", numbers: []))
    }

    @Test
    func repairing_neverBreaksAnIntactPlaceholder() {
        // 1つ目のトークンを範囲選択で消したケース。差分推定が外れても、無傷の2つ目を壊さない。
        #expect(
            ComposerImagePlaceholder.repairingBrokenPlaceholder(
                number: 1,
                oldText: "[Image #1] [Image #2] ",
                newText: "[Image #2] ",
                preserving: [2]
            ) == nil
        )
    }

    @Test
    func repairing_doesNotSplitSurrogatePairs() {
        // 高位サロゲートを共有する絵文字（😀/😃）で差分が絵文字の途中に落ちても U+FFFD を作らない。
        let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
            number: 1, oldText: "😀[Image #1] テスト", newText: "😃[Image #1 テスト"
        )
        #expect(repaired?.text.contains("\u{FFFD}") != true)
    }

    @Test
    func removing_doesNotMatchDifferentNumberWithSamePrefix() {
        // "[Image #1]" が "[Image #12]" の一部として誤マッチしないこと。
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "[Image #12]") == "[Image #12]")
    }
}
