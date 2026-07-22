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

    @Test
    func removing_doesNotMatchDifferentNumberWithSamePrefix() {
        // "[Image #1]" が "[Image #12]" の一部として誤マッチしないこと。
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "[Image #12]") == "[Image #12]")
    }
}
