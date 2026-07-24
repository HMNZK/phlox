import AppKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Markdown no truncation whitebox", .serialized)
@MainActor
struct MarkdownNoTruncationWhiteboxTests {
    private func sourceText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func fittingHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @Test("段落・見出しの縦サイズ確保は表テーマより前の非表ブロックに限定する")
    func paragraphAndHeadingsReserveHeightOutsideTables() throws {
        let source = try sourceText("RichMarkdownView.swift")
        let paragraphRange = try #require(source.range(of: ".paragraph {"))
        let tableRange = try #require(source.range(of: ".table {"))
        let nonTableTheme = String(source[paragraphRange.lowerBound..<tableRange.lowerBound])

        #expect(paragraphRange.lowerBound < tableRange.lowerBound)
        #expect(nonTableTheme.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!String(source[tableRange.lowerBound...]).contains("fixedSize"))
    }

    @Test("見出し4〜6も表より前で折り返し行の高さを確保する")
    func lowerLevelHeadingsReserveHeightOutsideTables() throws {
        let source = try sourceText("RichMarkdownView.swift")
        let tableRange = try #require(source.range(of: ".table {"))
        let nonTableTheme = String(source[..<tableRange.lowerBound])

        for level in 4...6 {
            let heading = ".heading\(level) { configuration in\n            configuration.label\n                .fixedSize(horizontal: false, vertical: true)"
            #expect(nonTableTheme.contains(heading))
        }
    }

    @Test("長い日本語段落と後続見出しは狭幅で全行分の高さを確保する")
    func japaneseParagraphAndFollowingHeadingReserveWrappedHeight() {
        let text = """
        を全部やっています。グリッドで複数セッションが一斉にワーッと出力すると、この1人に仕事が殺到して、あなたが見ている画面の更新やキー入力が順番待ちになる。これがカクつき・もたつきの正体です。

        ## 意外だったこと

        これは次の段落です。
        """

        let wideHeight = fittingHeight(RichMarkdownView(text), width: 1_400)
        let narrowHeight = fittingHeight(RichMarkdownView(text), width: 360)

        #expect(narrowHeight >= wideHeight + 14)
    }
}
