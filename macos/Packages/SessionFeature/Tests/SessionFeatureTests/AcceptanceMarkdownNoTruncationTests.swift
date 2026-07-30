import Foundation
import Testing
import AppKit
import SwiftUI
@testable import SessionFeature

// task-1 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md
// 目的: transcript のテキストが「…」で切り詰められる表示（クリックで全文が重なって
//       描画される不具合の温床）を廃止し、折り返し表示に統一する。
//       あわせて ADR 0045 の一線（markdown 表への .fixedSize 禁止）を守る。

@Suite("Acceptance: transcript テキストの「…」切り詰め廃止（task-1）")
@MainActor
struct AcceptanceMarkdownNoTruncationTests {

    // MARK: - ハーネス

    /// テストファイル位置を起点に SessionFeature のソースを読む。
    private func sourceText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent() // .../Tests/SessionFeatureTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../SessionFeature (package root)
            .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// 指定幅で SwiftUI ビューをホストしたときのレイアウト高さ。
    private func fittingHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        return hosting.fittingSize.height
    }

    // MARK: - DisclosureCard（コマンド・Reasoning 等の共通カード）

    @Test("長いタイトルは1行に切り詰めず折り返して全文表示される")
    func disclosureCardTitleWrapsInsteadOfTruncating() throws {
        let longTitle = String(repeating: "グリッドで複数セッションが一斉に出力するとカクつく問題の調査 ", count: 6)
        let shortCard = DisclosureCard(
            isExpanded: .constant(false),
            title: "短いタイトル",
            subtitle: nil,
            timestamp: .distantPast
        ) { EmptyView() }
        let longCard = DisclosureCard(
            isExpanded: .constant(false),
            title: longTitle,
            subtitle: nil,
            timestamp: .distantPast
        ) { EmptyView() }

        let shortHeight = fittingHeight(shortCard, width: 300)
        let longHeight = fittingHeight(longCard, width: 300)
        #expect(
            longHeight >= shortHeight + 10,
            "長いタイトルは折り返して高さが増えること（lineLimit(1)＋「…」切り詰めの廃止）。short=\(shortHeight) long=\(longHeight)"
        )
    }

    @Test("DisclosureCard のソースからテキスト切り詰め指定が除去されている")
    func disclosureCardSourceHasNoTruncation() throws {
        let source = try sourceText("ChatMessageCellsCommon.swift")
        #expect(
            !source.contains(".lineLimit("),
            "ChatMessageCellsCommon.swift（DisclosureCard）に .lineLimit( を残さないこと（「…」の温床）"
        )
        #expect(
            !source.contains(".truncationMode("),
            "ChatMessageCellsCommon.swift（DisclosureCard）に .truncationMode( を残さないこと"
        )
    }

    // MARK: - markdown 本文（段落の縦高さ確保）

    @Test("折り返しが必要な幅では段落＋見出しの高さが広幅より大きくなる（段落の縦高さが確保される）")
    func markdownParagraphReservesWrappedHeight() throws {
        let text = """
        を全部やっています。グリッドで複数セッションが一斉にワーッと出力すると、この1人に仕事が殺到して、\
        あなたが見ている画面の更新やキー入力が順番待ちになる。これがカクつき・もたつきの正体です。

        ## 意外だったこと

        これは次の段落です。
        """
        let wideHeight = fittingHeight(AgentMessageBody(text: text), width: 1400)
        let narrowHeight = fittingHeight(AgentMessageBody(text: text), width: 360)
        #expect(
            narrowHeight >= wideHeight + 14,
            "狭い幅では段落が折り返し、折り返した全行分の高さが確保されること（1行分しか確保されず「…」切り詰め・重なり描画になる退行の防止）。wide=\(wideHeight) narrow=\(narrowHeight)"
        )
    }

    // MARK: - ADR 0045 の一線（ハザードガード）

    @Test("markdown 表・表セルへ .fixedSize を適用しない（ADR 0045 の表レイアウト非収束の再発防止）")
    func markdownTableStaysFreeOfFixedSize() throws {
        let source = try sourceText("RichMarkdownView.swift")
        let tableRange = try #require(
            source.range(of: ".table {"),
            "RichMarkdownView.swift に .table テーマブロックが存在すること（段落系の修正は .table より前に置く契約）"
        )
        let afterTable = String(source[tableRange.lowerBound...])
        #expect(
            !afterTable.contains("fixedSize"),
            ".table 以降（表・表セル）に fixedSize を適用しないこと（ADR 0045: 表レイアウト非収束→CPU 100% 固着の再発防止）"
        )
    }
}
