import Foundation
import XCTest
import PhloxCore
@testable import Features

/// task-4 追加の受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 追加の経緯: レビューで、レイアウト費用が **総バイト数に比例し、件数にはほぼ依存しない**ことが
/// 実測された（6MB は 300 件でも 1 件でも約 0.6 秒）。描画窓は「件数」しか縛らないため、
/// **単一の巨大出力**（`npm install` のログ等）が主因の場合は窓だけでは症状が消えない。
/// 親画面がこれで固まらないのはツールコールを畳んで `lineLimit(1)` プレビューにしているからであり、
/// サブエージェント画面にはその制限が無い。よって「1 メッセージあたりの描画バイト上限」を契約に追加する。
///
/// **改訂（第2ラウンドのレビュー指摘を受けた PM 裁定）**:
/// 当初は「先頭を残す」仕様にしていたが、この画面の目的は「**起動中の**サブエージェントが今何をしているか」
/// を見ることであり、同じ機能の描画窓が末尾（最新）を取るのと原則が矛盾していた。
/// 6MB のログで先頭 16KiB しか読めないと、直近の出力へアプリ内で到達する手段が無くなる。
/// そこで **先頭と末尾の両方を残す**（間を省略する）仕様へ改める。
///
/// 凍結する契約:
///  1. 表示用の本文は 1 メッセージあたり上限バイト数で切り詰められる。
///  2. 上限以下の本文は一切変更されない（切り詰めが常時発動して表示が壊れない）。
///  3. 上限は正の有限値で、64KiB 以下（＝必ず縛られる）。
///  4. 切り詰めたときは **先頭と末尾の両方**が残る（最新の出力に必ず到達できる）。
///  5. 切り詰めはマルチバイト文字の途中で切らない（文字化けを作らない）。
///  6. 省略したバイト数が観測できる（ユーザーに「省略された」ことを示せる）。
///  7. **コピーは全文のまま**（表示を削ってもデータは失わせない）。
///  8. View が実際に切り詰めを経由して描画している（ソース assert）。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// ```swift
/// extension SubAgentDetailViewModel {
///     /// 表示用に切り詰めた本文。`omittedBytes == 0` なら切り詰めていない（このとき tail は空）。
///     struct RenderedBody: Equatable {
///         let head: String
///         let tail: String
///         let omittedBytes: Int
///     }
///     /// 1 メッセージあたりの描画バイト上限（UTF-8 バイト。head と tail の合計に適用する）
///     static var maxRenderedBytesPerMessage: Int { get }
///     static func renderedBody(_ text: String) -> RenderedBody
/// }
/// ```
/// View は `head` ＋ 省略の注記（省略バイト数を含む）＋ `tail` の順で描画すること。
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

        XCTAssertEqual(rendered.head, body, "上限以下の本文は一切変更しない")
        XCTAssertEqual(rendered.tail, "", "切り詰めていないときは tail を使わない")
        XCTAssertEqual(rendered.omittedBytes, 0)
    }

    func testBodyExactlyAtLimitIsUnchanged() {
        let body = String(repeating: "x", count: limit)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertEqual(rendered.head, body, "ちょうど上限なら切り詰めない（境界で1文字も削らない）")
        XCTAssertEqual(rendered.tail, "")
        XCTAssertEqual(rendered.omittedBytes, 0)
    }

    // MARK: - 契約1・6: 上限超えは切り詰められ、省略量が分かる

    func testHugeBodyIsTruncatedToBudget() {
        let body = String(repeating: "x", count: limit * 10)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertLessThanOrEqual(
            rendered.head.utf8.count + rendered.tail.utf8.count,
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
            body.utf8.count - (rendered.head.utf8.count + rendered.tail.utf8.count),
            "省略バイト数は「元のバイト数 − 残したバイト数」と一致すること"
        )
    }

    // MARK: - 契約4: 先頭と末尾の両方を残す

    func testTruncationKeepsBothHeadAndTail() {
        let head = "先頭の重要な行\n"
        let tail = "\n最後の重要な行"
        let body = head + String(repeating: "y", count: limit * 4) + tail
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertFalse(rendered.head.isEmpty, "先頭を残すこと")
        XCTAssertFalse(
            rendered.tail.isEmpty,
            "末尾を残すこと（起動中のサブエージェントが今何をしているかを見る画面なので、最新に到達できること）"
        )
        XCTAssertTrue(
            body.hasPrefix(rendered.head),
            "head は元の本文の先頭からの連続した一部であること"
        )
        XCTAssertTrue(
            body.hasSuffix(rendered.tail),
            "tail は元の本文の末尾までの連続した一部であること"
        )
        XCTAssertTrue(
            rendered.tail.hasSuffix("最後の重要な行"),
            "最新の出力が読めること（末尾が切り落とされていない）"
        )
    }

    // MARK: - 契約5: マルチバイト文字を壊さない

    func testTruncationDoesNotSplitMultibyteCharacters() {
        // 1 文字 3 バイトの日本語だけで上限を大きく超える本文を作る。
        let body = String(repeating: "あ", count: limit)
        let rendered = SubAgentDetailViewModel.renderedBody(body)

        XCTAssertLessThanOrEqual(rendered.head.utf8.count + rendered.tail.utf8.count, limit)
        XCTAssertTrue(
            (rendered.head + rendered.tail).allSatisfy { $0 == "あ" },
            "マルチバイト文字の途中で切らない（文字化けした本文を描画しない）"
        )
        XCTAssertEqual(
            rendered.omittedBytes,
            body.utf8.count - (rendered.head.utf8.count + rendered.tail.utf8.count)
        )
    }

    // MARK: - 契約7・8: View の配線（コピーは全文・描画は切り詰め）

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
        XCTAssertTrue(
            compact.contains("omittedBytes"),
            "省略したことと省略量を View が表示すること（黙って本文を消さない）"
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
