import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

public struct ChatSessionView: View {
    @Bindable var viewModel: ChatSessionViewModel
    @State private var requestedTranscriptTarget: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    // サブエージェント横並び分割（Bug2/3/4）: 右ペイン比率を永続化。ドラッグ中のみ liveWidth を使う。
    @AppStorage("phlox.chat.subAgentPaneFraction") private var subAgentPaneFraction: Double = SubAgentSplitLayout.defaultFraction
    @State private var subAgentPaneLiveWidth: CGFloat?
    @State private var subAgentPaneWidthAtDragStart: CGFloat = 0
    @State private var composerHeight: CGFloat = 0

    public init(viewModel: ChatSessionViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    public var body: some View {
        let _ = themeID
        GeometryReader { geometry in
            // Bug2: overlay で本文の上に浮かせず、HStack 水平分割の左右カラムとして並べる
            // （右ペイン出現時はメインが縮んで両方可視。裏に隠れない）。
            HStack(spacing: 0) {
                // 幅は親から演繹する。自身のレイアウト結果を GeometryReader で計測して
                // @State に書き、それをレイアウト入力へ戻さない（駆動源#1・ADR 0010 クラス）。
                mainColumn(width: mainColumnWidth(for: geometry.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let selectedSubAgent {
                    // メイン｜サブの境界線（他の境界線と同一の 1pt separator）。
                    Rectangle()
                        .fill(DSColor.separator)
                        .frame(width: 1)
                    SubAgentDrawerView(
                        subAgent: selectedSubAgent,
                        transcript: viewModel.subAgentTranscript(for: selectedSubAgent.id),
                        agentDescriptor: agentDescriptor,
                        onClose: { viewModel.selectSubAgent(nil) }
                    )
                    .frame(width: subAgentPaneWidth(for: geometry.size.width))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Bug3: 境界のリサイズ掴みしろ。DashboardView のインスペクタと同型で、区切り線の
            // 真上に最前面オーバーレイとして重ねる（右ペイン左端 = 幅ぶん左へ offset）。
            // 表示条件はドロワー本体（`selectedSubAgent`）と同一述語に揃える。id が非nilでも
            // subAgents に不在ならドロワーは出ないため、グリップだけ宙に浮くのを構造的に防ぐ。
            .overlay(alignment: .topTrailing) {
                if selectedSubAgent != nil {
                    ResizeGripView(
                        onChanged: { value in
                            let available = geometry.size.width
                            if subAgentPaneLiveWidth == nil {
                                subAgentPaneWidthAtDragStart = subAgentPaneWidth(for: available)
                            }
                            let proposed = subAgentPaneWidthAtDragStart - value.translation.width
                            let fraction = available > 0 ? Double(proposed / available) : SubAgentSplitLayout.defaultFraction
                            subAgentPaneLiveWidth = SubAgentSplitLayout.paneWidth(fraction: fraction, availableWidth: available)
                        },
                        onEnded: {
                            let available = geometry.size.width
                            if let width = subAgentPaneLiveWidth, available > 0 {
                                subAgentPaneFraction = min(max(Double(width / available), 0.0), 1.0)
                            }
                            subAgentPaneLiveWidth = nil
                        }
                    )
                    .offset(x: -(subAgentPaneWidth(for: geometry.size.width) + 0.5 - ResizeGripView.gripWidth / 2))
                }
            }
        }
        .background(DSColor.chatBackground)
        .animation(.easeOut(duration: 0.18), value: viewModel.selectedSubAgentId)
        // esc 状態機械（非フォーカス時の経路）＋履歴ピッカー overlay＋下書き復元を一括で付ける（task-9）。
        .chatEscapeHandling(viewModel: viewModel)
        // cancelOperation フォールバック（フォーカス無し等で .onKeyPress が発火しない経路）。
        // 3経路（keyDown / onKeyPress / onExitCommand）を統一ハンドラ performChatEscape へ収束させ、
        // フォーカス非依存で「ドロワー閉じ→中止」を等価にする（Bug1: 非フォーカス時に ESC が中止に
        // 届かず drawer 閉じだけになっていた欠陥の修正）。
        // 排他の前提: .onKeyPress(.escape) は .handled を返すため同一 ESC は cancelOperation へ
        // 伝搬せず onExitCommand と二重発火しない（onKeyPress 発火＝SwiftUI フォーカス有り／
        // onExitCommand 発火＝フォーカス無し、で相互排他）。破れると単発 ESC が「中止＋履歴ピッカー
        // 誤発火（handleEscapeKey が 2連打と誤判定）」になり得るため、フェーズ4 runtime で
        // 「単発 ESC＝中止のみ・ピッカー非表示」を実機確認する（docs/guides/vision-ui-test.md）。
        .onExitCommand {
            performChatEscape(viewModel)
        }
    }

    /// メインカラム幅を body 最上位の GeometryReader から演繹する（右ペイン・境界線ぶんを差し引く）。
    private func mainColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        var width = availableWidth
        if selectedSubAgent != nil {
            width -= subAgentPaneWidth(for: availableWidth) + 1
        }
        return max(0, width)
    }

    /// メインチャットのカラム（トランスクリプト／コンポーザ）。
    /// セッション名はタイトルバー（設定ボタン右）に表示済みのため、カラム内ヘッダー行は置かない。
    private func mainColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ApprovalBanner(viewModel: viewModel)
            ChatTranscriptView(
                viewModel: viewModel,
                contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width),
                bottomScrollContentMargin: composerHeight,
                requestedScrollTarget: $requestedTranscriptTarget,
                onSelectSubAgent: { viewModel.selectSubAgent($0) }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if viewModel.shouldOfferHistoryStart {
                        GeometryReader { overlayGeometry in
                            let availableHeight = overlayGeometry.size.height
                            let cardMaxHeight = ChatHistoryStartLayout.maxCardHeight(
                                availableHeight: availableHeight,
                                composerHeight: composerHeight
                            )
                            let bottomInset = ChatHistoryStartLayout.bottomInset(
                                composerHeight: composerHeight
                            )
                            ChatHistoryStartView(
                                entries: viewModel.historyEntries,
                                maxCardHeight: cardMaxHeight,
                                onSelect: { entry in
                                    Task { await viewModel.startFromHistory(entry) }
                                }
                            )
                            .padding(DSSpacing.xl)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, bottomInset)
                        }
                        .transition(.opacity)
                    }
                }
                .overlay {
                    if viewModel.shouldShowConnectingIndicator {
                        ChatConnectingIndicator()
                    }
                }
                .animation(.easeOut(duration: 0.15), value: viewModel.shouldOfferHistoryStart)
                // ストリップはトランスクリプトのレイアウト兄弟にせず safeAreaInset で上部に置く。
                // 兄弟配置(VStack)だと出現/消滅・行数変化のたびに LazyVStack の配置キャッシュが
                // 再配置ループに入り main thread が固着する（2026-07-03 実測・sample:
                // LazySubviewPlacements→commitPlacedSubviews の非収束。ADR 0010 クラス）。
                // safeAreaInset はスクロールコンテンツの安全域を一方向にインセットするのみで
                // ストリップ高さ→コンテンツ位置の一方向依存にとどまり、overlay と違い本文を
                // 覆い隠さない（ユーザーの最初のメッセージが隠れる問題を解消）。
                .safeAreaInset(edge: .top, spacing: 0) {
                    SessionActivityOverlayStrip(
                        backgroundTasks: viewModel.runningBackgroundTasks,
                        transcriptItemIDs: { viewModel.transcriptItemIDs },
                        subAgents: viewModel.stripSubAgents,
                        selectedSubAgentId: viewModel.selectedSubAgentId,
                        onJump: { requestedTranscriptTarget = $0 },
                        onSelectSubAgent: toggleSubAgentSelection
                    )
                }
                // composer は ScrollView の上に浮かせ、ScrollView 自体は画面下端まで広げる。
                // 実測高はスクロールコンテンツ余白にだけ使い、composer 自身のサイズ決定へ戻さない。
                .overlay(alignment: .bottom) {
                    let proposedComposerWidth = ComposerLayout.proposedWidth(mainColumnWidth: width)
                    ChatComposer(
                        viewModel: viewModel,
                        text: $viewModel.draft,
                        isRunning: viewModel.showsProcessingIndicator,
                        canSend: viewModel.isReadyForInput,
                        controlsLayout: proposedComposerWidth.map(ComposerLayout.controlsLayout(proposedWidth:)) ?? .standard,
                        onSend: sendDraft,
                        onInterrupt: interruptTurn
                    )
                    .frame(maxWidth: proposedComposerWidth)
                    .frame(maxWidth: .infinity)
                    // パネル上端から下の帯を背景色でマスクし、スクロール中のコンテンツ・
                    // アイコンが余白の背後に見えないようにする（上端はパネル上端まで＝
                    // 上余白帯 DSSpacing.m はマスクしない。コンテンツはパネル上端で切れる）。
                    // 右端はスクロールバー通り道ぶんを除外（塗るとバーの下端到達が崩れる。
                    // トランスクリプトの水平 padding = DSSpacing.l = 16pt なので通り道に
                    // コンテンツは描画されない）。
                    .background {
                        DSColor.chatBackground
                            .padding(.top, DSSpacing.m)
                            .padding(.trailing, ComposerLayout.scrollerCorridorWidth)
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        composerHeight = height
                    }
                }
        }
        .background(DSColor.chatBackground)
    }

    /// 右ペイン幅。ドラッグ中は liveWidth、それ以外は永続比率からクランプして算出。
    private func subAgentPaneWidth(for availableWidth: CGFloat) -> CGFloat {
        if let subAgentPaneLiveWidth { return subAgentPaneLiveWidth }
        return SubAgentSplitLayout.paneWidth(fraction: subAgentPaneFraction, availableWidth: availableWidth)
    }


    private var agentDescriptor: AgentDescriptor {
        if let kind = viewModel.agentRef.builtinKind {
            return AgentRegistry.descriptor(for: kind)
        }
        return AgentDescriptor(
            ref: viewModel.agentRef,
            displayName: viewModel.agentRef.id,
            binaryName: viewModel.agentRef.id,
            symbolName: "terminal",
            colorRGB: AgentRGB(0x8A, 0x8F, 0x98),
            bypassKey: "phlox.bypass.\(viewModel.agentRef.id)",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
    }

    private var selectedSubAgent: SubAgentRef? {
        guard let id = viewModel.selectedSubAgentId else { return nil }
        return viewModel.subAgents.first { $0.id == id }
    }

    private func toggleSubAgentSelection(_ id: String) {
        viewModel.selectSubAgent(viewModel.selectedSubAgentId == id ? nil : id)
    }

    private func sendDraft() {
        guard let text = viewModel.consumeDraftForSend() else { return }
        Task {
            try? await viewModel.sendText(text, submit: true)
        }
    }

    private func interruptTurn() {
        Task {
            await viewModel.turnInterrupt()
        }
    }
}
