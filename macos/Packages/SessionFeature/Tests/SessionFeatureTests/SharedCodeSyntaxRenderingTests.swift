import Testing
import SwiftUI
import DesignSystem
@testable import SessionFeature

@Suite("共有字句のチャット表示")
struct SharedCodeSyntaxRenderingTests {
    @Test("行のキャッシュは同じ拡張子でもファイル名による判定を取り違えない")
    @MainActor
    func cachedLinesUseFileNamePriority() {
        let make = ChatCodeHighlighter.highlightLines(["build:"], path: "Makefile")
        let plain = ChatCodeHighlighter.highlightLines(["build:"], path: "notes")
        #expect(make[0].runs.first?.foregroundColor == DSColor.codeSyntaxNumber)
        #expect(plain[0].runs.first?.foregroundColor == DSColor.chatTextPrimary)
        let environment = ChatCodeHighlighter.highlightLines(["FOO=1"], path: ".env.swift")
        let source = ChatCodeHighlighter.highlightLines(["FOO=1"], path: "source.swift")
        #expect(environment[0].runs.first?.foregroundColor == DSColor.codeSyntaxNumber)
        #expect(source[0].runs.first?.foregroundColor == DSColor.chatTextPrimary)
        #expect(ChatCodeHighlighter.highlightLines(["build:"], path: "Makefile") == make)
    }

    @Test("構造と差分を共有色で描き、原文と通常ウェイトを保つ")
    @MainActor
    func structuralColorsPreserveText() {
        let tokens: [ChatCodeToken] = [
            .init(text: "<tag", kind: .tag),
            .init(text: " attr", kind: .attribute),
            .init(text: "=\"値👩‍💻\">", kind: .string),
            .init(text: "\r\n--- a", kind: .diffHeader),
            .init(text: "\r\n@@ -1 +1 @@", kind: .diffHunk),
            .init(text: "\r\n+追加", kind: .diffAdded),
            .init(text: "\r\n-削除", kind: .diffRemoved),
        ]
        let rendered = ChatCodeHighlighter.highlight(tokens: tokens)
        #expect(String(rendered.characters).utf8.elementsEqual(tokens.map(\.text).joined().utf8))
        for token in tokens {
            guard let range = rendered.range(of: token.text) else {
                Issue.record("字句が表示から欠落した")
                continue
            }
            #expect(rendered[range].runs.first?.foregroundColor == CodeSyntaxColor.color(for: token.kind, chat: true))
            #expect(rendered[range].runs.first?.inlinePresentationIntent == nil)
        }
        #expect(CodeSyntaxColor.color(for: .diffAdded) == DSColor.diffAdded)
        #expect(CodeSyntaxColor.color(for: .diffRemoved) == DSColor.diffRemoved)
        #expect(CodeSyntaxColor.color(for: .attribute) == DSColor.codeSyntaxNumber)
        #expect(CodeSyntaxColor.color(for: .tag) == DSColor.codeSyntaxKeyword)
    }

    @Test("名前の追加分類はチャットに限定し、キーワードだけを太字にする")
    @MainActor
    func namesAndWeightRemainChatSpecific() {
        let rendered = ChatCodeHighlighter.highlight(tokens: [
            .init(text: "let", kind: .keyword),
            .init(text: " 型", kind: .type),
            .init(text: ".member", kind: .member),
            .init(text: "call", kind: .call),
        ], boldKeywords: true)
        let keyword = rendered.range(of: "let")!
        #expect(rendered[keyword].runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        for (text, kind) in [(" 型", ChatCodeTokenKind.type), (".member", .member), ("call", .call)] {
            let range = rendered.range(of: text)!
            #expect(rendered[range].runs.first?.inlinePresentationIntent == nil)
            #expect(rendered[range].runs.first?.foregroundColor == CodeSyntaxColor.color(for: kind, chat: true))
            #expect(CodeSyntaxColor.color(for: kind) == DSColor.textPrimary)
        }
    }
}
