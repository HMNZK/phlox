import Foundation
import XCTest
import PhloxCore
@testable import Features

/// task-4 追加の受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 追加の経緯: 第1ラウンドのレビューで、レイアウト費用が **総バイト数に比例し、件数にはほぼ
/// 依存しない**ことが実測された（6MB は 300 件でも 1 件でも約 0.67 秒）。
/// 描画窓は「件数」しか縛らないため、**単一の巨大出力**（`npm install` のログ等）が主因の場合は
/// 窓だけでは症状が消えない。親画面がこれで固まらないのはツールコールを畳んで
/// `lineLimit(1)` プレビューにしているからであり、サブエージェント画面にはその制限が無い。
/// よって PM の裁定として「**1 メッセージあたりの描画バイト数の上限**」を契約に追加する。
///
/// 凍結する契約:
///  1. 表示用の本文は 1 メッセージあたり上限バイト数で切り詰められる。
///  2. 上限以下の本文は一切変更されない（切り詰めが常時発動して表示が壊れない）。
///  3. 上限は正の有限値で、64KiB 以下（＝必ず縛られる）。
///  4. 切り詰めはマルチバイト文字の途中で切らない（文字化けを作らない）。
///  5. 省略したバイト数が観測できる（ユーザーに「省略された」ことを示せる）。
///  6. **コピーは全文のまま**（表示を削ってもデータは失わせない）。
///  7. View が実際に切り詰めを経由して描画している（ソース assert）。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// ```swift
/// extension SubAgentDetailViewModel {
///     /// 1 メッセージあたりの描画バイト数の上限（UTF-8 バイト）
///     static var maxRenderedBytesPerMessage: Int { get }
///     /// 表示用に本文を切り詰める。切り詰めていなければ omittedBytes == 0。
///     static func renderedBody(_ text: String) -> (text: String, omittedBytes: Int)
/// }
/// ```
final class AcceptanceSubAgentRenderBudgetTests: XCTestCase {

    private var limit: Int { SubAgentDetailViewModel.maxRenderedBytesPerMessage }

    // MARK: - 契約3: 上限が有限で十分小さい

    func testRenderBudgetIsFiniteAndBounded() {
        XCTAssertGreaterThan(limit, 0, "描画バイト上限は正の値であること")
        XCTAssertLessThanOrEqual(
            limit,
            64 * 1024,
            "上限は 64KiB 以下（レイアウト費用は総バイト数に比例するため、必ず縛る）"
        )
    }

    // MARK: - 契約2: 上限以下は素通し

    func testShortBodyIsUnchanged() {
        let body = "短い出力\nこれは切り詰められない"
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertEqual(rendered.text, body, "上限以下の本文は一切変更しない")
        XCTAssertEqual(rendered.omittedBytes, 0)
    }

    func testBodyExactlyAtLimitIsUnchanged() {
        let body = String(repeating: "x", count: limit)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertEqual(rendered.text, body, "ちょうど上限なら切り詰めない（境界で1文字も削らない）")
        XCTAssertEqual(rendered.omittedBytes, 0)
    }

    // MARK: - 契約1・5: 上限超えは切り詰められ、省略量が分かる

    func testHugeBodyIsTruncatedToBudget() {
        let body = String(repeating: "x", count: limit * 10)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertLessThanOrEqual(
            rendered.text.utf8.count,
            limit,
            "描画対象の本文は上限バイト数を超えない（単一の巨大出力でメインスレッドを詰まらせない）"
        )
        XCTAssertGreaterThan(
            rendered.omittedBytes,
            0,
            "省略したことが観測できる（黙って本文を消さない）"
        )
        XCTAssertEqual(
            rendered.omittedBytes,
            body.utf8.count - rendered.text.utf8.count,
            "省略バイト数は「元のバイト数 − 残したバイト数」と一致すること"
        )
    }

    func testTruncationKeepsTheHead() {
        let body = "先頭の重要な行\n" + String(repeating: "y", count: limit * 4)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertTrue(
            rendered.text.hasPrefix("先頭の重要な行"),
            "切り詰めても先頭は残す（親画面と同じくプレビューとして読める形にする）"
        )
    }

    // MARK: - 契約4: マルチバイト文字を壊さない

    func testTruncationDoesNotSplitMultibyteCharacters() {
        // 1 文字 3 バイトの日本語だけで上限を大きく超える本文を作る。
        let body = String(repeating: "あ", count: limit)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertLessThanOrEqual(rendered.text.utf8.count, limit)
        XCTAssertTrue(
            rendered.text.allSatisfy { $0 == "あ" },
            "マルチバイト文字の途中で切らない（文字化けした本文を描画しない）"
        )
        XCTAssertEqual(
            rendered.omittedBytes,
            body.utf8.count - rendered.text.utf8.count
        )
    }

    // MARK: - 契約6・7: View の配線（コピーは全文・描画は切り詰め）

    func testSubAgentDetailViewRendersThroughBudgetAndCopiesFullText() throws {
        let source = try sourceText("Sources/Features/SessionDetail/SubAgentDetailView.swift")
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(
            compact.contains("renderedBody("),
            "View は表示本文を renderedBody 経由で作ること（巨大出力を素のまま Text に渡さない）"
        )
        XCTAssertTrue(
            compact.contains("ChatMessageCopyText.copyText(for:message)"),
            "コピーは切り詰めた本文ではなく元のメッセージから作ること（表示を削ってもデータは失わない）"
        )
    }

    // MARK: - helpers

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
