import SwiftUI
import Testing
import ChatRenderKit
@testable import DesignSystemIOS

// task-2 の受け入れテスト（PM が著す不変の契約）。
// 目的: iOS 側に「枠線付きコードカード」という共通の器を 1 つだけ用意し、
// 共有トークン列（ChatRenderKit）を iOS のテーマ色へ対応付ける入口を固定する。

@Suite("DSChatCodeCard: 共通のカード器")
struct AcceptanceDSChatCodeCardTests {
    @Test("見出しと中身を受け取って組み立てられる")
    func composesHeaderAndContent() {
        let card = DSChatCodeCard {
            Text("Bash")
        } content: {
            Text("$ swift test")
        }
        // View として成立していること（型が合わなければコンパイルで落ちる）。
        _ = card.body
    }

    @Test("器の寸法は 1 箇所に集約され、枠線を持つ")
    func metricsAreCentralized() {
        #expect(DSChatCodeCardMetrics.cornerRadius > 0)
        #expect(DSChatCodeCardMetrics.borderWidth > 0)
    }
}

@Suite("CodeHighlighter: 共有トークンの色付け入口")
struct AcceptanceChatCodeHighlightEntryTests {
    @Test("共有トークン列を色付き文字列にしても、文字は 1 つも増減しない")
    func attributedPreservesCharacters() {
        let tokens = ChatCodeTokenizer.shell("swift test --package-path $HOME && echo ok")
        let attributed = CodeHighlighter.attributed(tokens: tokens)
        #expect(String(attributed.characters) == "swift test --package-path $HOME && echo ok")
    }

    @Test("シェル入口は原文を保つ（表示用のインデントを混ぜない）", arguments: [
        "swift build \\\n  --configuration release",
        "Read /tmp/a.txt",
        "",
    ])
    func shellEntryPreservesSource(_ command: String) {
        #expect(String(CodeHighlighter.shell(command).characters) == command)
    }

    @Test("diff 入口は原文を保ち、未対応拡張子でも落ちない", arguments: [
        ("let x = 1", "a.swift"),
        ("plain text", "notes.txt"),
        ("", "empty.swift"),
    ])
    func diffEntryPreservesSource(_ code: String, _ path: String) {
        #expect(String(CodeHighlighter.diff(code, path: path).characters) == code)
    }

    @Test("既存の markdown 用トークナイザの出力は変えない")
    func existingTokenizerIsUntouched() {
        let code = #"let value = "return // not a comment""#
        let tokens = CodeHighlighter.tokens(for: code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
        #expect(tokens.contains(CodeToken(kind: .string, text: #""return // not a comment""#)))
        #expect(!tokens.contains { $0.kind == .comment })
    }
}
