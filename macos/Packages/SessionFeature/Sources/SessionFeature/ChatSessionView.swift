import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

public struct ChatSessionView: View {
    @Bindable var viewModel: ChatSessionViewModel
    let projectName: String?
    @State private var requestedTranscriptTarget: String?
    @State private var fileChangeRevealRequest: FileChangeRevealRequest?
    @State private var isComposerPopupOpen = false
    /// 「新しい会話を始める」で履歴の一覧を閉じた（このビューが生きている間だけ）。
    @State private var historyStartDismissed = false
    /// スクラバーのハイライトをトランスクリプトのスクロール位置に連動させるための現在位置。
    /// 値の更新はトランスクリプトの NSScrollView イベント側からのみ行う（ADR 0010）。
    @State private var currentInputPositionID: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @State private var composerHeight: CGFloat = 0

    public init(viewModel: ChatSessionViewModel, projectName: String? = nil) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.projectName = projectName
    }

    public var body: some View {
        let _ = themeID
        GeometryReader { geometry in
            // 幅は親から演繹して固定する。中身の最小幅が割り当てを越えても窓の外へあふれない。
            mainColumn(width: geometry.size.width)
                .frame(width: geometry.size.width, alignment: .leading)
                .frame(maxHeight: .infinity)
                .environment(\.replySubjectMaxHeight, ApprovalCard.subjectMaxHeight(availableHeight: geometry.size.height))
        }
        .background(DSColor.chatBackground)
        // esc 状態機械（非フォーカス時の経路）＋履歴ピッカー overlay＋下書き復元を一括で付ける（task-9）。
        .chatEscapeHandling(viewModel: viewModel)
        // cancelOperation フォールバック（フォーカス無し等で .onKeyPress が発火しない経路）。
        // 3経路（keyDown / onKeyPress / onExitCommand）を統一ハンドラ performChatEscape へ収束させ、
        // フォーカス非依存で ESC を等価にする。
        // 排他の前提: .onKeyPress(.escape) は .handled を返すため同一 ESC は cancelOperation へ
        // 伝搬せず onExitCommand と二重発火しない（onKeyPress 発火＝SwiftUI フォーカス有り／
        // onExitCommand 発火＝フォーカス無し、で相互排他）。破れると単発 ESC が「中止＋履歴ピッカー
        // 誤発火（handleEscapeKey が 2連打と誤判定）」になり得るため、フェーズ4 runtime で
        // 「単発 ESC＝中止のみ・ピッカー非表示」を実機確認する（docs/guides/vision-ui-test.md）。
        .onExitCommand {
            performChatEscape(viewModel)
        }
    }

    /// メインチャットのカラム（サブエージェントの札／トランスクリプト／コンポーザ）。
    private func mainColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ChatTranscriptView(
                viewModel: viewModel,
                contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width),
                bottomScrollContentMargin: composerHeight,
                requestedScrollTarget: $requestedTranscriptTarget,
                currentInputPositionID: $currentInputPositionID
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.fileChangeRevealRequest, fileChangeRevealRequest)
                .overlay {
                    if viewModel.shouldOfferHistoryStart && !historyStartDismissed {
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
                                summaries: viewModel.historySummaries,
                                maxCardHeight: cardMaxHeight,
                                workingDirectory: viewModel.rawWorkspacePath,
                                agentName: agentDescriptor.displayName,
                                onSelect: { entry in
                                    Task { await viewModel.startFromHistory(entry) }
                                },
                                onStartNew: { historyStartDismissed = true }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.bottom, bottomInset)
                        }
                        .transition(.opacity)
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
                    // バックグラウンドタスクとサブエージェントの札（グリッドと共通。子がいなければ出ない）。
                    SessionActivityOverlayStrip(
                        viewModel: viewModel,
                        onJump: { requestedTranscriptTarget = $0 }
                    )
                }
                // composer は ScrollView の上に浮かせ、ScrollView 自体は画面下端まで広げる。
                // 実測高はスクロールコンテンツ余白にだけ使い、composer 自身のサイズ決定へ戻さない。
                .overlay(alignment: .bottom) {
                    let proposedComposerWidth = ComposerLayout.proposedWidth(mainColumnWidth: width)
                    // 承認・質問のカードと送信失敗の通知は入力欄の直上（05）。高さの実測は余白にだけ使う。
                    ChatReplyArea(viewModel: viewModel, showsKeyHints: viewModel.processExit == nil, onShowDiff: showDiff, onRetrySend: sendDraft) {
                        // 04 B3: プロセスが終わったら入力欄の代わりに終了コードと再開を出す。
                        if let processExit = viewModel.processExit {
                            ChatProcessEndedStrip(exit: processExit, onResume: viewModel.resumeConversationHandler)
                        } else {
                            ChatComposer(
                                viewModel: viewModel,
                                text: $viewModel.draft,
                                isRunning: viewModel.showsProcessingIndicator,
                                canSend: viewModel.isReadyForInput,
                                projectName: projectName,
                                controlsLayout: proposedComposerWidth.map(ComposerLayout.controlsLayout(proposedWidth:)) ?? .standard,
                                onSend: sendDraft,
                                onInterrupt: interruptTurn
                            )
                            // 入力履歴の目盛りは入力欄の右上に重ねる（右 12・上へ 9 はみ出す。PhloxReply.dc.html）。
                            // 入力欄の外側の余白（左右 m・上 s）ぶんを足して位置を合わせる。
                            // 入力欄の上に箱・候補・ツールチップが開いている間は、重なるので隠す。
                            .onPreferenceChange(ComposerPopupOpenKey.self) { isComposerPopupOpen = $0 }
                            .overlay(alignment: .topTrailing) {
                                if !isComposerPopupOpen {
                                    ChatInputHistoryScrubber(
                                        entries: viewModel.inputHistoryEntries,
                                        currentPositionID: currentInputPositionID,
                                        onJump: { target in
                                            // クリック時は即座に対象を強調（楽観的更新）し、実スクロールで確定させる。
                                            currentInputPositionID = target
                                            requestedTranscriptTarget = target
                                        }
                                    )
                                    .padding(.trailing, DSSpacing.m + 12)
                                    .offset(y: DSSpacing.s - 9)
                                }
                            }
                        }
                    }
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

    /// 承認カードの「差分を見る」: 会話の該当のファイルの変更へ移り、開く（05 R6e）。
    private func showDiff(_ itemID: String) {
        requestedTranscriptTarget = itemID
        fileChangeRevealRequest = FileChangeRevealRequest(itemID: itemID, token: (fileChangeRevealRequest?.token ?? 0) + 1)
    }

    private func sendDraft() {
        guard let text = viewModel.consumeDraftForSend() else { return }
        Task {
            do {
                try await viewModel.sendText(text, submit: true)
            } catch {
                viewModel.reportError("ターン開始に失敗しました: \(error)")
            }
        }
    }

    private func interruptTurn() {
        Task {
            await viewModel.turnInterrupt()
        }
    }
}
