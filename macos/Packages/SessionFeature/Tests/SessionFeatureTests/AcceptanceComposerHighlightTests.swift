import Foundation
import Testing
@testable import SessionFeature

// task-2 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: ComposerHighlight.spans(in:) の純関数仕様（tasks/task-2.md）。
//   - 先頭スラッシュコマンド（先頭のみ・最初の空白で停止）を1件
//   - 空白区切りで "@" 始まりトークンを各1件
//   - range は UTF16 オフセット・決定論

private func u16Range(of sub: String, in text: String) -> Range<Int> {
    guard let r = text.range(of: sub) else {
        Issue.record("部分文字列 \(sub) が \(text) に見つからない（ハーネス欠陥）")
        return 0..<0
    }
    return r.lowerBound.utf16Offset(in: text)..<r.upperBound.utf16Offset(in: text)
}

@Suite("Acceptance: 入力欄ハイライト範囲（task-2）")
struct AcceptanceComposerHighlightTests {
    @Test func 先頭スラッシュコマンドを1件返す() {
        let text = "/help"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "/help", in: text), kind: .slashCommand)])
    }

    @Test func スラッシュコマンドは最初の空白で止まる() {
        let text = "/help me"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "/help", in: text), kind: .slashCommand)])
    }

    @Test func 先頭以外のスラッシュはハイライトしない() {
        #expect(ComposerHighlight.spans(in: "hello /run").isEmpty)
    }

    @Test func アット参照トークンを返す() {
        let text = "@file.txt"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "@file.txt", in: text), kind: .fileReference)])
    }

    @Test func 複数のアット参照を各1件返す() {
        let text = "review @a.md and @b.md"
        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: u16Range(of: "@a.md", in: text), kind: .fileReference),
            ComposerHighlightSpan(range: u16Range(of: "@b.md", in: text), kind: .fileReference),
        ])
    }

    @Test func スラッシュとアットが混在() {
        let text = "/deploy @config.yaml"
        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: u16Range(of: "/deploy", in: text), kind: .slashCommand),
            ComposerHighlightSpan(range: u16Range(of: "@config.yaml", in: text), kind: .fileReference),
        ])
    }

    @Test func トークン先頭でないアットは無視() {
        #expect(ComposerHighlight.spans(in: "email a@b.com").isEmpty)
    }

    @Test func CJKを含む場合もUTF16オフセットが正しい() {
        let text = "こんにちは @メモ.txt"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "@メモ.txt", in: text), kind: .fileReference)])
    }

    @Test func 空文字列は空() {
        #expect(ComposerHighlight.spans(in: "").isEmpty)
    }
}
