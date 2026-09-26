import Testing
import SwiftUI
import DesignSystem
@testable import SessionFeature

/// 会話の本文・コード・コマンド出力の強調（2026-09-26 ユーザー依頼: docs/specs/Chat Screen.dc.html に合わせる）。
@Suite("会話の強調: Chat Screen.dc.html")
struct ChatScreenHighlightTests {
    private func run(_ word: String, in text: AttributedString) -> AttributedString.Runs.Run? {
        guard let range = text.range(of: word) else { return nil }
        return text[range].runs.first
    }

    @Test("文中のコードは紫、書式の無い名前は紫の等幅、ファイル名は青、太字はそのまま")
    @MainActor
    func proseColorsCodeNamesAndFiles() {
        let text = ChatProseText.compute("**完了。** `ApprovalSettings` と expiresAt を ApprovalBrokerTests.swift に追加")
        #expect(String(text.characters) == "完了。 ApprovalSettings と expiresAt を ApprovalBrokerTests.swift に追加")
        #expect(run("完了。", in: text)?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(run("ApprovalSettings", in: text)?.foregroundColor == DSColor.codeSyntaxKeyword)
        #expect(run("expiresAt", in: text)?.foregroundColor == DSColor.codeSyntaxKeyword)
        #expect(run("expiresAt", in: text)?.inlinePresentationIntent == .code)
        #expect(run("expiresAt", in: text)?.font == .system(size: ChatTypography.codeFontSize(scale: 1), design: .monospaced))
        #expect(run(" と ", in: text)?.font == nil)
        #expect(run("ApprovalBrokerTests.swift", in: text)?.foregroundColor == DSColor.attentionInk(.question))
        #expect(run(" と ", in: text)?.foregroundColor == nil)
    }

    @Test("成功は緑・失敗は赤の太字、数量は太字、太字の中は自動で強調しない")
    @MainActor
    func proseColorsOutcomes() {
        let text = ChatProseText.compute("3 件すべて成功、1 件失敗。**10 分固定**")
        #expect(run("すべて成功", in: text)?.foregroundColor == DSColor.diffAdded)
        #expect(run("失敗", in: text)?.foregroundColor == DSColor.diffRemoved)
        #expect(run("3 件", in: text)?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(run("10 分固定", in: text)?.foregroundColor == nil)
    }

    @Test("複合絵文字・結合文字の後の名前も位置がずれず、リンクの中は強調しない")
    @MainActor
    func proseKeepsPositionsAfterEmojiAndSkipsLinks() {
        let text = ChatProseText.compute("👨‍👩‍👧 が̈ expiresAt と [makeView](https://example.com)")
        #expect(run("expiresAt", in: text)?.foregroundColor == DSColor.codeSyntaxKeyword)
        #expect(run(" と ", in: text)?.foregroundColor == nil)
        #expect(run("makeView", in: text)?.foregroundColor == DSColor.accentInk)
        #expect(run("makeView", in: text)?.inlinePresentationIntent == nil)
    }

    @Test("json はキーワードを太字にしない（細かい色分けをしない言語）")
    @MainActor
    func jsonKeepsKeywordsRegularWeight() {
        let text = ChatCodeHighlighter.computeHighlight("{\"ok\": true}", language: "json")
        #expect(run("true", in: text)?.foregroundColor == DSColor.codeSyntaxKeyword)
        #expect(run("true", in: text)?.inlinePresentationIntent == nil)
    }

    @Test("コードの型は青・呼び出しはアクセント色・キーワードは太字")
    @MainActor
    func codeColorsTypesCallsAndBoldKeywords() {
        let text = ChatCodeHighlighter.computeHighlight("func expireOverdue(at now: Date) {}", language: "swift")
        #expect(run("Date", in: text)?.foregroundColor == DSColor.attentionInk(.question))
        #expect(run("expireOverdue", in: text)?.foregroundColor == DSColor.accentInk)
        #expect(run("func", in: text)?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test("コマンド出力: ✔ と 0 failures は緑、10 failures は緑にしない、経過は弱い色、error は赤")
    @MainActor
    func commandOutputLineColors() {
        let text = TranscriptCardOutputLines.attributed("Building for debugging...\n✔ testA (0.003s)\nExecuted 3 tests, with 0 failures\nExecuted 12 tests, with 10 failures\nerror: fatalError")
        #expect(run("Building", in: text)?.foregroundColor == DSColor.chatTextSecondary)
        #expect(run("✔ testA", in: text)?.foregroundColor == DSColor.diffAdded)
        #expect(run("with 0 failures", in: text)?.foregroundColor == DSColor.diffAdded)
        #expect(run("with 10 failures", in: text)?.foregroundColor == nil)
        #expect(run("error: fatalError", in: text)?.foregroundColor == DSColor.attentionInk(.error))
    }
}
