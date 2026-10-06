import Foundation
import SwiftUI
import Testing
import PhloxCore
@testable import Features

// セッション詳細の UX:
//   - 開いたら本文が後から届いても必ず最下部（最新）が見える（初回スクロールと追従）。
//   - ターミナル（pty）セッションの出力を、タップ無しで全文・桁揃えのまま読める。

// MARK: - 初回スクロール

@Suite("セッション詳細: 開いたら最下部（最新）から見える")
struct SessionDetailInitialScrollTests {

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

    @Test("初回追従後の空更新は追従閾値の判定を維持する")
    func emptyUpdatesAfterInitialFollowDoNotResetState() {
        var state = SessionDetailScrollFollowState()

        let initialDecision = state.onContentChanged(hasContent: true, distanceFromBottom: 10_000)
        let emptyDecision = state.onContentChanged(hasContent: false, distanceFromBottom: 0)
        let laterDecision = state.onContentChanged(hasContent: true, distanceFromBottom: 81)

        #expect(initialDecision)
        #expect(!emptyDecision)
        #expect(!laterDecision)
    }

    @Test("初回スクロール状態は本文到着で消費し、セッション切替で復帰する")
    func initialScrollStateTransitionsOnContentAndReset() {
        var state = SessionDetailScrollFollowState()

        #expect(!state.hasPerformedInitialScroll)
        let shouldInitiallyScroll = state.onContentChanged(hasContent: true, distanceFromBottom: 10_000)
        #expect(shouldInitiallyScroll)
        #expect(state.hasPerformedInitialScroll)

        state.reset()

        #expect(!state.hasPerformedInitialScroll)
    }

    @MainActor
    @Test("初回スクロールは描画できる本文だけを判定する")
    func renderableContentExcludesEmptyReasoningAndIncludesVisibleContentOrOutput() async {
        let viewModel = SessionDetailViewModel(
            session: session(),
            api: MockAPI(messagesOutcome: .success([
                .reasoning(id: "m1", text: "   \n")
            ]))
        )

        await viewModel.load()

        #expect(!viewModel.chatMessages.isEmpty, "空の reasoning でも取得済みメッセージは存在する")
        #expect(viewModel.visibleMessages.isEmpty, "空白だけの reasoning は描画対象ではない")
        #expect(!SessionDetailView.hasRenderableContent(
            visibleMessages: viewModel.visibleMessages,
            outputText: viewModel.outputText
        ))
        #expect(SessionDetailView.hasRenderableContent(
            visibleMessages: [.agent(id: "m2", text: "本文")],
            outputText: ""
        ))
        #expect(SessionDetailView.hasRenderableContent(
            visibleMessages: [],
            outputText: "terminal output"
        ))
    }

    @MainActor
    @Test("初回スクロールだけはアニメーションしない")
    func onlySubsequentScrollsAreAnimated() {
        #expect(!SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: false))
        #expect(SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: true))
    }

    // 例外のソース検査: `scrollToBottomForContentChange` は private な View メソッドで、SwiftUI の
    // ホストなしには呼べない。初回だけ即時にする正しさは評価順序に依存するため、ここで順序を守る。
    @Test("View は描画可能本文と初回状態の述語を経由してスクロールを決める")
    func viewRoutesScrollDecisionThroughNamedPredicates() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")
        let function = try #require(SourceFunction.body(named: "scrollToBottomForContentChange", in: source))

        #expect(function.contains("Self.hasRenderableContent("))
        #expect(function.contains("visibleMessages: viewModel.visibleMessages"))
        #expect(!function.contains("viewModel.chatMessages"))
        #expect(function.contains("Self.shouldAnimateScroll("))
        #expect(function.contains("hasPerformedInitialScroll: scrollFollowState.hasPerformedInitialScroll"))

        // 初回だけ即時にする正しさは評価順序に依存する。onContentChanged が
        // hasPerformedInitialScroll を true へ書き換える前に読まないと、初回もアニメーションに戻る。
        let animateIndex = try #require(function.range(of: "Self.shouldAnimateScroll(")).lowerBound
        let decideIndex = try #require(function.range(of: "scrollFollowState.onContentChanged(")).lowerBound
        #expect(
            animateIndex < decideIndex,
            "初回判定が消費される前に hasPerformedInitialScroll を読むこと（順序を入れ替えると初回もアニメーションする）"
        )
    }

    private func session() -> Session {
        Session(
            id: "whitebox-session",
            name: "Whitebox",
            agent: .claudeCode,
            status: .running,
            subtitle: "ターミナル",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - ターミナル出力

@Suite("セッション詳細: ターミナルセッションの出力がモバイルで読める")
@MainActor
struct TerminalOutputVisibilityTests {

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

    @MainActor
    @Test("ターミナル出力はユーザー操作前から展開状態で始まる")
    func terminalOutputStartsExpanded() {
        let session = Session(
            id: "whitebox-session",
            name: "Whitebox",
            agent: .claudeCode,
            status: .running,
            subtitle: "ターミナル",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let viewModel = SessionDetailViewModel(session: session, api: MockAPI())

        #expect(viewModel.isOutputExpanded)
    }

    @MainActor
    @Test("出力本体は横にクランプせず、折り返さず、高さ未指定でも行数に応じて縦へ伸びる")
    func outputBodyPreservesTerminalLayoutUnderVerticalScrollProposal() {
        let thirtyLines = terminalOutput(lineCount: 30)
        let sixtyLines = terminalOutput(lineCount: 60)

        let thirtyLineSize = OutputLayoutProbe.measure(SessionDetailOutputBody(text: thirtyLines))
        let sixtyLineSize = OutputLayoutProbe.measure(SessionDetailOutputBody(text: sixtyLines))

        #expect(thirtyLineSize.width > 1_000, "横スクロール用の中身をビューポート幅へクランプしないこと。size=\(thirtyLineSize)")
        #expect(thirtyLineSize.height > 300, "height=nil の提案でも30行分の高さを返すこと。size=\(thirtyLineSize)")
        #expect(thirtyLineSize.height < 800, "200桁の各行を折り返さず、30行分の高さに保つこと。size=\(thirtyLineSize)")
        #expect(sixtyLineSize.height > thirtyLineSize.height + 300, "行数を増やすと高さも比例して伸びること。30=\(thirtyLineSize) 60=\(sixtyLineSize)")
    }

    /// 上のテストは高さ未指定の提案しか使わないため、`.fixedSize` の縦軸を外しても
    /// 結果が変わらず検出力がない（縦軸あり 450pt / なし 450pt で区別不能）。確定高を提案すると
    /// 縦軸あり 450pt / なし 90pt で明確に分かれるので、こちらで縦軸をピン留めする。
    @MainActor
    @Test("確定高を提案されても出力本体は行数ぶんの高さを主張する（fixedSize の縦軸）")
    func outputBodyKeepsIdealHeightUnderDefiniteHeightProposal() {
        let thirtyLines = terminalOutput(lineCount: 30)

        let clampedProposalSize = OutputLayoutProbe.measure(
            SessionDetailOutputBody(text: thirtyLines),
            height: 100
        )

        #expect(
            clampedProposalSize.height > 300,
            "確定高 100pt を提案されても30行分の理想高を返すこと（縦軸を外すと提案値へ丸められる）。size=\(clampedProposalSize)"
        )
    }

    private func terminalOutput(lineCount: Int) -> String {
        Array(repeating: String(repeating: "x", count: 200), count: lineCount)
            .joined(separator: "\n")
    }
}

// MARK: - ナビゲーションバー（端スワイプで戻る）

@Suite("セッション詳細: システムのナビゲーションバーを使う")
struct SessionDetailNavigationChromeTests {
    // 例外のソース検査（ADR 0033）: ナビバーを隠す・自前 topBar に戻すと端スワイプ pop が拒否される。
    // ADR 0033 のとおりこの症状は自動テストで再現できていないため、構成の逆戻りをソースで防ぐ。
    @Test("詳細画面の chrome はシステムのナビゲーションバーへ載せる（ADR 0033）")
    func detailChromeUsesSystemNavigationBar() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(source.contains(".navigationTitle(title)"))
        #expect(source.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(source.contains("ToolbarItem(placement: .topBarTrailing) { menu() }"))
        #expect(
            !source.contains("private var topBar"),
            "自前 topBar を復活させない（ナビバーを隠す構成へ戻ると端スワイプが壊れる）"
        )
        #expect(
            !source.contains("interactivePopGestureRecognizer"),
            "UIKit のジェスチャへ直接触らないこと"
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

@MainActor
private enum OutputLayoutProbe {
    /// 既定は外側の縦 `ScrollView` と同じ提案（高さ未指定）。`height` を渡すと確定高を提案する
    /// ＝`.fixedSize` の縦軸が効いているかを区別できる（未指定だと軸の有無で結果が変わらない）。
    static func measure(_ view: some View, height: CGFloat? = nil) -> CGSize {
        let sink = OutputLayoutSizeSink()
        let renderer = ImageRenderer(
            content: ProposalProbe(width: 390, height: height, sink: { sink.size = $0 }) {
                view
            }
        )
        renderer.render { _, _ in }
        return sink.size
    }
}

private final class OutputLayoutSizeSink: @unchecked Sendable {
    var size = CGSize.zero
}

private struct ProposalProbe: Layout {
    let width: CGFloat
    let height: CGFloat?
    let sink: @Sendable (CGSize) -> Void

    init(width: CGFloat, height: CGFloat? = nil, sink: @escaping @Sendable (CGSize) -> Void) {
        self.width = width
        self.height = height
        self.sink = sink
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: height))
        sink(size)
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {}
}

private enum SourceFunction {
    static func body(named name: String, in source: String) -> String? {
        guard let declarationRange = source.range(of: "func \(name)") else { return nil }
        guard let bodyStart = source[declarationRange.upperBound...].firstIndex(of: "{") else { return nil }

        var depth = 1
        var index = source.index(after: bodyStart)
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[bodyStart...index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
