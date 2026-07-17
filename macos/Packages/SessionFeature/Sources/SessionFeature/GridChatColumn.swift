import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

/// グリッド表示の appServer タイル用。読み取り専用のトランスクリプトに、承認バナーと
/// 各タイルから直接返信できる composer を足す（single へ切り替えずグリッドのまま返信・承認可能にする）。
struct GridChatColumn: View {
    @Bindable var viewModel: ChatSessionViewModel
    @State private var composerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // 承認が無いときは非表示・場所を取らない（単体表示と同じ）。
                ApprovalBanner(viewModel: viewModel)
                ChatTranscriptView(
                    viewModel: viewModel,
                    transcript: selectedSubAgentTranscript,
                    showsThinkingIndicator: viewModel.selectedSubAgentId == nil,
                    contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: geo.size.width),
                    bottomScrollContentMargin: composerHeight,
                    presentationContext: .gridTile,
                    onSelectSubAgent: { viewModel.selectSubAgent($0) }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 単一表示と同じく safeAreaInset で置く（VStack 兄弟だと出現/行数変化で
                    // LazyVStack 再配置ループ＝ADR 0010 非収束を招く。safeAreaInset は一方向依存で安全）。
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SubAgentStrip(
                            subAgents: viewModel.stripSubAgents,
                            selectedSubAgentId: viewModel.selectedSubAgentId,
                            includesMainButton: true,
                            onSelectMain: { viewModel.selectSubAgent(nil) },
                            onSelectSubAgent: { viewModel.selectSubAgent($0) }
                        )
                    }
                    .overlay(alignment: .bottom) {
                        let proposedComposerWidth = ComposerLayout.proposedWidth(mainColumnWidth: geo.size.width)
                        GridComposerBar(
                            viewModel: viewModel,
                            text: $viewModel.draft,
                            controlsLayout: proposedComposerWidth.map(ComposerLayout.gridControlsLayout(proposedWidth:)) ?? .compact,
                            onSend: sendDraft,
                            onInterrupt: interruptTurn
                        )
                        .frame(maxWidth: ComposerLayout.maxWidth(mainColumnWidth: geo.size.width))
                        .frame(maxWidth: .infinity)
                        // パネル上端から下の帯のマスク（ChatSessionView と同型。上余白帯は
                        // マスクせず、右端はスクロールバー通り道を除外）。
                        .background {
                            DSColor.chatBackground
                                .padding(.top, DSSpacing.s)
                                .padding(.trailing, ComposerLayout.scrollerCorridorWidth)
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            composerHeight = height
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // グリッドタイルからも esc 状態機械・履歴ピッカー・下書き復元を動かす（task-9）。
        .chatEscapeHandling(viewModel: viewModel)
        // cancelOperation フォールバック（単一表示 ChatSessionView と対称）。二重発火の排他前提と
        // フェーズ4 runtime 確認については ChatSessionView の .onExitCommand コメントを参照。
        .onExitCommand {
            performChatEscape(viewModel)
        }
    }

    private var selectedSubAgentTranscript: [ChatItem]? {
        guard let selectedSubAgentId = viewModel.selectedSubAgentId else { return nil }
        return viewModel.subAgentTranscript(for: selectedSubAgentId)
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

/// グリッドタイル専用の composer。単一表示 `ChatComposer` と同じく 40〜160 で auto-grow する。
/// 高さの測定と収束は単一表示と同じ `IMESafeTextView` / `ComposerHeightPolicy` に委ねる。
///
/// 沿革（なぜ固定高40を撤去して安全か）: かつてグリッドは min==max==40 に固定していた。これは
/// 「可変高 composer がトランスクリプトの自動追従スクロールと干渉し CPU 100%固着する」ための防御的
/// 回避策だった（旧 ADR 0010）。しかしその固着の真因は (1) Bug A＝描画パス(updateNSView)中の同期 state
/// 書込、(2) トランスクリプトの LazyVStack 自走レイアウトループ であり、いずれも ADR 0030 で
/// 「高さ書込を event 文脈＋遅延Task に限定」「LazyVStack→VStack 化」により根治済み。真因が消えた今、
/// 固定高40は冗長なので撤去し、共有機構（`shouldWrite` 0.5pt ガードで高々1回の固定点収束）へ委ねる。
/// 注: この安全性の最終確認は runtime 依存（grid＋スクロール＋実行中セッションでの CPU 収束）であり、
/// 実機検証で裏を取る（swift test では原理的に証明できない）。
struct GridComposerBar: View {
    @Bindable var viewModel: ChatSessionViewModel
    @Binding var text: String
    var controlsLayout: ComposerFooterLayout?
    let onSend: () -> Void
    let onInterrupt: () -> Void
    @State private var editorHeight: CGFloat = ComposerHeightBounds.grid.min
    @State private var isComposing = false
    @State private var suggestionController: ComposerSuggestionController

    init(
        viewModel: ChatSessionViewModel,
        text: Binding<String>,
        controlsLayout: ComposerFooterLayout? = nil,
        onSend: @escaping () -> Void,
        onInterrupt: @escaping () -> Void
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _text = text
        self.controlsLayout = controlsLayout
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        _suggestionController = State(
            wrappedValue: ComposerSuggestionController.production(workingDirectory: viewModel.workspacePath)
        )
    }

    private var canSubmit: Bool {
        viewModel.isReadyForInput
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
    }

    var body: some View {
        if let controlsLayout {
            composerContent(controlsLayout: controlsLayout)
        } else {
            GeometryReader { geo in
                let proposedWidth = ComposerLayout.proposedWidth(mainColumnWidth: geo.size.width) ?? geo.size.width
                composerContent(controlsLayout: ComposerLayout.gridControlsLayout(proposedWidth: proposedWidth))
                    .frame(maxWidth: geo.size.width)
            }
        }
    }

    private func composerContent(controlsLayout: ComposerFooterLayout) -> some View {
        // パネル全体≈80px の要件（ADR 0046）: 間隔 xs に圧縮（8+36+4+28+8=84）。
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if suggestionController.isPresented {
                ComposerSuggestionPopup(controller: suggestionController, onAccept: acceptSuggestionFromPopup)
                    .accessibilityIdentifier("GridComposer.suggestions")
            }
            ComposerAttachmentStrip(store: viewModel.attachmentStore, layout: controlsLayout.settingsLayout)
            ZStack(alignment: .topLeading) {
                IMESafeTextView(
                    text: $text,
                    isComposing: $isComposing,
                    measuredHeight: $editorHeight,
                    minHeight: ComposerHeightBounds.grid.min,
                    maxHeight: ComposerHeightBounds.grid.max,
                    suggestionController: suggestionController,
                    onSubmit: onSend,
                    onPasteImage: addPastedImage,
                    onEscape: { performChatEscape(viewModel) }
                )
                .frame(
                    minHeight: ComposerHeightBounds.grid.min,
                    idealHeight: editorHeight,
                    maxHeight: ComposerHeightBounds.grid.max
                )
                .accessibilityIdentifier("GridComposer.input")
                if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
                    Text("メッセージを入力")
                        .font(ComposerPlaceholderMetrics.placeholderFont)
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .padding(.horizontal, ComposerPlaceholderMetrics.textInsets.width)
                        .padding(.vertical, ComposerPlaceholderMetrics.textInsets.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)
            .padding(.horizontal, DSSpacing.xs)

            ChatComposerFooter(
                viewModel: viewModel,
                layout: controlsLayout,
                isRunning: viewModel.showsProcessingIndicator,
                canSubmit: canSubmit,
                onSend: onSend,
                onInterrupt: onInterrupt,
                accessibilityPrefix: "GridComposer"
            )
        }
        .padding(DSSpacing.s)
        // フローティング配置（ADR 0065）: パネル本体を chatBackground で不透明化してから
        // white 4% ティントを重ねる（ChatComposer と同型。背後のメッセージが透けない）。
        .background {
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .fill(DSColor.chatBackground)
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(DSSpacing.s)
    }

    private func acceptSuggestionFromPopup(_ index: Int) {
        suggestionController.select(index)
        guard let replacement = suggestionController.acceptSelected() else { return }
        text = ComposerSuggestionTextReplacement.apply(replacement, to: text).text
    }

    /// 画像を添付できたら true。非対応エージェント（Claude 以外）では false を返し、
    /// 呼び出し側は同居テキストの通常ペースト（super.paste）へフォールバックする。
    private func addPastedImage(data: Data, mediaType: String) -> Bool {
        guard ComposerAttachmentCapability.supportsImageAttachments(agentRef: viewModel.agentRef) else {
            viewModel.attachmentStore.setError(ComposerAttachmentCapability.unsupportedImageMessage)
            return false
        }
        viewModel.attachmentStore.addImage(data: data, mediaType: mediaType)
        return true
    }
}
