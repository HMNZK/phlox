// task-41（UX-01a）の受け入れテスト。
//
// ベースラインでの red 理由: `SessionTitleDeriver` と `DerivedSessionTitle` は
// 本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: tasks/task-41.md の公開契約と成功基準 1。期待値は下表の独立リテラルであり、
// 実装の戻り値から生成しない。表の \n・\r・\t は実際の制御文字を入力する。
// 実装役はアサーションを変更禁止。

import Foundation
import Testing
import AgentDomain

@Suite("task-41: session title deriver")
struct AcceptanceSessionTitleDeriverTests {
    private func expectBoth(_ input: String, _ expected: String, _ label: String) {
        let result = SessionTitleDeriver.derive(from: input)
        #expect(result?.title == expected, Comment(rawValue: "\(label) title"))
        #expect(result?.fullTitle == expected, Comment(rawValue: "\(label) fullTitle"))
    }

    private func expectNil(_ input: String, _ label: String) {
        #expect(SessionTitleDeriver.derive(from: input) == nil, Comment(rawValue: label))
    }

    @Test("公開契約: derive(from:) が title/fullTitle を返す")
    func publicAPIMatchesContract() {
        let result = SessionTitleDeriver.derive(from: "ログイン画面を修正")
        #expect(result?.title == "ログイン画面を修正", Comment(rawValue: "public title"))
        #expect(result?.fullTitle == "ログイン画面を修正", Comment(rawValue: "public fullTitle"))
        let again = SessionTitleDeriver.derive(from: "ログイン画面を修正")
        #expect(result == again, Comment(rawValue: "equatable"))
    }

    @Test("公開契約: title と fullTitle は非 Optional の String に代入できる")
    func publicTitlePropertiesAreNonOptionalStrings() {
        let result = SessionTitleDeriver.derive(from: "ログイン画面を修正")
        #expect(result != nil, Comment(rawValue: "derive returns a value"))
        guard let derived = result else { return }
        let title: String = derived.title
        let fullTitle: String = derived.fullTitle
        #expect(title == "ログイン画面を修正", Comment(rawValue: "non-optional title"))
        #expect(fullTitle == "ログイン画面を修正", Comment(rawValue: "non-optional fullTitle"))
    }

    @Test("最初の適格行を title/fullTitle にする")
    func firstEligibleLineIsTitle() {
        expectBoth("ログイン画面を修正\n詳しい条件", "ログイン画面を修正", "first eligible")
    }

    @Test("CRLF・タブ・全角空白を正規化する")
    func crlfTabAndIdeographicSpaceNormalize() {
        expectBoth("\r\n  API\t の　接続を修正  \r\n次の行", "API の 接続を修正", "crlf tab width")
    }

    @Test("全角英数・全角空白を幅変換する")
    func fullwidthAlphanumericsConvert() {
        expectBoth("ＡＰＩ　１２３を修正", "API 123を修正", "fullwidth")
    }

    @Test("空文字は nil")
    func emptyStringIsNil() {
        expectNil("", "empty")
    }

    @Test("空白のみは nil")
    func whitespaceOnlyIsNil() {
        expectNil("   ", "spaces")
        expectNil("\t  \t", "tabs")
    }

    @Test("改行のみは nil")
    func newlinesOnlyAreNil() {
        expectNil("\n", "lf")
        expectNil("\r\n", "crlf")
        expectNil("\n\n", "lfs")
        expectNil("\r", "cr")
    }

    @Test("スラッシュコマンド行だけなら nil")
    func slashCommandOnlyIsNil() {
        expectNil("/review", "ascii slash")
        expectNil("／review 引数", "fullwidth slash")
    }

    @Test("スラッシュコマンドの次の適格行を採る")
    func slashCommandThenEligibleLine() {
        expectBoth("/review\nログイン画面を修正", "ログイン画面を修正", "slash then eligible")
    }

    @Test("閉じたバッククォートフェンスだけなら nil")
    func closedBacktickFenceOnlyIsNil() {
        let input = #"""
        ```swift
        print(1)
        ```
        """#
        expectNil(input, "closed backtick fence")
    }

    @Test("閉じたバッククォートフェンスの次行を採る")
    func closedBacktickFenceThenEligibleLine() {
        let input = #"""
        ```swift
        print(1)
        ```
        ログインを修正
        """#
        expectBoth(input, "ログインを修正", "closed backtick then eligible")
    }

    @Test("チルダ3個のフェンスもバッククォートと同じ除外規則")
    func tildeFenceMatchesBacktickRule() {
        let onlyFence = #"""
        ~~~
        print(1)
        ~~~
        """#
        expectNil(onlyFence, "closed tilde fence")

        let fenceThenEligible = #"""
        ~~~
        print(1)
        ~~~
        ログインを修正
        """#
        expectBoth(fenceThenEligible, "ログインを修正", "closed tilde then eligible")
    }

    @Test("バッククォート4個開始は3個の行では閉じず、開始後から候補を採らない")
    func fourBacktickFenceIgnoresThreeBacktickCloser() {
        let input = #"""
        ````
        print(1)
        ```
        ログインを修正
        """#
        expectNil(input, "unclosed 4-backtick fence")
    }

    @Test("バッククォート開始をチルダでは閉じず、開始後から候補を採らない")
    func backtickFenceDoesNotCloseWithTilde() {
        let input = #"""
        ```
        print(1)
        ~~~
        ログインを修正
        """#
        expectNil(input, "backtick opened tilde closer")
    }

    @Test("未閉鎖フェンスの前の最初の適格行を採る")
    func eligibleLineBeforeUnclosedFence() {
        let input = #"""
        ログイン画面を修正
        ```
        print(1)
        """#
        expectBoth(input, "ログイン画面を修正", "eligible before unclosed fence")
    }

    @Test("半角空白4個の貼り付けコード行を除外する")
    func fourSpaceIndentedLineIsExcluded() {
        expectBoth("    let value = 1\nログインを修正", "ログインを修正", "4-space indent")
    }

    @Test("半角空白4個の説明行は let 接頭辞なしでも貼り付けコードとして除外する")
    func fourSpaceIndentedPlainLineIsExcluded() {
        expectBoth("    説明\nログインを修正", "ログインを修正", "4-space 説明")
    }

    @Test("半角空白3個の行は貼り付けコードとして除外せず説明を採る")
    func threeSpaceIndentedLineIsEligible() {
        expectBoth("   説明\nログインを修正", "説明", "3-space 説明")
    }

    @Test("タブ始まりの行を除外する")
    func tabIndentedLineIsExcluded() {
        expectBoth("\t説明\nログインを修正", "ログインを修正", "tab indent")
    }

    @Test("import 接頭辞の行を除外する")
    func importPrefixIsExcluded() {
        expectBoth("import Foundation\nログインを修正", "ログインを修正", "import prefix")
    }

    @Test(arguments: [
        "import Foundation",
        "from x",
        "func f()",
        "def f():",
        "class C",
        "struct S",
        "enum E",
        "let value = 1",
        "var value = 1",
        "const x = 1",
        "function f()",
        "return 1",
        "#include <stdio.h>",
        "#!/usr/bin/env python",
        "$ echo hi",
        "{",
        "}",
        "[",
        "]",
    ])
    func excludedPrefixThenEligibleLine(_ prefixLine: String) {
        expectBoth(prefixLine + "\nログインを修正", "ログインを修正", "prefix \(prefixLine)")
    }

    @Test("ASCII の大文字を維持する")
    func preservesASCIIUppercase() {
        expectBoth("APIを修正", "APIを修正", "uppercase")
    }

    @Test("32 Character はそのまま title == fullTitle")
    func thirtyTwoCharactersAreKept() {
        expectBoth(
            "abcdefghijklmnopqrstuvwx12345678",
            "abcdefghijklmnopqrstuvwx12345678",
            "32 chars"
        )
    }

    @Test("33 Character は先頭 31 Character と … を title にし fullTitle は入力を維持")
    func thirtyThreeCharactersTruncateTitle() {
        let input = "abcdefghijklmnopqrstuvwx123456789"
        let result = SessionTitleDeriver.derive(from: input)
        #expect(result?.title == "abcdefghijklmnopqrstuvwx1234567…", Comment(rawValue: "33 title"))
        #expect(result?.fullTitle == "abcdefghijklmnopqrstuvwx123456789", Comment(rawValue: "33 fullTitle"))
    }

    @Test("家族絵文字の 32 Character 境界は切らない")
    func familyEmojiThirtyTwoCharactersKept() {
        let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦b"
        #expect(input.count == 32, Comment(rawValue: "32 Character fixture"))
        expectBoth(input, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦b", "family emoji 32")
    }

    @Test("家族絵文字の 33 Character は 31 Character と …、fullTitle は入力")
    func familyEmojiThirtyThreeCharactersTruncate() {
        let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦bc"
        #expect(input.count == 33, Comment(rawValue: "33 Character fixture"))
        let result = SessionTitleDeriver.derive(from: input)
        #expect(result?.title == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦…", Comment(rawValue: "family emoji 33 title"))
        #expect(result?.fullTitle == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦bc", Comment(rawValue: "family emoji 33 fullTitle"))
    }

    @Test("結合文字の 32 Character 境界は切らない")
    func combiningMarkThirtyTwoCharactersKept() {
        let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}b"
        #expect(input.count == 32, Comment(rawValue: "32 Character fixture"))
        expectBoth(input, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}b", "combining 32")
    }

    @Test("結合文字の 33 Character は 31 Character と …、fullTitle は入力")
    func combiningMarkThirtyThreeCharactersTruncate() {
        let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}bc"
        #expect(input.count == 33, Comment(rawValue: "33 Character fixture"))
        let result = SessionTitleDeriver.derive(from: input)
        #expect(result?.title == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}…", Comment(rawValue: "combining 33 title"))
        #expect(result?.fullTitle == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}bc", Comment(rawValue: "combining 33 fullTitle"))
    }

    @Test("同一入力への反復呼び出しは同じ結果で、入力文字列は変化しない")
    func repeatedCallsAreStableAndDoNotMutateInput() {
        var input = "ログイン画面を修正"
        let snapshot = input
        let first = SessionTitleDeriver.derive(from: input)
        let second = SessionTitleDeriver.derive(from: input)
        #expect(first == second, Comment(rawValue: "repeat equal"))
        #expect(first?.title == "ログイン画面を修正", Comment(rawValue: "repeat title"))
        #expect(first?.fullTitle == "ログイン画面を修正", Comment(rawValue: "repeat fullTitle"))
        #expect(input == snapshot, Comment(rawValue: "input unchanged vs snapshot"))
        #expect(input == "ログイン画面を修正", Comment(rawValue: "input unchanged literal"))

        var normalized = "\r\n  API\t の　接続を修正  \r\n次の行"
        let normalizedSnapshot = normalized
        let once = SessionTitleDeriver.derive(from: normalized)
        let twice = SessionTitleDeriver.derive(from: normalized)
        #expect(once == twice, Comment(rawValue: "normalized repeat"))
        #expect(once?.title == "API の 接続を修正", Comment(rawValue: "normalized title"))
        #expect(once?.fullTitle == "API の 接続を修正", Comment(rawValue: "normalized fullTitle"))
        #expect(normalized == normalizedSnapshot, Comment(rawValue: "normalized input unchanged"))
    }

    @Test("URL 行はコマンドとして除外しない")
    func urlLineIsEligible() {
        expectBoth("https://example.com", "https://example.com", "url only")
        expectBoth("https://example.com\nログインを修正", "https://example.com", "url first")
    }

    @Test("10000 Character の適格行は fullTitle を全文保持し title は 31 Character と …")
    func tenThousandCharacterLineKeepsFullTitle() {
        let input = String(repeating: "a", count: 10_000)
        #expect(input.count == 10_000, Comment(rawValue: "10000 Character fixture"))
        let result = SessionTitleDeriver.derive(from: input)
        #expect(result?.fullTitle == input, Comment(rawValue: "10000 fullTitle retained"))
        #expect(result?.fullTitle.count == 10_000, Comment(rawValue: "10000 fullTitle count"))
        #expect(result?.title == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa…", Comment(rawValue: "10000 title"))
        #expect(result?.title.count == 32, Comment(rawValue: "31 + ellipsis Character"))
    }

    @Test("単独 CR を行境界として扱う")
    func bareCRIsLineBoundary() {
        expectBoth("説明\rログインを修正", "説明", "CR between lines")
        expectBoth("\rログインを修正", "ログインを修正", "leading CR")
    }

    @Test("全角空白のみは nil")
    func ideographicSpaceOnlyIsNil() {
        expectNil("\u{3000}", "ideographic space")
        expectNil("\u{3000}\u{3000}", "ideographic spaces")
    }

    @Test("連続する内部の全角空白・タブを半角空白1個にする")
    func consecutiveInternalWhitespaceCollapses() {
        expectBoth("API\u{3000}\u{3000}\u{3000}接続を修正", "API 接続を修正", "ideographic run")
        expectBoth("API \t\u{3000}接続を修正", "API 接続を修正", "mixed internal")
    }

    @Test(arguments: [1, 2, 3])
    func leadingSpacesFenceIsExcluded(_ spaces: Int) {
        let indent = String(repeating: " ", count: spaces)
        let input = "\(indent)```\nprint(1)\n```\nログインを修正"
        expectBoth(input, "ログインを修正", "\(spaces)-space fence")
    }

    @Test("開始より長い終了フェンスで閉じ、次の適格行を採る")
    func longerClosingFenceCloses() {
        expectBoth("```\nprint(1)\n````\nログインを修正", "ログインを修正", "longer closer")
    }

    @Test("終了フェンス後の非空白文字では閉じず、開始後から候補を採らない")
    func closingFenceWithTrailingNonWhitespaceDoesNotClose() {
        expectNil("```\nprint(1)\n```x\nログインを修正", "closer with trailing text")
    }

    @Test("除外接頭辞に似た英語の適格行は採る")
    func englishLinesThatLookLikeExcludedPrefixesRemain() {
        expectBoth("Return home", "Return home", "Return home")
        expectBoth("important fix", "important fix", "important fix")
    }

    @Test("全角カタカナを半角カナへ幅変換する")
    func fullwidthKatakanaConvertsToHalfwidth() {
        expectBoth("カタカナ修正", "ｶﾀｶﾅ修正", "fw katakana")
    }

    @Test("濁点付き全角カナを半角カナ+半角濁点へ幅変換する")
    func fullwidthVoicedKatakanaConverts() {
        expectBoth("ガ行を修正", "ｶﾞ行を修正", "fw dakuten")
    }

    @Test("半角カナと半角濁点は幅変換後も保持する")
    func halfwidthKatakanaAndDakutenAreKept() {
        expectBoth("ｶﾀｶﾅ修正", "ｶﾀｶﾅ修正", "hw katakana")
        expectBoth("ｶﾞ行を修正", "ｶﾞ行を修正", "hw dakuten")
    }
}
