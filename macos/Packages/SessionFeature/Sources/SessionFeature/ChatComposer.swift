import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

struct ChatComposer: View {
    @Bindable var viewModel: ChatSessionViewModel
    @Binding var text: String
    let isRunning: Bool
    let canSend: Bool
    let projectName: String?
    let onSend: () -> Void
    let onInterrupt: () -> Void
    let controlsLayout: ComposerFooterLayout
    @State private var editorHeight: CGFloat = ComposerHeightBounds.single.min
    @State private var isComposing = false
    @State private var isEditorFocused = false
    @State private var suggestionController: ComposerSuggestionController
    @Environment(\.locale) private var locale

    init(
        viewModel: ChatSessionViewModel,
        text: Binding<String>,
        isRunning: Bool,
        canSend: Bool,
        projectName: String? = nil,
        controlsLayout: ComposerFooterLayout = .standard,
        onSend: @escaping () -> Void,
        onInterrupt: @escaping () -> Void
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _text = text
        self.isRunning = isRunning
        self.canSend = canSend
        self.projectName = projectName
        self.controlsLayout = controlsLayout
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        let controller = ComposerSuggestionController.production(workingDirectory: viewModel.workspacePath)
        controller.onAcceptSkill = { [weak viewModel] identity in
            viewModel?.codexSkillSelectionState?.select(name: identity.name, path: identity.path)
        }
        _suggestionController = State(wrappedValue: controller)
    }

    var body: some View {
        // PhloxReply.dc.html の入力欄: 上 10・左右 12・下 8、本文と下段の間 10（空のとき高さ 74）。
        // 本文欄の内側余白 8（ComposerPlaceholderMetrics.textInsets）の分だけ外側を詰める。
        VStack(alignment: .leading, spacing: 2) {
            if let error = viewModel.codexSkillSelectionState?.errorMessage {
                Text("Codex skill の取得に失敗しました: \(error)")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusError)
                    .lineLimit(2)
                    .accessibilityIdentifier("ChatComposer.codexSkillError")
            }
            if let staleMessage = viewModel.codexSkillSelectionState?.invalidSelectionMessage {
                Text(staleMessage)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.statusAwaitingApprovalForeground)
                .lineLimit(2)
                .accessibilityIdentifier("ChatComposer.codexSkillStale")
            }
            ComposerAttachmentStrip(
                store: viewModel.attachmentStore,
                layout: controlsLayout.settingsLayout,
                imageNotice: ComposerAttachmentCapability.imageNotice(viewModel, locale: locale),
                onRemove: removeAttachment
            )
            .padding(.top, viewModel.attachmentStore.attachments.isEmpty && viewModel.attachmentStore.lastError == nil ? 0 : DSSpacing.s)
            ZStack(alignment: .topLeading) {
                IMESafeTextView(
                    text: $text,
                    isComposing: $isComposing,
                    measuredHeight: $editorHeight,
                    minHeight: ComposerHeightBounds.single.min,
                    maxHeight: ComposerHeightBounds.single.max,
                    suggestionController: suggestionController,
                    onSubmit: onSend,
                    onPasteImageOutcome: addPastedImage,
                    attachedImageNumbers: { viewModel.attachmentStore.attachments.map(\.number) },
                    imagesForCopy: { viewModel.attachmentStore.imagesForCopy(numbers: $0) },
                    onEscape: { performChatEscape(viewModel) },
                    focusRequest: viewModel.composerFocusRequest,
                    highlightsKeywords: viewModel.agentRef == .builtin(.claudeCode),
                    onTab: { viewModel.moveFocusToReplyCard() },
                    onRecallHistory: { viewModel.recallInputHistory($0) },
                    onCycleEffort: { ComposerEffortCycle.perform(viewModel, locale: locale) },
                    isEditable: viewModel.inFlightText == nil,
                    onFocusChange: { isEditorFocused = $0 }
                )
                .frame(
                    minHeight: ComposerHeightBounds.single.min,
                    idealHeight: editorHeight,
                    maxHeight: ComposerHeightBounds.single.max
                )
                .accessibilityIdentifier("ChatComposer.input")

                if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
                    // 送信中は送った本文を淡く残す（05 R4）。
                    Text(viewModel.inFlightText ?? placeholderText)
                        .font(ComposerPlaceholderMetrics.placeholderFont)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, ComposerPlaceholderMetrics.textInsets.width)
                        .padding(.vertical, ComposerPlaceholderMetrics.textInsets.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)
            .padding(.horizontal, -ComposerPlaceholderMetrics.textInsets.width)

            ChatComposerFooter(
                viewModel: viewModel,
                layout: controlsLayout,
                isRunning: isRunning || hasPendingReplyCard,
                canSubmit: canSubmit,
                sendUnavailableReason: sendUnavailableReason,
                onSend: onSend,
                onInterrupt: onInterrupt
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10 - ComposerPlaceholderMetrics.textInsets.height)
        .padding(.bottom, 8)
        // 面は `--field`（ダークでは背景より暗い #1A1A1C）、縁は `--fieldBorder` 1pt、書いている間は `--selText` の 3pt の輪。
        // 縁も背面に描く（前面だと、チップから上に開く箱の上に縁が引かれる）。
        .background {
            let shape = RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
            shape.fill(DSColor.fieldBackground)
                .overlay(shape.strokeBorder(DSColor.fieldBorder, lineWidth: 1))
        }
        .background {
            if isEditorFocused {
                RoundedRectangle(cornerRadius: DSRadius.l + 3, style: .continuous)
                    .fill(DSColor.focusRing)
                    .padding(-3)
            }
        }
        // 上のカード・候補との間は 8（PhloxReply.dc.html の rootStyle gap）。
        .overlay(alignment: .topLeading) {
            if suggestionController.isPresented {
                ComposerSuggestionPopup(controller: suggestionController, onAccept: acceptSuggestionFromPopup)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ChatComposer.suggestions")
                    .padding(.leading, 10)
                    .placedAbove(gap: 6)
            }
        }
        .reportsComposerPopup(suggestionController.isPresented)
        .padding(.horizontal, DSSpacing.m)
        .padding(.top, DSSpacing.s)
        .padding(.bottom, DSSpacing.m)
        .onChange(of: text) { oldValue, newValue in
            viewModel.syncAttachmentsWithDraftEdit(oldText: oldValue, newText: newValue)
            updateCodexSkillSuggestions()
        }
        .onAppear {
            suggestionController.availableSlashCommands = viewModel.availableSlashCommands
            suggestionController.seedSlashCommands = viewModel.seedSlashCommands
            updateCodexSkillSuggestions()
        }
        .onChange(of: viewModel.codexSkillSelectionState?.filteredSkills.map { "\($0.name)\u{0}\($0.path)" }) { _, _ in
            updateCodexSkillSuggestions()
        }
        .onChange(of: viewModel.codexSkillSelectionState?.isStale) { _, _ in
            updateCodexSkillSuggestions()
        }
        .onChange(of: viewModel.codexSkillSelectionState?.requiresReselection) { _, _ in
            updateCodexSkillSuggestions()
        }
        .onChange(of: viewModel.availableSlashCommands) { _, commands in
            suggestionController.availableSlashCommands = commands
        }
        .onChange(of: viewModel.seedSlashCommands) { _, commands in
            suggestionController.seedSlashCommands = commands
        }
    }

    /// 承認・質問を待っている間も実行中として扱う（■ を出す。PhloxReply.dc.html）。
    private var hasPendingReplyCard: Bool {
        !viewModel.replyApprovals.isEmpty || ChatReplyArea<EmptyView>.hasPendingQuestion(in: viewModel.transcript)
    }

    /// 状態ごとの案内（PhloxReply.dc.html の placeholder）。
    private var placeholderText: String {
        let key: String
        if !viewModel.replyApprovals.isEmpty {
            key = "承認待ちの間も入力できます（送信は承認後）"
        } else if ChatReplyArea<EmptyView>.hasPendingQuestion(in: viewModel.transcript) {
            key = "質問に答えるか、ここから別の指示を送れます"
        } else if isRunning {
            key = "実行中です。中断は Esc か ■"
        } else {
            key = "メッセージを入力 — / でコマンド、@ でファイル"
        }
        return AppLocalizedString.string(key, locale: locale)
    }

    /// 送れないときの理由（宛先の行をやめたので、送信ボタンの説明に出す）。
    private var sendUnavailableReason: String? {
        guard !canSubmit else { return nil }
        return ComposerDestinationLabel.text(
            for: .conversation(projectName: projectName, taskName: viewModel.displayName),
            hasDestination: true,
            isReadyForInput: canSend,
            hasContent: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !viewModel.attachmentStore.attachments.isEmpty
        )
    }

    private var canSubmit: Bool {
        canSend && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
    }

    private func acceptSuggestionFromPopup(_ index: Int) {
        suggestionController.select(index)
        guard let replacement = suggestionController.acceptSelected() else { return }
        text = ComposerSuggestionTextReplacement.apply(replacement, to: text).text
    }

    /// Codex の skills/list 結果を、入力中の slash 候補へ反映する。
    /// テストでは本番の ViewModel → Composer 経路を通して候補 identity を検証する。
    func updateCodexSkillSuggestions() {
        guard viewModel.agentRef == .builtin(.codex),
              let state = viewModel.codexSkillSelectionState,
              !state.isStale,
              let query = SuggestionTrigger.query(text: text, cursorUTF16: text.utf16.count),
              query.kind == .slashCommand
        else {
            suggestionController.updateExternalCandidates(nil)
            return
        }

        state.search(query.searchTerm)
        suggestionController.updateExternalCandidates(
            state.filteredSkills.compactMap { skill in
                guard skill.enabled, !skill.name.isEmpty, !skill.path.isEmpty else { return nil }
                return SuggestionCandidate(
                    title: "/\(skill.name)",
                    insertionText: "$\(skill.name)",
                    subtitle: skill.description,
                    kind: .slashCommand,
                    skillIdentity: SkillIdentity(name: skill.name, path: skill.path),
                    origin: .skills
                )
            }
        )
    }

    var suggestionControllerForTesting: ComposerSuggestionController {
        suggestionController
    }

    private func addPastedImage(data: Data, mediaType: String) -> ComposerPasteImageOutcome {
        ComposerAttachmentCapability.addPastedImage(to: viewModel, data: data, mediaType: mediaType, locale: locale)
    }

    private func removeAttachment(_ attachment: ComposerAttachment) {
        viewModel.attachmentStore.remove(id: attachment.id)
        text = ComposerImagePlaceholder.removing(number: attachment.number, from: text)
    }
}

struct ChatComposerFooter: View {
    @Bindable var viewModel: ChatSessionViewModel
    let layout: ComposerFooterLayout
    let isRunning: Bool
    let canSubmit: Bool
    /// 送れない理由（送信ボタンの説明と読み上げに出す）。
    var sendUnavailableReason: String? = nil
    let onSend: () -> Void
    let onInterrupt: () -> Void
    var accessibilityPrefix: String = "ChatComposer"
    var branchNameOverride: String?
    var branchIsCheckingOutOverride = false
    /// ブランチを出すか。既定は 600pt 以上（standard）だけ。グリッドは実際の幅で決める。
    var showsBranchOverride: Bool? = nil
    @Environment(\.locale) private var locale

    var body: some View {
        switch layout {
        case .minimal:
            minimalFooter
        case .standard, .compact:
            regularFooter
        }
    }

    private var regularFooter: some View {
        let settingsLayout = layout.settingsLayout
        // PhloxReply.dc.html の下段: ＋ モデル effort 権限 …… ブランチ コンテキスト 送信。
        return HStack(spacing: 6) {
            ComposerSettingsControlsView(
                viewModel: viewModel,
                layout: settingsLayout,
                side: .leading,
                accessibilityPrefix: accessibilityPrefix
            )
            Spacer(minLength: DSSpacing.s)
            ComposerContextIndicator(
                usage: viewModel.lastTurnUsage,
                workspacePath: viewModel.workspacePath,
                layout: settingsLayout == .compact ? .compact : .regular,
                branchNameOverride: branchNameOverride,
                branchIsCheckingOutOverride: branchIsCheckingOutOverride,
                showsBranch: showsBranchOverride ?? (settingsLayout != .compact),
                suggestsCompact: viewModel.agentRef != .builtin(.cursor)
            )
            .accessibilityIdentifier("\(accessibilityPrefix).contextIndicator")
            sendOrStopButton
        }
        .frame(height: 26)
    }

    private var minimalFooter: some View {
        HStack(spacing: DSSpacing.s) {
            ComposerAttachPlaceholder(
                viewModel: viewModel,
                layout: .compact,
                accessibilityIdentifier: "\(accessibilityPrefix).attachPlaceholder"
            )
            ComposerSettingsOverflowMenu(
                viewModel: viewModel,
                workspacePath: viewModel.workspacePath,
                accessibilityIdentifier: "\(accessibilityPrefix).overflowMenu"
            )
            Spacer(minLength: DSSpacing.s)
            sendOrStopButton
        }
    }

    /// 右端の丸ボタン（05 R1・R4・R5）。送信中は「…」、実行中（承認・質問待ちを含む）は ■（中断）、それ以外は送信。
    /// 実行中に書いた追加の指示は ↩ で送る（PhloxReply.dc.html: 実行中は常に ■）。
    @ViewBuilder
    private var sendOrStopButton: some View {
        if viewModel.inFlightText != nil {
            ComposerRoundButton(style: .sending, action: {})
                .disabled(true)
                .accessibilityLabel(Text("送信中"))
                .accessibilityIdentifier("\(accessibilityPrefix).sendButton")
        } else if isRunning {
            ComposerRoundButton(style: .stop, action: onInterrupt)
                .help("中断（Esc / ⌘.）")
                .accessibilityLabel(Text("中断"))
                .accessibilityIdentifier("\(accessibilityPrefix).stopButton")
        } else {
            ComposerRoundButton(style: .send, action: onSend)
                .disabled(!canSubmit)
                .help(sendUnavailableReason ?? AppLocalizedString.string("送信", locale: locale))
                .accessibilityLabel(Text("送信"))
                .accessibilityHint(sendUnavailableReason.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
                .accessibilityIdentifier("\(accessibilityPrefix).sendButton")
        }
    }
}

private struct ComposerRoundButton: View {
    enum Style {
        case send
        case sending
        case stop
    }

    let style: Style
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                if isHovering && isEnabled && style == .send {
                    Circle().fill(Color.white.opacity(0.14))
                }
                symbol
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
        switch style {
        case .send: isEnabled ? DSColor.accentFill : DSColor.segmentTrack
        case .sending: DSColor.segmentTrack
        case .stop: DSColor.textPrimary
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch style {
        case .send:
            Text(verbatim: "↑")
                .font(DSFont.row.weight(.bold))
                .foregroundStyle(isEnabled ? Color.white : DSColor.textTertiary)
        case .sending:
            Text(verbatim: "…")
                .font(DSFont.row.weight(.bold))
                .foregroundStyle(DSColor.textTertiary)
        case .stop:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DSColor.fieldBackground)
                .frame(width: 8, height: 8)
        }
    }
}

struct ComposerSuggestionPopup: View {
    @Bindable var controller: ComposerSuggestionController
    /// 一度に見せる行数。グリッドのタイルは高さが足りないので少なくする。
    var maxVisibleRows = ComposerSuggestionPopupMetrics.maxVisibleRows
    let onAccept: (Int) -> Void

    /// 05 R3: 組込 / .claude/commands / .claude/skills / 実行時に受け取ったもの。
    static func originLabel(_ origin: SlashCommandOrigin) -> LocalizedStringKey {
        switch origin {
        case .builtin: "組込"
        case .commands: ".claude/commands"
        case .skills: ".claude/skills"
        case .runtime: "実行時に受け取ったもの"
        }
    }

    /// 05 R3: 見出し・候補行（30pt・選択はアクセント地に白）・下端のキー操作の案内（PhloxReply.dc.html の sug）。
    var body: some View {
        let isSlash = controller.candidates.first?.kind == .slashCommand
        VStack(alignment: .leading, spacing: 1) {
            Text(isSlash ? "コマンド" : "ファイル")
                .font(DSFont.meta.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .padding(EdgeInsets(top: 4, leading: 8, bottom: 6, trailing: 8))
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: controller.candidates.count > maxVisibleRows) {
                    LazyVStack(alignment: .leading, spacing: ComposerSuggestionPopupMetrics.rowSpacing) {
                        ForEach(Array(controller.candidates.enumerated()), id: \.element.id) { index, candidate in
                            row(candidate, isSelected: index == controller.selectedIndex) { onAccept(index) }
                                .onHover { hovering in
                                    if hovering {
                                        controller.select(index)
                                    }
                                }
                        }
                    }
                }
                // ↑↓ や絞り込みで選択行が見える範囲の外に出たら、その行まで送る。
                .onChange(of: selectedCandidateID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            .frame(maxHeight: ComposerSuggestionPopupMetrics.contentHeight(rows: maxVisibleRows))
            .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)
                .padding(.top, 4)
            HStack(spacing: 12) {
                Text("↑↓ 移動")
                Text("↩ / Tab 確定")
                Text("Esc 閉じる")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(DSColor.textTertiary)
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 2, trailing: 8))
        }
        .padding(6)
        .frame(maxWidth: 460, alignment: .leading)
        .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DSColor.popoverEdge, lineWidth: 0.5)
        )
        .dsShadow(.popover)
    }

    private var selectedCandidateID: SuggestionCandidate.ID? {
        controller.candidates.indices.contains(controller.selectedIndex) ? controller.candidates[controller.selectedIndex].id : nil
    }

    private func row(_ candidate: SuggestionCandidate, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let isSlash = candidate.kind == .slashCommand
        return Button(action: action) {
            HStack(spacing: 10) {
                Text(candidate.title)
                    .font(.system(size: 13, weight: isSlash ? .semibold : .medium, design: isSlash ? .default : .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // 説明から先に縮め、それでも入らない長い名前は途中を省く（右の出どころを押し出さない）。
                    .layoutPriority(1)
                Text(candidate.subtitle ?? "")
                    .font(DSFont.auxiliary)
                    .opacity(0.85)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let origin = candidate.origin {
                    Text(Self.originLabel(origin))
                        .font(.system(size: 10.5))
                        .opacity(0.75)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Color.white : DSColor.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: ComposerSuggestionPopupMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DSColor.accentFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum ComposerSuggestionPopupMetrics {
    static let maxVisibleRows = 8
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 1

    static func contentHeight(rows: Int) -> CGFloat {
        (rowHeight * CGFloat(rows)) + (rowSpacing * CGFloat(rows - 1))
    }
}

enum ComposerPlaceholderVisibility {
    static func shouldShowPlaceholder(text: String, isComposing: Bool) -> Bool {
        text.isEmpty && !isComposing
    }
}

struct IMESafeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var suggestionController: ComposerSuggestionController?
    let onSubmit: () -> Void
    var onPasteImage: ((Data, String) -> Bool)?
    var onPasteImageOutcome: ((Data, String) -> ComposerPasteImageOutcome)?
    /// 本文の `[Image #N]` をトークン単位で扱うための添付番号一覧（task-5）。
    var attachedImageNumbers: (() -> [Int])?
    /// 選択範囲に含まれる番号の画像（コピー時にクリップボードへ載せる。task-6）。
    var imagesForCopy: (([Int]) -> [(data: Data, mediaType: String)])?
    /// composer フォーカス時の esc 経路（task-9）。IME 変換中は呼ばれない。
    var onEscape: () -> Void = {}
    /// 入力欄がキーボードフォーカスを得たときに呼ぶ（tasks/task-5.md 契約。
    /// グリッドタイルの composer クリック→タイル選択に使う。受け入れテスト
    /// AcceptanceGridSelectionFocusTests が凍結。配線は task-5 が実装）。
    var onFocusGained: (() -> Void)? = nil
    /// composer へフォーカスを戻す要求（esc-restore-input-focus task-2 契約の PM スタブ）。
    /// 受け入れテスト AcceptanceComposerFocusRestoreTests が凍結（既定値ありのシグネチャは変更禁止）。
    /// トークンが変化したときだけ first responder とキャレットを動かす配線は task-2 が実装する。
    var focusRequest: ComposerFocusRequest = .none
    /// 入力欄でキーワード（ultrathink 等）を強調するか。Claude セッションのみ true を渡す。
    var highlightsKeywords: Bool = false
    /// 候補の無いときの Tab。true を返したら入力欄では処理しない（承認・質問カードへ移る。05 R6b）。
    var onTab: (() -> Bool)? = nil
    /// 候補の無いとき、先頭にいる ↑↓。true を返したら入力欄では処理しない（過去の入力を呼び戻した。05 R2）。
    var onRecallHistory: ((InputHistoryCursor.Direction) -> Bool)? = nil
    /// 候補の無いときの ⇧Tab。true を返したら入力欄では処理しない（推論の深さを次の段へ回した）。
    var onCycleEffort: (() -> Bool)? = nil
    /// 送信を受け付けてもらうまでは書けない（05 R4。失敗時に戻す本文と、その間に書いた本文がぶつからないように）。
    var isEditable = true
    /// 入力欄のフォーカスが変わったとき（入力欄の輪を出す。05 R2）。
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.identifier = NSUserInterfaceItemIdentifier("ChatComposer.input")

        let textView = SubmitAwareTextView()
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.onPasteImageOutcome = onPasteImageOutcome
        textView.attachedImageNumbers = attachedImageNumbers
        textView.imagesForCopy = imagesForCopy
        textView.onEscape = onEscape
        textView.onTab = onTab
        textView.onRecallHistory = onRecallHistory
        textView.onCycleEffort = onCycleEffort
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        textView.onFocusGained = onFocusGained
        textView.onFocusChange = onFocusChange
        textView.suggestionController = suggestionController
        textView.onComposingChanged = { [coordinator = context.coordinator] isComposing, currentText in
            coordinator.setComposing(isComposing, currentText: currentText)
        }
        textView.insertionPointColor = NSColor.labelColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = ComposerPlaceholderMetrics.textNSFont
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = ComposerPlaceholderMetrics.textInsets
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.highlightsKeywords = highlightsKeywords
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.applyComposerHighlights()

        // 初回描画でフォーカスを奪わない。以後は「この値から変化したとき」だけ移す。
        context.coordinator.lastHandledFocusToken = focusRequest.token

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.allowsUndo = true
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.onPasteImageOutcome = onPasteImageOutcome
        textView.attachedImageNumbers = attachedImageNumbers
        textView.imagesForCopy = imagesForCopy
        textView.onEscape = onEscape
        textView.onTab = onTab
        textView.onRecallHistory = onRecallHistory
        textView.onCycleEffort = onCycleEffort
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        textView.onFocusGained = onFocusGained
        textView.onFocusChange = onFocusChange
        textView.suggestionController = suggestionController
        textView.onComposingChanged = { [coordinator = context.coordinator] isComposing, currentText in
            coordinator.setComposing(isComposing, currentText: currentText)
        }
        // セッション種別の変化に追随させる（生成時だけ読むと切替後に色が変わらない）。
        if textView.highlightsKeywords != highlightsKeywords {
            textView.highlightsKeywords = highlightsKeywords
            textView.applyComposerHighlights()
        }
        if !textView.hasMarkedText(), textView.string != text {
            textView.syncStringFromBinding(text)
            suggestionController?.update(text: text, cursorUTF16: min(textView.selectedRange().location, text.utf16.count))
        }
        // フォーカス復帰要求（esc 2連打→履歴ピッカー→復元/キャンセル）。
        // 末尾化の対象となる復元本文は、この更新パスの直前の同期ブロックで既に textView へ入っている
        // （ChatSessionViewModel.confirmRevert が draft とフォーカス要求を同時に確定させるため）。
        // よって「本文の到着を待つ保留」は要らず、要求ごとにその場で完結する。
        //
        // 適用は Task で次の runloop へ回す。理由は2つ:
        //   (1) ピッカー ChatHistoryRevertPicker は .focused() で自らフォーカスを保持しており、この更新パスの
        //       時点では overlay がまだ responder chain に残りうる。
        //       実物の overlay をホストした closingRealPickerReturnsFocusToComposer で、この配線が無いと
        //       ピッカーを閉じてもフォーカスが composer へ戻らないことを実測済み。
        //   (2) ADR 0010: updateNSView は描画パスであり副作用の同期実行を避ける（既存の高さ再計算と同じ流儀）。
        if focusRequest.token != context.coordinator.lastHandledFocusToken {
            context.coordinator.lastHandledFocusToken = focusRequest.token
            let movesCaretToEnd = focusRequest.movesCaretToEnd
            Task { @MainActor [weak textView, coordinator = context.coordinator] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
                if movesCaretToEnd {
                    coordinator.moveCaretToEnd(of: textView)
                }
            }
        }
        // Bug A / ADR 0010: updateNSView は描画パスなので @State/@Binding を同期書込しない。
        // 差分ガード付き遅延書込は、実行時に再計算・再判定することで高々1回で固定点に収束する。
        if let nextHeight = context.coordinator.resolvedHeight(for: textView),
           ComposerHeightPolicy.shouldWrite(current: measuredHeight, next: nextHeight) {
            Task { @MainActor [weak textView, coordinator = context.coordinator] in
                guard let textView else { return }
                coordinator.recalculateHeight(for: textView)
            }
        }
        scrollView.hasVerticalScroller = measuredHeight >= maxHeight
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeTextView
        /// 直前に処理した `focusRequest.token`。再描画のたびにフォーカスを奪い返さないための冪等キー。
        /// `struct IMESafeTextView` や `@State` ではなく Coordinator（再描画をまたいで生存する参照型）に
        /// 持つ（値側に持つと毎回の再生成で初期値へ戻り、無関係な再描画でフォーカスを奪う）。
        var lastHandledFocusToken = ComposerFocusRequest.none.token

        init(_ parent: IMESafeTextView) {
            self.parent = parent
        }

        /// 本文末尾へキャレットを移す。IME 変換中は動かさない（変換途中の確定位置を壊さないため）。
        func moveCaretToEnd(of textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() {
                setComposing(true, currentText: textView.string)
                recalculateHeight(for: textView)
                return
            }
            parent.text = textView.string
            (textView as? SubmitAwareTextView)?.applyComposerHighlights()
            updateSuggestions(for: textView)
            recalculateHeight(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            updateSuggestions(for: textView)
        }

        /// 選択が `[Image #N]` を分断しないように寄せる（task-7）。
        ///
        /// 個々のコマンド（shift+←、shift+↑、⌘shift+←、マウスドラッグ…）を列挙して
        /// override すると覆うべき集合が閉じないため、**選択変更の1箇所**でこの不変条件を守る。
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
            toCharacterRange newSelectedCharRange: NSRange
        ) -> NSRange {
            guard !textView.hasMarkedText() else { return newSelectedCharRange }
            guard let numbers = (textView as? SubmitAwareTextView)?.attachedImageNumbers?(),
                  !numbers.isEmpty
            else { return newSelectedCharRange }

            let snapped = ComposerImagePlaceholder.snappedSelectionUTF16(
                from: oldSelectedCharRange.lowerBound..<oldSelectedCharRange.upperBound,
                to: newSelectedCharRange.lowerBound..<newSelectedCharRange.upperBound,
                in: textView.string,
                numbers: numbers
            )
            return NSRange(location: snapped.lowerBound, length: snapped.count)
        }

        func setComposing(_ isComposing: Bool, currentText: String) {
            if !isComposing, parent.text != currentText {
                parent.text = currentText
            }
            guard parent.isComposing != isComposing else { return }
            parent.isComposing = isComposing
        }

        func resolvedHeight(for textView: NSTextView) -> CGFloat? {
            guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else { return nil }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let insetHeight = textView.textContainerInset.height * 2
            return ComposerHeightPolicy.resolvedHeight(
                usedTextHeight: usedHeight,
                insetHeight: insetHeight,
                minHeight: parent.minHeight,
                maxHeight: parent.maxHeight
            )
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let nextHeight = resolvedHeight(for: textView) else { return }
            guard ComposerHeightPolicy.shouldWrite(current: parent.measuredHeight, next: nextHeight) else { return }
            parent.measuredHeight = nextHeight
        }

        private func updateSuggestions(for textView: NSTextView) {
            parent.suggestionController?.update(
                text: textView.string,
                cursorUTF16: textView.selectedRange().location
            )
        }
    }

    final class SubmitAwareTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onPasteImage: ((Data, String) -> Bool)?
        /// task-2 契約の PM スタブ。設定されていればこちらだけを呼び、結果に応じて
        /// カーソル位置へ `[Image #N]` を挿入する。nil なら従来の onPasteImage 経路。
        /// 受け入れテスト ComposerImageNumberingAcceptanceTests が凍結（シグネチャ変更禁止）。
        var onPasteImageOutcome: ((Data, String) -> ComposerPasteImageOutcome)?
        var onComposingChanged: ((Bool, String) -> Void)?
        var onEscape: (() -> Void)?
        var onTab: (() -> Bool)?
        var onRecallHistory: ((InputHistoryCursor.Direction) -> Bool)?
        var onCycleEffort: (() -> Bool)?
        var onFocusGained: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        var suggestionController: ComposerSuggestionController?
        /// 本文中のプレースホルダをトークン単位で扱うための、添付されている番号一覧。
        /// task-5 契約（受け入れテスト ComposerPlaceholderEditingAcceptanceTests が凍結）。
        var attachedImageNumbers: (() -> [Int])?
        /// 選択範囲に含まれる番号に対応する画像。コピー時にクリップボードへ載せる。
        /// task-6 契約（同上）。
        var imagesForCopy: (([Int]) -> [(data: Data, mediaType: String)])?
        /// キーワード強調（ultrathink 等）を有効にするか。Claude セッションのみ true。
        var highlightsKeywords: Bool = false

        override func becomeFirstResponder() -> Bool {
            let didBecomeFirstResponder = super.becomeFirstResponder()
            if didBecomeFirstResponder {
                onFocusGained?()
                onFocusChange?(true)
            }
            return didBecomeFirstResponder
        }

        override func resignFirstResponder() -> Bool {
            let didResign = super.resignFirstResponder()
            if didResign { onFocusChange?(false) }
            return didResign
        }

        // MARK: - トークン単位削除（task-5）

        override func deleteBackward(_ sender: Any?) {
            guard !deleteWholePlaceholder(direction: .backward) else { return }
            super.deleteBackward(sender)
        }

        override func deleteForward(_ sender: Any?) {
            guard !deleteWholePlaceholder(direction: .forward) else { return }
            super.deleteForward(sender)
        }

        /// カーソルがプレースホルダに掛かっていれば、トークンごとまとめて消す。
        /// 消したときだけ true（呼び出し元は通常の1文字削除を行わない）。
        @discardableResult
        func deleteWholePlaceholder(direction: ComposerImagePlaceholder.DeleteDirection) -> Bool {
            guard !hasMarkedText() else { return false }
            let selection = selectedRange()
            guard selection.length == 0 else { return false }
            guard let numbers = attachedImageNumbers?(), !numbers.isEmpty else { return false }
            guard let range = ComposerImagePlaceholder.deletionRangeUTF16(
                at: selection.location,
                in: string,
                numbers: numbers,
                direction: direction
            ) else { return false }

            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            guard shouldChangeText(in: nsRange, replacementString: "") else { return true }
            textStorage?.replaceCharacters(in: nsRange, with: "")
            setSelectedRange(NSRange(location: range.lowerBound, length: 0))
            didChangeText()
            applyComposerHighlights()
            return true
        }

        // MARK: - 画像もコピーする（task-6）

        override func copy(_ sender: Any?) {
            guard writeSelectionWithImages(to: .general) else {
                super.copy(sender)
                return
            }
        }

        override func cut(_ sender: Any?) {
            // ⌘X も ⌘C と同じくクリップボードへ画像を載せる（載せた後に選択範囲を消す）。
            guard writeSelectionWithImages(to: .general) else {
                super.cut(sender)
                return
            }
            let selection = selectedRange()
            guard shouldChangeText(in: selection, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: selection, with: "")
            setSelectedRange(NSRange(location: selection.location, length: 0))
            didChangeText()
            applyComposerHighlights()
        }

        /// 選択範囲にプレースホルダが含まれていれば、テキストと一緒に画像もクリップボードへ載せる。
        /// 載せたときだけ true（false なら呼び出し元が通常のコピーを行う）。
        @discardableResult
        func writeSelectionWithImages(to pasteboard: NSPasteboard) -> Bool {
            let selection = selectedRange()
            guard selection.length > 0, let numbers = attachedImageNumbers?(), !numbers.isEmpty else {
                return false
            }
            let selected = (string as NSString).substring(with: selection)
            let contained = numbers.filter { ComposerImagePlaceholder.contains(number: $0, in: selected) }
            guard !contained.isEmpty else { return false }
            let images = imagesForCopy?(contained) ?? []
            guard !images.isEmpty else { return false }

            // 1つ目の item にテキストと画像を両方載せる（貼り付け先が欲しい形を選べる）。
            // 2枚目以降は item を分ける（1つの item に同じ型は1つしか載らないため）。
            let encodable = images.compactMap { image -> (NSPasteboard.PasteboardType, Data)? in
                guard let type = Self.pasteboardType(forMediaType: image.mediaType) else { return nil }
                return (type, image.data)
            }
            // 1枚も載せられない形式なら通常のコピーに委ねる（テキストまで失わせない）。
            guard let firstImage = encodable.first else { return false }

            let first = NSPasteboardItem()
            first.setString(selected, forType: .string)
            first.setData(firstImage.1, forType: firstImage.0)
            var items: [NSPasteboardItem] = [first]
            for (type, data) in encodable.dropFirst() {
                let item = NSPasteboardItem()
                item.setData(data, forType: type)
                items.append(item)
            }

            pasteboard.clearContents()
            return pasteboard.writeObjects(items)
        }

        /// pasteboard が「この composer の添付を指すプレースホルダ入りテキスト」を持っているか。
        private func carriesOwnPlaceholderText(_ pasteboard: NSPasteboard) -> Bool {
            guard let numbers = attachedImageNumbers?(), !numbers.isEmpty,
                  let text = pasteboard.string(forType: .string)
            else { return false }
            return numbers.contains { ComposerImagePlaceholder.contains(number: $0, in: text) }
        }

        static func pasteboardType(forMediaType mediaType: String) -> NSPasteboard.PasteboardType? {
            switch mediaType {
            case "image/png": return NSPasteboard.PasteboardType("public.png")
            case "image/jpeg": return NSPasteboard.PasteboardType("public.jpeg")
            case "image/tiff": return NSPasteboard.PasteboardType("public.tiff")
            case "image/gif": return NSPasteboard.PasteboardType("com.compuserve.gif")
            case "image/webp": return NSPasteboard.PasteboardType("org.webmproject.webp")
            default: return nil
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48,
               event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               !hasMarkedText(),
               suggestionController?.isPresented != true,
               onTab?() == true {
                return
            }
            if event.keyCode == 48,
               event.modifierFlags.intersection([.command, .shift, .option, .control]) == .shift,
               !hasMarkedText(),
               suggestionController?.isPresented != true,
               onCycleEffort?() == true {
                return
            }
            if event.keyCode == 126 || event.keyCode == 125,
               event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               !hasMarkedText(),
               suggestionController?.isPresented != true,
               selectedRange() == NSRange(location: 0, length: 0),
               onRecallHistory?(event.keyCode == 126 ? .older : .newer) == true {
                return
            }
            switch ComposerKeyRouting.action(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isComposing: hasMarkedText(),
                suggestionsVisible: suggestionController?.isPresented == true
            ) {
            case .undo:
                undoManager?.undo()
            case .redo:
                undoManager?.redo()
            case .paste:
                paste(nil)
            case .submit:
                onSubmit?()
            case .insertNewline:
                insertNewline(nil)
            case .escape:
                onEscape?()
            case .moveSuggestionUp:
                suggestionController?.moveSelection(-1)
            case .moveSuggestionDown:
                suggestionController?.moveSelection(1)
            case .acceptSuggestion:
                if let replacement = suggestionController?.acceptSelected() {
                    applySuggestionReplacement(replacement)
                }
            case .dismissSuggestions:
                suggestionController?.dismiss()
            case .passToSystem:
                super.keyDown(with: event)
            }
        }

        func syncStringFromBinding(_ nextString: String) {
            guard string != nextString else { return }
            let currentSelection = selectedRange()
            let selectionLocation = min(currentSelection.location, nextString.utf16.count)
            let selectionLength = min(
                currentSelection.length,
                max(0, nextString.utf16.count - selectionLocation)
            )
            let manager = undoManager
            manager?.disableUndoRegistration()
            defer { manager?.enableUndoRegistration() }
            let attributedString = NSAttributedString(string: nextString, attributes: typingAttributes)
            if let textStorage {
                textStorage.setAttributedString(attributedString)
            } else {
                string = nextString
            }
            setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))
            applyComposerHighlights()
            breakUndoCoalescing()
        }

        func applyComposerHighlights() {
            guard !hasMarkedText(), let textStorage else { return }

            let currentSelection = selectedRange()
            let defaultForegroundColor =
                typingAttributes[.foregroundColor] as? NSColor
                ?? textColor
                ?? NSColor.labelColor
            let manager = undoManager
            manager?.disableUndoRegistration()
            defer {
                setSelectedRange(currentSelection)
                manager?.enableUndoRegistration()
            }

            textStorage.beginEditing()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            if fullRange.length > 0 {
                textStorage.addAttribute(
                    .foregroundColor,
                    value: defaultForegroundColor,
                    range: fullRange
                )
                textStorage.addAttribute(.font, value: ComposerPlaceholderMetrics.textNSFont, range: fullRange)
            }
            // スラッシュコマンド・@参照・キーワードを別色にして種別を判別できるようにする。
            for span in ComposerHighlight.spans(in: string, includingKeywords: highlightsKeywords) {
                let range = NSRange(location: span.range.lowerBound, length: span.range.count)
                guard NSMaxRange(range) <= textStorage.length else { continue }
                // 網羅 switch。case を足したら必ずここでコンパイルエラーになり、
                // 新種別が既存色へ黙って落ちる事故を防ぐ（default / _ を書かないこと）。
                // 色と書体は PhloxReply.dc.html の kHL（cmd / file / kw）。
                let color: NSColor
                let font: NSFont
                switch span.kind {
                case .slashCommand:
                    color = NSColor(DSColor.accentInk)
                    font = .systemFont(ofSize: 13.5, weight: .semibold)
                case .fileReference:
                    color = NSColor(DSColor.attentionInk(.question))
                    font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
                case .keyword:
                    color = NSColor(DSColor.composerKeyword)
                    font = .systemFont(ofSize: 13.5, weight: .semibold)
                }
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
                textStorage.addAttribute(.font, value: font, range: range)
            }
            textStorage.endEditing()

            var defaultTypingAttributes = typingAttributes
            defaultTypingAttributes[.foregroundColor] = defaultForegroundColor
            typingAttributes = defaultTypingAttributes
        }

        override func paste(_ sender: Any?) {
            if handlePaste(from: .general) {
                return
            }
            super.paste(sender)
        }

        // task-4 契約の PM スタブ。API 表面は受け入れテスト ChatFixTask4PasteAcceptanceTests が
        // 凍結している（シグネチャ変更禁止）。実装契約の正本: tasks/task-4.md
        // （paste(_:) の画像横取りロジックをこの検査可能な seam に移す。
        //   true = 画像として処理済み（テキストペースト抑止）/ false = 呼び出し側が通常ペースト）。
        func handlePaste(from pasteboard: NSPasteboard) -> Bool {
            // 自分でコピーした「テキスト＋画像」を貼り戻すときは、画像として横取りしない。
            // 横取りすると選択していた本文が丸ごと捨てられ、画像1枚だけが新規添付になる。
            if carriesOwnPlaceholderText(pasteboard) { return false }
            guard Self.shouldInterceptImagePaste(in: pasteboard),
                  let image = Self.imageData(from: pasteboard)
            else {
                return false
            }

            if let onPasteImageOutcome {
                switch onPasteImageOutcome(image.data, image.mediaType) {
                case .unsupported:
                    return false
                case .rejected:
                    return true
                case .attached(let number):
                    applyImagePlaceholderInsertion(number: number)
                    return true
                }
            }

            guard let onPasteImage else {
                return false
            }
            return onPasteImage(image.data, image.mediaType)
        }

        private func applyImagePlaceholderInsertion(number: Int) {
            if hasMarkedText() {
                unmarkText()
            }
            let applied = ComposerImagePlaceholder.inserting(
                number: number,
                into: string,
                cursorUTF16: selectedRange().location
            )
            guard applied.text != string else { return }
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            guard shouldChangeText(in: fullRange, replacementString: applied.text) else { return }
            string = applied.text
            setSelectedRange(NSRange(location: applied.cursorUTF16, length: 0))
            didChangeText()
            applyComposerHighlights()
        }

        private func applySuggestionReplacement(_ replacement: SuggestionReplacement) {
            let applied = ComposerSuggestionTextReplacement.apply(replacement, to: string)
            guard applied.text != string else { return }
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            guard shouldChangeText(in: fullRange, replacementString: applied.text) else { return }
            string = applied.text
            setSelectedRange(NSRange(location: applied.cursorUTF16, length: 0))
            didChangeText()
        }

        // IME の composing 状態は入力方式ごとに終了経路が異なる（候補確定で unmarkText を
        // 呼ぶ IME／insertText: だけで確定し didChangeText 経由になる IME 等）。取りこぼしを
        // 防ぐため setMarkedText/unmarkText/didChangeText の3経路すべてから composing 状態を
        // 再評価する（防御的な多重通知）。notifyComposingChanged → Coordinator.setComposing は
        // `hasMarkedText()` を単一の真実源とし、状態が変わらなければ binding を更新しない
        // べき等操作なので、多重呼び出しでも副作用はない。
        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            notifyComposingChanged()
        }

        override func unmarkText() {
            super.unmarkText()
            notifyComposingChanged()
        }

        override func didChangeText() {
            super.didChangeText()
            notifyComposingChanged()
        }

        private func notifyComposingChanged() {
            onComposingChanged?(hasMarkedText(), string)
        }

        private static func shouldInterceptImagePaste(in pasteboard: NSPasteboard) -> Bool {
            let availableTypes = Set((pasteboard.types ?? []).map(\.rawValue))
            return ComposerPastePolicy.shouldInterceptImagePaste(availableTypeIdentifiers: availableTypes)
        }

        private static func imageData(from pasteboard: NSPasteboard) -> (data: Data, mediaType: String)? {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) {
                return (data, "image/png")
            }
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
                return (data, "image/jpeg")
            }
            guard let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                return nil
            }
            return (png, "image/png")
        }
    }
}

struct ComposerAttachmentStrip: View {
    @Bindable var store: ComposerAttachmentStore
    let layout: ComposerSettingsLayout
    /// いまのモデルには送られない画像の知らせ。あれば画像を薄く出し、承認待ちの色の面で知らせる（05 R8 案 B）。
    var imageNotice: String? = nil
    let onRemove: (ComposerAttachment) -> Void

    private var chipHeight: CGFloat {
        layout == .compact ? 26 : 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(store.attachments) { attachment in
                            ComposerAttachmentChip(
                                attachment: attachment,
                                chipHeight: chipHeight,
                                onRemove: { onRemove(attachment) }
                            )
                            .opacity(imageNotice == nil ? 1 : 0.55)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .accessibilityIdentifier("ChatComposer.attachments")
            }
            // 知らせは本文色。面は上限などが淡い赤、送られない画像が承認待ちの色、置き換えは中立（PhloxReply.dc.html の notice）。
            if let lastError = store.lastError {
                notice(Text(LocalizedStringKey(lastError)), background: noticeBackground)
            } else if let imageNotice {
                notice(Text(verbatim: imageNotice), background: DSColor.attentionTint(.approval))
            }
        }
    }

    private func notice(_ text: Text, background: Color) -> some View {
        text
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(2)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityIdentifier("ChatComposer.attachmentError")
    }
}

extension ComposerAttachmentStrip {
    private var noticeBackground: Color {
        switch store.lastErrorTone {
        case .error: DSColor.attentionTint(.error)
        case .neutral: DSColor.fillSubtle
        }
    }
}

/// 添付の 1 枚（高さ 30・角丸 7・区切りの面、22pt の縮小画像・名前・大きさ・丸い ✕）。
/// ponytail: 本文の `[Image #N]` と対応させる「#N」はモックに無いが、どの画像か分かる手掛かりなので残す。
private struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let chipHeight: CGFloat
    let onRemove: () -> Void
    @State private var isHoveringRemove = false

    var body: some View {
        HStack(spacing: 6) {
            thumbnail
            Text(verbatim: ComposerAttachmentChipPresentation.badge(for: attachment))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)
                .accessibilityIdentifier("ChatComposer.attachmentBadge")
            Text(ComposerAttachmentChipPresentation.title(for: attachment))
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                .font(.system(size: 10.5))
                .foregroundStyle(DSColor.textTertiary)
                .fixedSize()
            Button(action: onRemove) {
                Text(verbatim: "✕")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(isHoveringRemove ? DSColor.fillSelected : DSColor.fillSubtle, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRemove = $0 }
            .help("削除")
            .accessibilityLabel(Text("添付を外す"))
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: 190)
        .frame(height: chipHeight)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(shape)
                .overlay(shape.strokeBorder(DSColor.separator, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            shape
                .fill(DSColor.fillSubtle)
                .frame(width: 22, height: 22)
                .overlay(shape.strokeBorder(DSColor.separator, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}
