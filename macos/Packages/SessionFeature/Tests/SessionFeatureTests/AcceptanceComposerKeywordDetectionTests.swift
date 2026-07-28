import Foundation
import Testing
@testable import SessionFeature

// task-1 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md
// claude CLI v2.1.220 の検出実装（2026-07-28 実測）を写した規則を凍結する。
//   規則X（ultrathink のみ）: ASCII 語境界・大小無視のみ。除外規則なし。
//   規則Y（ultraplan / ultrareview / ultracode）: 規則X に加えて
//     - text が "/" で始まるなら1件も検出しない
//     - 保護区間（` " < { [ ( '）の内側は除外
//     - 直前が / \ - なら除外、直後が / \ - ? なら除外
//     - 直後が "." かつその次が語構成文字なら除外

private func u16Range(of sub: String, in text: String) -> Range<Int> {
    guard let r = text.range(of: sub) else {
        Issue.record("部分文字列 \(sub) が \(text) に見つからない（ハーネス欠陥）")
        return 0..<0
    }
    return r.lowerBound.utf16Offset(in: text)..<r.upperBound.utf16Offset(in: text)
}

private func keywordSpans(_ text: String) -> [ComposerHighlightSpan] {
    ComposerHighlight.spans(in: text, includingKeywords: true).filter { $0.kind == .keyword }
}

private func keywordRanges(_ text: String) -> [Range<Int>] {
    keywordSpans(text).map(\.range)
}

@Suite("Acceptance: 入力欄の ultra 系キーワード検出（task-1）")
struct AcceptanceComposerKeywordDetectionTests {

    // MARK: - 既存契約の不変性

    @Test("spans(in:) はキーワードを一切返さない（既存契約は不変）")
    func plainSpansNeverReturnKeyword() {
        let text = "ultrathink と ultracode を試す"
        #expect(ComposerHighlight.spans(in: text).allSatisfy { $0.kind != .keyword })
    }

    @Test("includingKeywords: false は spans(in:) と同一の結果を返す")
    func includingKeywordsFalseMatchesPlainSpans() {
        for text in ["ultrathink", "/help me", "hello @file ultracode", ""] {
            #expect(
                ComposerHighlight.spans(in: text, includingKeywords: false)
                    == ComposerHighlight.spans(in: text),
                "includingKeywords: false は既存挙動と一致すること（入力: \(text)）"
            )
        }
    }

    // MARK: - 規則X / 規則Y に共通する語一致

    @Test("4語をそれぞれ検出する")
    func detectsAllFourKeywords() {
        for word in ["ultrathink", "ultraplan", "ultrareview", "ultracode"] {
            let text = "\(word) で進めて"
            #expect(keywordRanges(text) == [u16Range(of: word, in: text)], "\(word) を検出すること")
        }
    }

    @Test("大文字小文字を無視する")
    func matchesCaseInsensitively() {
        let text = "UltraThink で進めて"
        #expect(keywordRanges(text) == [u16Range(of: "UltraThink", in: text)])
    }

    @Test("語の一部に含まれるだけでは検出しない")
    func doesNotMatchInsideLongerWord() {
        #expect(keywordRanges("ultrathinking").isEmpty)
        #expect(keywordRanges("xultrathink").isEmpty)
        #expect(keywordRanges("ultracodes").isEmpty)
        #expect(keywordRanges("myultracode").isEmpty)
    }

    @Test("語境界は ASCII 判定なので、日本語が隣接していても検出する")
    func matchesWhenAdjacentToNonASCII() {
        let text = "今から日本語ultrathinkで調べて"
        #expect(keywordRanges(text) == [u16Range(of: "ultrathink", in: text)])
    }

    @Test("range は UTF16 オフセット（絵文字を含んでも正しい）")
    func rangeIsUTF16Offset() {
        let text = "🎉 ultrathink"
        #expect(keywordRanges(text) == [3..<13])
        #expect(keywordRanges(text) == [u16Range(of: "ultrathink", in: text)])
    }

    @Test("同じ語が複数回現れたら全件返す")
    func returnsEveryOccurrence() {
        let text = "ultrathink して ultrathink する"
        #expect(keywordRanges(text).count == 2)
    }

    // MARK: - 規則X と規則Y の差（"/" 始まりの扱い）

    @Test("入力が / で始まるとき、ultraplan・ultrareview・ultracode は検出しない")
    func slashPrefixedInputSuppressesRqsKeywords() {
        for word in ["ultraplan", "ultrareview", "ultracode"] {
            #expect(keywordRanges("/fix \(word) して").isEmpty, "\(word) は / 始まりで抑止されること")
        }
    }

    @Test("入力が / で始まっても ultrathink は検出する")
    func slashPrefixedInputStillDetectsUltrathink() {
        let text = "/fix ultrathink して"
        #expect(keywordRanges(text) == [u16Range(of: "ultrathink", in: text)])
    }

    // MARK: - 規則Y の保護区間

    @Test("引用符・バッククォート・波括弧・角括弧・丸括弧の内側は検出しない")
    func skipsProtectedRegions() {
        #expect(keywordRanges("\"ultracode\" とは何か").isEmpty)
        #expect(keywordRanges("`ultracode` とは何か").isEmpty)
        #expect(keywordRanges("{ultracode} とは何か").isEmpty)
        #expect(keywordRanges("[ultracode] とは何か").isEmpty)
        #expect(keywordRanges("(ultracode) とは何か").isEmpty)
    }

    @Test("< は次が英字かスラッシュのときだけ保護を開始する")
    func angleBracketOpensOnlyBeforeLetterOrSlash() {
        #expect(keywordRanges("<ultracode> とは").isEmpty, "<u… は保護区間を開く")

        let afterTag = "<div> ultracode を使う"
        #expect(keywordRanges(afterTag) == [u16Range(of: "ultracode", in: afterTag)],
                "閉じたタグの外側は検出する")

        let comparison = "1 < 2 ultracode を使う"
        #expect(keywordRanges(comparison) == [u16Range(of: "ultracode", in: comparison)],
                "< の次が空白なら保護を開始しない")
    }

    @Test("アポストロフィは直前が語構成文字なら保護を開始しない")
    func apostropheDoesNotOpenAfterWordCharacter() {
        let text = "don't ultracode it"
        #expect(keywordRanges(text) == [u16Range(of: "ultracode", in: text)])
    }

    @Test("ultrathink は保護区間の内側でも検出する（規則X には除外がない）")
    func ultrathinkIgnoresProtectedRegions() {
        let text = "\"ultrathink\" と書いた"
        #expect(keywordRanges(text) == [u16Range(of: "ultrathink", in: text)])
    }

    // MARK: - 規則Y の前後文字の除外

    @Test("直前が / \\ - なら検出しない")
    func excludesWhenPrecededBySeparator() {
        #expect(keywordRanges("a/ultracode を見て").isEmpty)
        #expect(keywordRanges("a\\ultracode を見て").isEmpty)
        #expect(keywordRanges("x-ultracode を見て").isEmpty)
    }

    @Test("直後が / \\ - ? なら検出しない")
    func excludesWhenFollowedBySeparator() {
        #expect(keywordRanges("ultracode/x を見て").isEmpty)
        #expect(keywordRanges("ultracode\\x を見て").isEmpty)
        #expect(keywordRanges("ultracode-x を見て").isEmpty)
        #expect(keywordRanges("ultracode? と聞く").isEmpty)
    }

    @Test("直後が . でその次が語構成文字なら検出しない（ファイル名・ドメイン避け）")
    func excludesWhenFollowedByDottedWord() {
        #expect(keywordRanges("ultracode.md を開く").isEmpty)
        #expect(keywordRanges("ultracode.example.com").isEmpty)
    }

    @Test("直後が . でもその次が語構成文字でなければ検出する")
    func detectsWhenDotIsSentenceEnd() {
        let text = "ultracode. 次へ進む"
        #expect(keywordRanges(text) == [u16Range(of: "ultracode", in: text)])
    }

    // MARK: - 既存 span との重なり

    @Test("スラッシュコマンド span と重なるキーワードは落とす")
    func dropsKeywordOverlappingSlashCommand() {
        let text = "/ultrathink"
        #expect(ComposerHighlight.spans(in: text, includingKeywords: true) ==
            [ComposerHighlightSpan(range: u16Range(of: "/ultrathink", in: text), kind: .slashCommand)])
    }

    @Test("@参照 span と重なるキーワードは落とす")
    func dropsKeywordOverlappingFileReference() {
        let text = "@ultrathink"
        #expect(ComposerHighlight.spans(in: text, includingKeywords: true) ==
            [ComposerHighlightSpan(range: u16Range(of: "@ultrathink", in: text), kind: .fileReference)])
    }

    @Test("重ならないキーワードは既存 span と共存する")
    func keepsKeywordAlongsideOtherSpans() {
        let text = "/go ultrathink @file"
        #expect(ComposerHighlight.spans(in: text, includingKeywords: true) == [
            ComposerHighlightSpan(range: u16Range(of: "/go", in: text), kind: .slashCommand),
            ComposerHighlightSpan(range: u16Range(of: "ultrathink", in: text), kind: .keyword),
            ComposerHighlightSpan(range: u16Range(of: "@file", in: text), kind: .fileReference),
        ])
    }

    @Test("返り値は開始オフセットの昇順")
    func spansAreSortedByStartOffset() {
        let spans = ComposerHighlight.spans(in: "ultrathink /go ultracode @file", includingKeywords: true)
        #expect(spans.map(\.range.lowerBound) == spans.map(\.range.lowerBound).sorted())
    }
}
