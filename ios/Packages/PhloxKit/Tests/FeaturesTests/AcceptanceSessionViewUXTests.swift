import Foundation
import SwiftUI
import Testing
import PhloxCore
@testable import Features

// task-1 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md
// 目的:
//   A-1 セッション詳細を開いたら、本文が後から届いても必ず最下部（最新）が見える。
//   C-1 詳細画面から端スワイプで前の画面へ戻れる（ナビバー非表示＋自前 topBar は維持）。
//   D-1/D-2 ターミナル（pty）セッションの出力を、タップ無しで全文・桁揃えのまま読める。

// MARK: - A-1 初期スクロール

@Suite("Acceptance: セッション詳細を開いたら最下部（最新）から見える（task-1）")
struct SessionDetailInitialScrollAcceptanceTests {

    @Test("onAppear 時点で本文が空なら初回スクロールを消費しない")
    func emptyContentDoesNotConsumeInitialScroll() {
        var state = SessionDetailScrollFollowState()

        let decision = state.onContentChanged(hasContent: false, distanceFromBottom: 4000)

        #expect(decision == false, "本文が無い時点ではスクロール要求を出さないこと")
        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == true,
            "空の通知で初回判定を使い切らず、本文が届いた最初の1回で最下部へ寄せること"
        )
    }

    @Test("本文が届いた最初の1回は最下部から遠くても必ず最下部へ寄せる")
    func firstContentArrivalScrollsToBottomRegardlessOfDistance() {
        var state = SessionDetailScrollFollowState()

        let decision = state.onContentChanged(hasContent: true, distanceFromBottom: 4000)

        #expect(
            decision == true,
            "初回表示は距離判定（80pt）に依らず最下部へ寄せること（最上部で開く退行の防止）"
        )
    }

    @Test("初回以降は最下部付近にいる時だけ追従する")
    func laterUpdatesFollowOnlyNearBottom() {
        var state = SessionDetailScrollFollowState()
        _ = state.onContentChanged(hasContent: true, distanceFromBottom: 0)

        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 0) == true)
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 80) == true, "閾値ちょうどは追従する")
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 81) == false, "閾値を超えたら追従しない")
        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == false,
            "上へ読み戻している間は新着で引き戻さないこと（既存の追従方針を壊さない）"
        )
    }

    @Test("セッションを切り替えたら、また初回として最下部から開く")
    func sessionSwitchRestartsInitialScroll() {
        var state = SessionDetailScrollFollowState()
        _ = state.onContentChanged(hasContent: true, distanceFromBottom: 0)
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == false)

        state.reset()

        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == true,
            "別セッションを開いたら初回扱いに戻り、最下部から表示すること"
        )
    }

    @Test("View が初期スクロール状態を経由して追従判定している")
    func viewRoutesFollowDecisionThroughState() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(
            source.contains("SessionDetailScrollFollowState"),
            "SessionDetailView が SessionDetailScrollFollowState を経由して追従判定すること"
        )
    }
}

// MARK: - C-1 スワイプバック

@Suite("Acceptance: セッション詳細から端スワイプで戻れる（task-1 / ADR 0033）")
struct SessionDetailBackSwipeAcceptanceTests {

    /// 端スワイプは iOS 標準の `interactivePopGestureRecognizer` に委ねる。UIKit はナビゲーション
    /// バーを隠した画面ではこのジェスチャを拒否するため、詳細画面はバーを隠さないことが唯一の条件。
    /// 実際に指で戻れるかは XCUITest（`SessionDetailBackSwipeUITests`）で検証する。
    @Test("詳細画面はナビゲーションバーを隠さず、端スワイプを UIKit 標準のまま成立させる")
    func detailKeepsSystemNavigationBarSoPopGestureWorks() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(
            SessionDetailView.providesBackSwipeGesture,
            "実装と同時にフラグを反転すること（フラグだけの反転は虚偽報告として扱う）"
        )
        #expect(
            !source.contains(".toolbar(.hidden, for: .navigationBar)"),
            "ナビバーを隠すと UIKit が端スワイプ pop を拒否する（ADR 0033）"
        )
        #expect(
            !source.contains("InteractivePopGestureRestorer"),
            "delegate を差し替えて無理に通す迂回は使わないこと（pop 後に一覧の大タイトルが失われる）"
        )
    }

    /// 戻る導線はシステムの戻るボタンに委ねる。`navigationItem.leftBarButtonItem` を自前に差し替えると
    /// UIKit が端スワイプ pop を拒否するため、独自の戻るボタンを置いてはいけない。
    @Test("戻るボタンは自前で置かず、システムの戻るボタンを使う")
    func detailDoesNotInstallItsOwnBackButton() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(source.contains(".toolbarRole(.editor)"))
        #expect(
            !source.contains("chevron.left"),
            "自前の戻るボタンは端スワイプ pop を拒否させる"
        )
        #expect(
            !source.contains("topBarLeading"),
            "leading へ自前の項目を置かない（システムの戻るボタンを潰さない）"
        )
    }
}

// MARK: - D-1 / D-2 ターミナル出力

@Suite("Acceptance: ターミナルセッションの出力がモバイルで読める（task-1）")
@MainActor
struct TerminalOutputVisibilityAcceptanceTests {

    private static let terminalSession = Session(
        id: "sess-foxglove",
        name: "Foxglove",
        agent: .claudeCode,
        status: .running,
        subtitle: "ターミナル",
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    @Test("30 行のターミナル出力は、開いた直後にタップ無しで全文が描画対象になる")
    func longTerminalOutputIsFullyVisibleRightAfterOpen() async {
        let output = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let api = MockAPI(outputOutcome: .success(output), messagesOutcome: .success([]))
        let viewModel = SessionDetailViewModel(session: Self.terminalSession, api: api)

        await viewModel.load()

        #expect(viewModel.showsChat == false, "構造化メッセージが無い pty セッションは出力表示になること")
        #expect(viewModel.outputText == output, "取得した出力がそのまま保持されること")
        #expect(
            SessionDetailMetrics.displayedOutput(
                text: viewModel.outputText,
                isExpanded: viewModel.isOutputExpanded
            ) == output,
            "開いた直後（ユーザー操作なし）に出力の全文が描画対象になること（「出力」トグルだけの空表示の防止）"
        )
    }

    @Test("折りたたみ閾値を超えない短い出力も、開いた直後から全文が見える")
    func shortTerminalOutputIsAlsoVisible() async {
        let output = "› running tests...\nOK"
        let api = MockAPI(outputOutcome: .success(output), messagesOutcome: .success([]))
        let viewModel = SessionDetailViewModel(session: Self.terminalSession, api: api)

        await viewModel.load()

        #expect(
            SessionDetailMetrics.displayedOutput(
                text: viewModel.outputText,
                isExpanded: viewModel.isOutputExpanded
            ) == output
        )
    }

    @Test("ターミナル出力は桁揃えを保つため横スクロールで提供される")
    func outputIsProvidedWithHorizontalScroll() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(
            SessionDetailView.providesTerminalOutputHorizontalScroll,
            "実装と同時にフラグを反転すること（フラグだけの反転は虚偽報告として扱う）"
        )
        #expect(
            source.contains("ScrollView(.horizontal"),
            "出力を横スクロールで提供すること（TUI の桁揃えを折り返しで壊さない）"
        )
    }
}

// MARK: - ハーネス

/// テストファイル位置を起点に PhloxKit のソースを読む。
enum SessionViewUXSource {
    static func text(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/FeaturesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PhloxKit
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
