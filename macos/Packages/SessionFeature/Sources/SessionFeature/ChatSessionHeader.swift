import SwiftUI
import AgentDomain
import DesignSystem

/// 会話の上端のセッションヘッダ（04 H1〜H3）。
/// タイトル（＋命名タグ）/ エージェント · モデル · 作業ディレクトリ · ブランチ / サブエージェントの帯 / 状態 / 書き出し。
/// 高さは 56pt に固定する（中身の高さを会話のレイアウトへ戻さない）。
struct ChatSessionHeader: View {
    @Bindable var viewModel: ChatSessionViewModel
    let agentDescriptor: AgentDescriptor
    let onToggleSubAgent: (String) -> Void

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showsExport = false
    @State private var branch: String?
    @FocusState private var isRenameFocused: Bool
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    static let height: CGFloat = SubAgentSplitLayout.headerHeight

    var body: some View {
        let _ = themeID
        HStack(spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                metaRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !viewModel.stripSubAgents.isEmpty {
                subAgentChips
            }
            stateView
            exportButton
        }
        .padding(.leading, 18)
        .padding(.trailing, DSSpacing.l)
        .frame(height: Self.height)
        .background(DSColor.chatBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("セッションヘッダ"))
        // .git/HEAD の読み取りは描画ごとにせず、見えている間 2 秒ごとに読み直す（入力欄・エージェント・
        // 外部のどこでブランチを切り替えても追いつく）。値が変わったときだけ書く。
        .task(id: viewModel.rawWorkspacePath) {
            let path = viewModel.rawWorkspacePath
            while !Task.isCancelled {
                let current = GitBranchReader.currentBranch(at: path)
                if current != branch { branch = current }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - タイトル

    private var presentation: SessionTitlePresentation {
        SessionTitlePresentation(
            state: viewModel.titleState,
            fallback: SessionViewModel.shortID(for: viewModel.id),
            workspacePath: viewModel.workspacePath
        )
    }

    @ViewBuilder
    private var titleRow: some View {
        if isRenaming {
            TextField(text: $renameText, prompt: Text(verbatim: presentation.primary)) {
                Text("セッション名")
            }
            .textFieldStyle(.plain)
            .font(DSFont.sessionTitle)
            .focused($isRenameFocused)
            .onSubmit(commitRename)
            .onExitCommand { isRenaming = false }
            .onChange(of: isRenameFocused) { _, focused in
                if !focused, isRenaming { commitRename() }
            }
        } else {
            HStack(spacing: 7) {
                Text(verbatim: presentation.primary)
                    .font(DSFont.sessionTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(presentation.helpText)
                    .onTapGesture(count: 2, perform: beginRename)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityAction(named: Text("名前を変更…"), beginRename)
                if let tag = namingTag {
                    Text(tag)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                }
            }
        }
    }

    /// H1 花名・H2 内容からの自動生成にだけ付ける。手動の名前（H3）には付けない。
    private var namingTag: LocalizedStringKey? {
        switch viewModel.titleState.source {
        case .flower: "自動の名前（花名）"
        case .derived: "自動"
        case .manual: nil
        }
    }

    private func beginRename() {
        renameText = viewModel.titleState.name
        isRenaming = true
        isRenameFocused = true
    }

    private func commitRename() {
        isRenaming = false
        viewModel.name = renameText
    }

    // MARK: - エージェント · モデル · 作業ディレクトリ · ブランチ

    private var metaRow: some View {
        HStack(spacing: 7) {
            Text(verbatim: agentLine)
                .fixedSize()
            separatorDot
            Text(verbatim: viewModel.workspacePath)
                .font(DSFont.monoCaption)
                .truncationMode(.middle)
            if let branch {
                separatorDot
                Text(verbatim: branch)
                    .font(DSFont.monoCaption)
                    .fixedSize()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(DSColor.textSecondary)
        .lineLimit(1)
    }

    private var separatorDot: some View {
        Text(verbatim: "·").foregroundStyle(DSColor.textTertiary)
    }

    /// 「Claude Code · Opus · high」。Cursor は推論の強さを持たないのでモデル名まで。
    private var agentLine: String {
        let model = viewModel.selectedModel.map { selected in
            viewModel.availableModels.first { $0.id == selected || $0.model == selected }?.displayName
                ?? viewModel.spawnAgentModelDisplayName(selected)
        }
        return [agentDescriptor.displayName, model, viewModel.selectedEffort]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - サブエージェントの帯（C3）

    private var subAgentChips: some View {
        HStack(spacing: DSSpacing.xs) {
            Text("サブ")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(viewModel.stripSubAgents) { subAgent in
                        SubAgentStripRow(
                            subAgent: subAgent,
                            isSelected: viewModel.selectedSubAgentId == subAgent.id,
                            onSelect: { onToggleSubAgent(subAgent.id) },
                            onDismiss: { viewModel.dismissSubAgent(subAgent.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: 320)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("サブエージェント"))
    }

    // MARK: - 状態

    @ViewBuilder
    private var stateView: some View {
        if viewModel.isStalled {
            // B5: 「無応答 2:14」。1 秒ごとに更新する。
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let silence = viewModel.hangAssessment(now: context.date)?.silence ?? 0
                stateChip(Text("無応答 \(ThinkingIndicatorCell.clockText(silence))"), kind: .stalled)
            }
        } else if displayState.attentionKind != nil {
            // 12 S: 「承認待ち · 3分」。対応待ちに入ってからの経過を 1 分ごとに更新する。
            TimelineView(.periodic(from: viewModel.statusEnteredAt ?? .now, by: 60)) { context in
                StatusCapsuleBadge(
                    state: displayState,
                    elapsed: viewModel.statusEnteredAt.map {
                        SessionRelativeTime.label(from: $0, to: context.date, locale: locale)
                    }
                )
            }
        } else {
            // PhloxChat.dc.html: 12pt の文字だけ（実行中は medium）。待機は「待機 · 2分前に応答」、圧縮中は「実行中 · 圧縮中」。
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Self.plainStateText(
                    displayState.localizedLabel(locale: locale),
                    state: displayState,
                    isCompacting: viewModel.isCompacting,
                    lastRespondedAt: viewModel.lastTurnCompletedAt,
                    now: context.date,
                    exitCode: viewModel.processExit?.exitCode
                )
                .font(DSFont.auxiliary.weight(displayState == .running ? .medium : .regular))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    static func plainStateText(
        _ label: String,
        state: SessionDisplayState,
        isCompacting: Bool,
        lastRespondedAt: Date?,
        now: Date,
        exitCode: Int32? = nil
    ) -> Text {
        let base = Text(verbatim: label)
        if state == .running, isCompacting {
            return Text("\(base) · 圧縮中")
        }
        // 04 B3: プロセスが 0 で終わったら「完了 · exit 0」（0 以外はエラーの表示のまま）。
        if state == .done || state == .doneUnread, let exitCode {
            return Text("\(base) · exit \(Int(exitCode))")
        }
        guard state == .idle, let lastRespondedAt else { return base }
        let minutes = max(0, Int(now.timeIntervalSince(lastRespondedAt) / 60))
        if minutes < 1 { return Text("\(base) · たった今応答") }
        if minutes < 60 { return Text("\(base) · \(minutes)分前に応答") }
        return Text("\(base) · \(minutes / 60)時間前に応答")
    }

    private var displayState: SessionDisplayState {
        SessionDisplayState.resolve(
            viewModel.displayStatus,
            hasUnseenCompletion: viewModel.hasUnseenCompletion,
            isStalled: viewModel.isStalled
        )
    }

    /// 無応答の「無応答 2:14」（秒で動くので数字を等幅にする）。
    private func stateChip(_ text: Text, kind: AttentionKind) -> some View {
        text
            .font(DSFont.auxiliary.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DSColor.attentionInk(kind))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(DSColor.attentionTint(kind), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }

    // MARK: - 書き出し（C6）

    private var exportButton: some View {
        Button {
            showsExport.toggle()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(DSFont.row)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("会話を書き出す（⇧⌘E）")
        .accessibilityLabel(Text("会話を書き出す（⇧⌘E）"))
        .popover(isPresented: $showsExport, arrowEdge: .bottom) {
            ChatExportPopover(viewModel: viewModel, title: presentation.primary) {
                showsExport = false
            }
            .environment(\.locale, locale)
        }
    }
}

/// 書き出しの選択肢（04 C6）。設定はアプリ全体で記憶する。
private struct ChatExportPopover: View {
    let viewModel: ChatSessionViewModel
    let title: String
    let onDone: () -> Void

    @Environment(\.locale) private var locale
    @AppStorage(ChatTranscriptExportOptions.includesReasoningKey)
    private var includesReasoning = ChatTranscriptExportOptions().includesReasoning
    @AppStorage(ChatTranscriptExportOptions.includesCommandOutputKey)
    private var includesCommandOutput = ChatTranscriptExportOptions().includesCommandOutput
    @AppStorage(ChatTranscriptExportOptions.includesTimestampsKey)
    private var includesTimestamps = ChatTranscriptExportOptions().includesTimestamps

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("会話を Markdown で書き出す")
                .font(DSFont.row.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            Text("\(title) · メッセージ \(messageCount)")
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Toggle("推論を含める", isOn: $includesReasoning)
            Toggle("コマンド出力を含める", isOn: $includesCommandOutput)
            Toggle("タイムスタンプを含める", isOn: $includesTimestamps)
            HStack(spacing: DSSpacing.s) {
                Button {
                    ChatTranscriptExportAction.copyToPasteboard(session: viewModel)
                    onDone()
                } label: {
                    HStack(spacing: 6) {
                        Text("コピー")
                        Text(verbatim: "⌥⇧⌘C").foregroundStyle(DSColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Button {
                    onDone()
                    ChatTranscriptExportAction.save(session: viewModel, locale: locale)
                } label: {
                    Text("書き出す…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .toggleStyle(.checkbox)
        .tint(DSColor.accentFill)
        .font(DSFont.dense)
        .padding(.horizontal, 18)
        .padding(.top, DSSpacing.l)
        .padding(.bottom, 14)
        .frame(width: 320)
    }

    private var messageCount: Int {
        viewModel.transcript.filter {
            switch $0 {
            case .userMessage, .agentMessage: true
            default: false
            }
        }.count
    }
}
