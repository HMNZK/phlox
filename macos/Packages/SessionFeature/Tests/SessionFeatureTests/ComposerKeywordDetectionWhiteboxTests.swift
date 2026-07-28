import Foundation
import Testing
@testable import SessionFeature

// task-1 白箱テスト（実装役）。
// tasks/task-1.md が名指しした3つの正しさハザードを、素朴な実装なら落ちる入力で狙い撃ちする。
//   H1: ASCII 語境界 vs Unicode 語境界（Swift の \b をそのまま使うと日本語隣接で落ちる）
//   H2: Rqs の条件つき状態機械（' の開始/終了条件・[[ の開始位置更新・< の条件開始・非入れ子）
//   H3: UTF16 オフセット（Character 単位で走査すると絵文字・結合文字でずれる）

private func keywordRanges(_ text: String) -> [Range<Int>] {
    ComposerHighlight.spans(in: text, includingKeywords: true)
        .filter { $0.kind == .keyword }
        .map(\.range)
}

@Suite("ComposerHighlight キーワード検出 white-box（task-1）")
struct ComposerKeywordDetectionWhiteboxTests {

    // MARK: - H1: ASCII 語境界

    @Test("直後が CJK でも検出する（Unicode 語境界なら一致しない入力）")
    func detectsKeywordFollowedByCJK() {
        // ICU の Unicode 語境界では "k" と "日" の間に \b が立たず一致しない。ASCII 判定なら一致する。
        #expect(keywordRanges("ultrathink日本語で調べて") == [0..<10])
    }

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
