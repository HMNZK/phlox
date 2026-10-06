import Foundation
import Testing
@testable import SessionFeature

// 入力欄の ultra 系キーワード（ultrathink / ultraplan / ultrareview / ultracode）検出。
// claude CLI v2.1.220 の検出実装（2026-07-28 実測）を写した規則。
//   規則X（ultrathink のみ）: ASCII 語境界・大小無視のみ。除外規則なし。
//   規則Y（ultraplan / ultrareview / ultracode）: 規則X に加えて
//     - text が "/" で始まるなら1件も検出しない
//     - 保護区間（` " < { [ ( '）の内側は除外
//     - 直前が / \ - なら除外、直後が / \ - ? なら除外
//     - 直後が "." かつその次が語構成文字なら除外
// 検出の落とし穴: ASCII 語境界 vs Unicode 語境界、保護区間の状態機械、UTF16 オフセット。

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

@Suite("Composer keyword detection")
struct ComposerKeywordDetectionTests {

    // MARK: - 既存契約の不変性

    @Test("spans(in:) はキーワードを一切返さない（既存契約は不変）")
    func plainSpansNeverReturnKeyword() {
        let text = "ultrathink と ultracode を試す"
        #expect(ComposerHighlight.spans(in: text).allSatisfy { $0.kind != .keyword })
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

    // MARK: - 規則X と規則Y の差（"/" 始まりの扱い）

    @Test("入力が / で始まるとき、ultraplan・ultrareview・ultracode は検出しない")
    func slashPrefixedInputSuppressesRqsKeywords() {
        for word in ["ultraplan", "ultrareview", "ultracode"] {
            #expect(keywordRanges("/fix \(word) して").isEmpty, "\(word) は / 始まりで抑止されること")
        }
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

        // 後方に > があるケース。< を無条件に開く実装だと 2..<17 が保護区間になり
        // ultracode が飲み込まれる。条件開始を守っているかはこのケースでしか判別できない。
        let comparisonWithCloser = "a < b ultracode > c"
        #expect(keywordRanges(comparisonWithCloser) == [u16Range(of: "ultracode", in: comparisonWithCloser)],
                "< の次が空白なら、後方に > があっても保護区間を開かない")
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

    // MARK: - H1: ASCII 語境界

    @Test("直前が結合文字でも検出し、オフセットは UTF16 単位")
    func detectsKeywordAfterCombiningMark() {
        // "é"（e + U+0301）は 1 Character・2 UTF16 単位。直前の UTF16 単位 U+0301 は ASCII 語構成文字でない。
        #expect(keywordRanges("e\u{0301}ultrathink") == [2..<12])
    }

    @Test("直前が ASCII 語構成文字なら検出しない")
    func rejectsWhenPrecededByASCIIWordCharacter() {
        #expect(keywordRanges("_ultrathink").isEmpty)
        #expect(keywordRanges("9ultrathink").isEmpty)
    }

    @Test("直後が ASCII 語構成文字なら検出しない")
    func rejectsWhenFollowedByASCIIWordCharacter() {
        #expect(keywordRanges("ultrathink_").isEmpty)
        #expect(keywordRanges("ultrathink9").isEmpty)
    }

    // MARK: - H2: 保護区間の状態機械

    @Test("アポストロフィの直前判定は Unicode の語構成文字（CJK の直後では保護を開始しない）")
    func apostropheDoesNotOpenAfterUnicodeWordCharacter() {
        // 直前判定を ASCII 限定にすると "語" が非語構成文字扱いになり、保護区間を開いて検出を落とす。
        #expect(keywordRanges("日本語'ultracode'") == [4..<13])
    }

    @Test("アポストロフィは直後が語構成文字なら閉じない")
    func apostropheDoesNotCloseBeforeWordCharacter() {
        // "don't" の "'" で閉じてしまうと保護区間が 0..<5 で終わり、ultracode を検出してしまう。
        #expect(keywordRanges("'don't ultracode'").isEmpty)
    }

    @Test("文頭のアポストロフィは保護区間を開始する")
    func apostropheAtStartOpensProtection() {
        #expect(keywordRanges("'ultracode' とは").isEmpty)
    }

    @Test("開いている間に来た [ は保護区間の開始位置を更新する")
    func repeatedOpenBracketMovesRegionStart() {
        // 開始位置を更新しないと区間が 0..<14 になり、ultracode(1..<10) を保護区間内と誤判定する。
        #expect(keywordRanges("[ultracode [x] rest") == [1..<10])
    }

    @Test("< は次が数字なら保護を開始しない")
    func angleBracketDoesNotOpenBeforeDigit() {
        // 無条件に開くと "<1 ultracode>" が丸ごと保護区間になり検出が消える。
        #expect(keywordRanges("x<1 ultracode>") == [4..<13])
    }

    @Test("< は次がスラッシュなら保護を開始する")
    func angleBracketOpensBeforeSlash() {
        #expect(keywordRanges("</div> ultracode") == [7..<16])
    }

    @Test("保護区間は入れ子にせず、開いている種別が閉じるまで他の開始文字を無視する")
    func protectedRegionsAreNotNested() {
        // 素朴なスタック実装だと "(" を積んでしまい、区間が閉じずに ultracode を飲み込む。
        #expect(keywordRanges("\"(\" ultracode)") == [4..<13])
    }

    @Test("閉じないまま終端に達した保護区間は成立しない")
    func unterminatedProtectedRegionDoesNotSwallowRest() {
        // 区間は「開始文字から終了文字の次まで」で定義されるため、終了文字が無ければ区間は確定しない。
        #expect(keywordRanges("\"ultracode") == [1..<10])
    }

    // MARK: - H3: UTF16 オフセット

    @Test("ZWJ 絵文字を含んでも range は UTF16 オフセット")
    func zwjEmojiKeepsUTF16Offsets() {
        // 家族絵文字は 1 Character だが 11 UTF16 単位。Character 単位で数えると 2..<12 にずれる。
        let text = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466} ultrathink"
        #expect(keywordRanges(text) == [12..<22])
    }

    // MARK: - 規則X と規則Y の差

    @Test("先頭の空白があれば / 始まりではないので規則Yの語も検出する")
    func leadingWhitespaceMeansNotSlashPrefixed() {
        #expect(keywordRanges(" /fix ultracode") == [6..<15])
    }

    @Test("/ 始まりでも ultrathink だけは検出する")
    func slashPrefixSuppressesOnlyRestrictedKeywords() {
        #expect(keywordRanges("/x ultrathink ultracode") == [3..<13])
    }

    // MARK: - 規則Y の除外規則

    @Test("除外規則も大文字小文字を無視する")
    func exclusionRulesAreCaseInsensitive() {
        #expect(keywordRanges("ULTRACODE.MD を開く").isEmpty)
        #expect(keywordRanges("ULTRACODE. 次へ") == [0..<9])
    }

    // MARK: - 並び順と既存 span との併合

    @Test("複数の語は語ごとではなく出現順に返る")
    func occurrencesAreReturnedInDocumentOrder() {
        #expect(keywordRanges("ultracode ultraplan ultrareview ultrathink") == [
            0..<9, 10..<19, 20..<31, 32..<42,
        ])
    }

    @Test("キーワードと既存 span は開始オフセット順に交互へ併合される")
    func keywordsAndTokenSpansAreInterleavedByOffset() {
        #expect(ComposerHighlight.spans(in: "ultrathink @a ultracode /b ultraplan", includingKeywords: true) == [
            ComposerHighlightSpan(range: 0..<10, kind: .keyword),
            ComposerHighlightSpan(range: 11..<13, kind: .fileReference),
            ComposerHighlightSpan(range: 14..<23, kind: .keyword),
            ComposerHighlightSpan(range: 24..<26, kind: .slashCommand),
            ComposerHighlightSpan(range: 27..<36, kind: .keyword),
        ])
    }

    @Test("キーワード検出は既存 span の並びを一切変えない", arguments: [
        "ultrathink /go ultracode @file",
        "/help me ultracode",
        "@a.md ultrathink @b.md",
        "\"ultracode\" と `ultraplan`",
        "",
    ])
    func keywordDetectionKeepsExistingSpansIntact(text: String) {
        let plain = ComposerHighlight.spans(in: text)

        #expect(ComposerHighlight.spans(in: text, includingKeywords: false) == plain)
        #expect(
            ComposerHighlight.spans(in: text, includingKeywords: true).filter { $0.kind != .keyword } == plain
        )
    }
}
