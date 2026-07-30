import Testing
import AgentDomain
@testable import ChatRenderKit

// task-1 の受け入れテスト（PM が著す不変の契約）。
// 目的: macOS 専用パッケージにあったチャット表示の純粋計算を、macOS/iOS 双方から使える
// 共有ターゲット ChatRenderKit へ移した結果、公開 API と境界の振る舞いが契約どおりであることを固定する。
// 出力の「現行と完全一致」は macOS 側の既存凍結テスト（無改変）が担保する。

@Suite("ChatRenderKit: diff の分類と行番号採番")
struct AcceptanceChatDiffClassifierTests {
    @Test("hunk ヘッダから旧側・新側を起算する")
    func numbersFromHunkHeader() {
        let diff = """
        @@ -10,3 +20,4 @@
         context
        -removed
        +added
        """
        let lines = ChatDiffClassifier.classify(diff)
        #expect(lines.map(\.kind) == [.hunk, .context, .deletion, .addition])
        // 旧側の番号は削除行にだけ、新側の番号は追加・コンテキスト行にだけ載せる。
        #expect(lines[1].oldLineNumber == nil)
        #expect(lines[1].newLineNumber == 20)
        #expect(lines[2].oldLineNumber == 11)
        #expect(lines[3].newLineNumber == 21)
        // 表示上の番号: 削除は旧側、追加とコンテキストは新側。
        #expect(lines[1].displayLineNumber == 20)
        #expect(lines[2].displayLineNumber == 11)
        #expect(lines[3].displayLineNumber == 21)
        #expect(lines[0].displayLineNumber == nil)
    }

    @Test("複数 hunk はそれぞれのヘッダで採番し直す")
    func numbersRestartPerHunk() {
        let diff = """
        @@ -1,1 +1,1 @@
         first
        @@ -100,1 +200,1 @@
         second
        """
        let lines = ChatDiffClassifier.classify(diff)
        #expect(lines[1].newLineNumber == 1)
        #expect(lines[3].newLineNumber == 200)
        #expect(lines[3].displayLineNumber == 200)
    }

    @Test("hunk ヘッダが無い diff は採番しない（推測しない）")
    func noHunkHeaderMeansNoNumbers() {
        let lines = ChatDiffClassifier.classify("+added\n-removed\n plain")
        #expect(lines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber == nil })
        #expect(lines.allSatisfy { $0.displayLineNumber == nil })
    }

    @Test("壊れた hunk ヘッダは、その時点以降の採番を諦める（連番を続けない・落ちない）", arguments: [
        "@@",
        "@@ @@",
        "@@ -a,b +c,d @@",
        "@@ -1 +@@",
        "@@ - + @@",
        "@@ -,, +,, @@",
        "@@ -1,2 @@",
        "@@ +1,2 @@",
        "@@ -x +1 @@",
        "@@ -1,2 +x @@",
        "@@ -1,2 3,4 @@",
        "@@ +1,2 -3,4 @@",
        "@@ -9999999999999999999999 +1 @@",
        "@@ - 1,2 + 3,4 @@",
        "@@ x y z @@",
    ])
    func brokenHunkHeaderStopsNumbering(_ header: String) {
        let diff = """
        @@ -1,1 +1,1 @@
         good
        \(header)
         after
        """
        let lines = ChatDiffClassifier.classify(diff)
        #expect(lines.count == 4)
        // 壊れたヘッダの後ろの行に番号を出さない（直前 hunk の連番継続は「推測」なので禁止）。
        #expect(lines[3].displayLineNumber == nil)
    }

    @Test("Int の上限付近でも採番がオーバーフローで落ちない")
    func overflowIsSafe() {
        let diff = """
        @@ -\(Int.max),1 +\(Int.max),1 @@
         a
         b
         c
        """
        let lines = ChatDiffClassifier.classify(diff)
        #expect(lines.count == 4)
    }

    @Test("no-newline 注記は表示対象外で、採番を進めない")
    func noNewlineMarkerDoesNotAdvanceNumbering() {
        let diff = """
        @@ -1,2 +1,2 @@
         a
        \\ No newline at end of file
         b
        """
        let lines = ChatDiffClassifier.classify(diff)
        let marker = try? #require(lines.first { $0.text == "\\ No newline at end of file" })
        #expect(marker?.isDisplayable == false)
        let last = lines[3]
        #expect(last.newLineNumber == 2)
    }

    @Test("--- / +++ のファイルヘッダは表示対象外")
    func fileHeadersAreNotDisplayable() {
        let diff = """
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,1 +1,1 @@
         a
        """
        let lines = ChatDiffClassifier.classify(diff)
        #expect(lines[0].kind == .fileHeader)
        #expect(lines[1].kind == .fileHeader)
        #expect(lines[0].isDisplayable == false)
        #expect(lines[1].isDisplayable == false)
        #expect(lines[3].isDisplayable == true)
    }

    @Test("空の diff は空配列でも 1 要素でも落ちない")
    func emptyDiffIsSafe() {
        _ = ChatDiffClassifier.classify("")
    }
}

@Suite("ChatRenderKit: コードのトークナイズ")
struct AcceptanceChatCodeTokenizerTests {
    @Test("Swift 以外の拡張子は全体を 1 つの plain トークンにする")
    func nonSwiftFallsBackToPlain() {
        let tokens = ChatCodeTokenizer.tokens(for: "let x = 1", path: "notes.txt")
        #expect(tokens == [ChatCodeToken(text: "let x = 1", kind: .plain)])
    }

    @Test("空のコードは空のトークン列になる")
    func emptyCodeYieldsNoTokens() {
        #expect(ChatCodeTokenizer.tokens(for: "", path: "notes.txt").isEmpty)
    }

    @Test("Swift はキーワード・文字列・数値・コメントを分類する")
    func swiftTokensAreClassified() {
        let tokens = ChatCodeTokenizer.swift("let x = 1 // \"note\"")
        #expect(tokens.contains { $0.text == "let" && $0.kind == .keyword })
        #expect(tokens.contains { $0.kind == .number })
        #expect(tokens.contains { $0.kind == .comment })
    }

    @Test("Swift の文字列リテラル内のキーワードはキーワードにしない")
    func keywordInsideStringStaysString() {
        let tokens = ChatCodeTokenizer.swift("let s = \"let func\"")
        let stringToken = tokens.first { $0.kind == .string }
        #expect(stringToken?.text.contains("let func") == true)
    }

    @Test("シェルはコマンド名・オプション・変数・演算子を分類する")
    func shellTokensAreClassified() {
        let tokens = ChatCodeTokenizer.shell("swift test --package-path $HOME && echo ok")
        #expect(tokens.first { $0.text == "swift" }?.kind == .command)
        #expect(tokens.contains { $0.text == "--package-path" && $0.kind == .option })
        #expect(tokens.contains { $0.kind == .variable })
        #expect(tokens.contains { $0.text == "&&" && $0.kind == .operator })
    }

    @Test("シェルの空入力は落ちない")
    func shellEmptyIsSafe() {
        _ = ChatCodeTokenizer.shell("")
    }

    @Test("トークン列を連結すると原文に戻る（表示用の加工を混ぜない）", arguments: [
        "swift test --package-path $HOME && echo ok",
        "Read /tmp/a.txt",
        "  leading and   inner   spaces  ",
    ])
    func shellTokensPreserveSource(_ command: String) {
        #expect(ChatCodeTokenizer.shell(command).map(\.text).joined() == command)
    }
}

@Suite("ChatRenderKit: ツール名ラベルの導出")
struct AcceptanceChatCommandToolLabelTests {
    @Test("既知ツール名と完全一致すればツール名と残りに分ける", arguments: [
        ("Read /tmp/a.txt", "Read", "/tmp/a.txt"),
        ("Edit foo.swift", "Edit", "foo.swift"),
        ("Glob **/*.swift", "Glob", "**/*.swift"),
        ("TodoWrite", "TodoWrite", ""),
    ])
    func knownToolsAreSplit(_ input: String, _ label: String, _ body: String) {
        let result = ChatCommandToolLabel.derive(command: input)
        #expect(result.label == label)
        #expect(result.body == body)
    }

    @Test("既知ツール名でなければ Bash とコマンド全文になる", arguments: [
        "swift test", "read /tmp/a.txt", "READ x", "ls -la",
    ])
    func unknownToolsBecomeBash(_ input: String) {
        let result = ChatCommandToolLabel.derive(command: input)
        #expect(result.label == "Bash")
        #expect(result.body == input)
    }

    @Test("nil・空白のみは Bash と空文字列になる", arguments: [nil, "", "   ", "\n"])
    func emptyCommandsBecomeBashWithEmptyBody(_ input: String?) {
        let result = ChatCommandToolLabel.derive(command: input)
        #expect(result.label == "Bash")
        #expect(result.body == "")
    }
}

@Suite("ChatRenderKit: ファイル変更の見出しと増減行数")
struct AcceptanceChatFileChangePresentationTests {
    @Test("kind から動詞を決める", arguments: [
        ("edit", "編集済み"), ("Edit", "編集済み"), ("multi_edit", "編集済み"),
        ("write", "作成済み"), ("create", "作成済み"),
        ("delete", "削除済み"),
        ("unknown", "変更済み"), ("", "変更済み"),
    ])
    func verbFromKind(_ kind: String, _ verb: String) {
        #expect(ChatFileChangePresentation.verb(for: kind) == verb)
    }

    @Test("kind が nil なら 変更済み")
    func verbFromNilKind() {
        #expect(ChatFileChangePresentation.verb(for: nil) == "変更済み")
    }

    @Test("増減行数は追加行・削除行だけを数える（hunk・ファイルヘッダは数えない）")
    func countsOnlyAdditionsAndDeletions() {
        let patch = ChatFilePatch(
            path: "a/b/lessons.md",
            diff: """
            --- a/lessons.md
            +++ b/lessons.md
            @@ -1,3 +1,4 @@
             keep
            +add1
            +add2
            -del1
            """,
            kind: "edit"
        )
        let counts = ChatFileChangePresentation.counts(for: [patch])
        #expect(counts.additions == 2)
        #expect(counts.deletions == 1)
    }

    @Test("見出しは単一ファイルならファイル名、複数なら件数")
    func titleShape() {
        let a = ChatFilePatch(path: "src/deep/lessons.md", diff: "", kind: "edit")
        let b = ChatFilePatch(path: "src/other.swift", diff: "", kind: "edit")
        #expect(ChatFileChangePresentation.title(for: [a]) == "編集済み lessons.md")
        #expect(ChatFileChangePresentation.title(for: [a, b]) == "編集済み 2 件のファイル")
    }
}

@Suite("ChatRenderKit: Reasoning の見出しと本文")
struct AcceptanceChatReasoningPresentationTests {
    @Test("見出しと本文が同じなら折りたたまない")
    func sameHeadlineAndBodyDoesNotUseDisclosure() {
        let presentation = ChatReasoningPresentation(text: "  短い一文  ")
        #expect(presentation.headline == "短い一文")
        #expect(presentation.trimmedText == "短い一文")
        #expect(presentation.usesDisclosure == false)
    }

    @Test("本文が見出しより長ければ折りたたむ")
    func longerBodyUsesDisclosure() {
        let presentation = ChatReasoningPresentation(text: "# 見出し\n本文がある")
        #expect(presentation.usesDisclosure == true)
        #expect(presentation.headline.isEmpty == false)
        #expect(presentation.trimmedText == "# 見出し\n本文がある")
    }

    @Test("空文字列でも落ちず、既定の見出しになる")
    func emptyTextIsSafe() {
        let presentation = ChatReasoningPresentation(text: "   ")
        #expect(presentation.headline == "Reasoning")
        #expect(presentation.trimmedText.isEmpty)
        #expect(presentation.usesDisclosure == true)
    }
}

@Suite("ChatRenderKit: ツール実行グループの見出し")
struct AcceptanceChatCommandGroupTitleTests {
    @Test("末尾の非空コマンドの原文を見出しにする（接尾辞を付けない）")
    func titleIsLastCommandVerbatim() {
        let title = ChatCommandGroupTitle.derive(commands: ["ls", "swift test"], itemCount: 2)
        #expect(title == "swift test")
    }

    @Test("複数行コマンドは空白を畳んで 1 行にする（末尾断片に化けない）")
    func multilineCommandIsFolded() {
        let command = "cd macos && swift build \\\n  --configuration release"
        let title = ChatCommandGroupTitle.derive(commands: [command], itemCount: 1)
        #expect(title == "cd macos && swift build \\ --configuration release")
    }

    @Test("60 文字を超えたら省略記号付きで切る")
    func titleIsClampedAt60() {
        let command = String(repeating: "a", count: 100)
        let title = ChatCommandGroupTitle.derive(commands: [command], itemCount: 1)
        #expect(title == String(repeating: "a", count: 60) + "…")
    }

    @Test("コマンドが 1 件も無ければ件数のフォールバックへ落ちる", arguments: [
        [String?](), [nil], ["", "   "],
    ])
    func fallbackWhenNoCommand(_ commands: [String?]) {
        let title = ChatCommandGroupTitle.derive(commands: commands, itemCount: 3)
        #expect(title == "ツール実行 ×3")
    }

    @Test("末尾が空でも、その前の非空コマンドを拾う")
    func picksLastNonEmptyCommand() {
        let title = ChatCommandGroupTitle.derive(commands: ["swift test", nil, "  "], itemCount: 3)
        #expect(title == "swift test")
    }
}
