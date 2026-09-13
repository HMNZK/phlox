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
@testable import AgentDomain

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
}
