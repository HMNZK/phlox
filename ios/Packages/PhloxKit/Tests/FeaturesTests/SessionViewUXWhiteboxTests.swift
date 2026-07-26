import Foundation
import SwiftUI
import Testing
import AgentDomain
import PhloxCore
@testable import Features

@Suite("セッション詳細 UX の白箱テスト（task-1）")
struct SessionViewUXWhiteboxTests {

    @Test("根画面で既に有効な端スワイプは変更しない")
    func rootHostKeepsItsExistingGestureState() {
        let host = NavigationHost(depth: 1, isGestureEnabled: true)

        #expect(InteractivePopGestureRestorer.restore(on: host) == false)
        #expect(host.isInteractivePopGestureEnabled == true)
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

    @Test("View は描画可能本文と初回状態の述語を経由してスクロールを決める")
    func viewRoutesScrollDecisionThroughNamedPredicates() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")
        let function = try #require(SourceFunction.body(named: "scrollToBottomForContentChange", in: source))

        #expect(function.contains("Self.hasRenderableContent("))
        #expect(function.contains("visibleMessages: viewModel.visibleMessages"))
        #expect(!function.contains("viewModel.chatMessages"))
        #expect(function.contains("Self.shouldAnimateScroll("))
        #expect(function.contains("hasPerformedInitialScroll: scrollFollowState.hasPerformedInitialScroll"))

        // PM 追記: 初回だけ即時にする正しさは評価順序に依存する。onContentChanged が
        // hasPerformedInitialScroll を true へ書き換える前に読まないと、初回もアニメーションに戻る。
        let animateIndex = try #require(function.range(of: "Self.shouldAnimateScroll(")).lowerBound
        let decideIndex = try #require(function.range(of: "scrollFollowState.onContentChanged(")).lowerBound
        #expect(
            animateIndex < decideIndex,
            "初回判定が消費される前に hasPerformedInitialScroll を読むこと（順序を入れ替えると初回もアニメーションする）"
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

    /// PM 追記: 上のテストは高さ未指定の提案しか使わないため、`.fixedSize` の縦軸を外しても
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

    @Test("UIKit 接続層は iOS 条件コンパイル内に隔離し、判定層は UIKit 型へ触れない")
    func interactivePopUIKitBridgeStaysIsolated() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/InteractivePopGestureRestorer.swift")
        let importRange = try #require(source.range(of: "import UIKit"))
        let iosGuardRange = try #require(source.range(of: "#if os(iOS)"))
        let guardEndRange = try #require(source.range(of: "#endif", range: iosGuardRange.upperBound..<source.endIndex))
        let restorer = try #require(SourceDeclaration.body(named: "InteractivePopGestureRestorer", in: source))

        #expect(iosGuardRange.lowerBound < importRange.lowerBound && importRange.upperBound < guardEndRange.lowerBound)
        #expect(!restorer.contains("UINavigationController"), "UIKit 接続層ではなく判定層が UINavigationController に触れている")
    }

    private func terminalOutput(lineCount: Int) -> String {
        Array(repeating: String(repeating: "x", count: 200), count: lineCount)
            .joined(separator: "\n")
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

private final class NavigationHost: InteractivePopGestureHost {
    let navigationStackDepth: Int
    var isInteractivePopGestureEnabled: Bool

    init(depth: Int, isGestureEnabled: Bool) {
        navigationStackDepth = depth
        isInteractivePopGestureEnabled = isGestureEnabled
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

private enum SourceDeclaration {
    static func body(named name: String, in source: String) -> String? {
        guard let declarationRange = source.range(of: "enum \(name) {") ?? source.range(of: "struct \(name) {") else {
            return nil
        }
        let bodyStart = source.index(before: declarationRange.upperBound)

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
