import SwiftUI
import AgentDomain
import ChatRenderKit
import DesignSystem
import StructuredChatKit

extension EnvironmentValues {
    /// 右パネルに開いているサブエージェント（会話の中のマーカーを選択表示にする）。
    @Entry var selectedSubAgentID: String? = nil
    /// 右パネルで開けるサブエージェント（nil は制限なし）。アプリを再起動すると一覧が戻らず中身を開けないので、その行は押せなくする。
    @Entry var openableSubAgentIDs: Set<String>? = nil
    /// 承認カードの「差分を見る」で開くファイルの変更（05 R6e）。token は同じ項目を何度でも開けるように。
    @Entry var fileChangeRevealRequest: FileChangeRevealRequest? = nil
}

struct FileChangeRevealRequest: Equatable {
    let itemID: String
    let token: Int
}

struct SubAgentMarkerCell: View {
    let id: String
    let subagentType: String
    let description: String
    let status: SubAgentStatus
    let onSelect: ((String) -> Void)?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
    @Environment(\.locale) private var locale
    @Environment(\.selectedSubAgentID) private var selectedSubAgentID
    @Environment(\.openableSubAgentIDs) private var openableSubAgentIDs
    @State private var isHovering = false

    private var selectAction: ((String) -> Void)? {
        openableSubAgentIDs?.contains(id) == false ? nil : onSelect
    }

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let _ = themeID
        Button {
            selectAction?(id)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(selectAction == nil)
        .help(selectAction == nil ? "" : "サブエージェントを表示")
        .accessibilityIdentifier("SubAgentMarkerCell")
    }

    /// PhloxChat.dc.html の子エージェント行: 「↳ 説明 種類 … 状態 ›」。角丸 8・1pt の枠。
    @ViewBuilder
    private var content: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack(spacing: 10) {
            Text(verbatim: "↳")
                .font(.system(size: 14 * scale))
                .foregroundStyle(DSColor.textTertiary)
                .accessibilityHidden(true)
            Text(description.isEmpty ? UIWording.text(.missingSubAgentDescription, languageCode: languageCode) : description)
                .font(.system(size: 13 * scale))
                .foregroundStyle(DSColor.chatTextPrimary)
                .lineLimit(1)
            Text(verbatim: subagentType)
                .font(.system(size: 11.5 * scale, design: .monospaced))
                .foregroundStyle(DSColor.chatTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            statusLabel
                .font(.system(size: 11 * scale, weight: status == .running ? .semibold : .regular))
                .foregroundStyle(statusColor)
            if selectAction != nil {
                Text(verbatim: "›")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background {
            // 選択中（右パネルに開いている）とホバーはホバー色の地。選択中は 2pt のアクセント枠。
            if isSelected || (isHovering && selectAction != nil) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DSColor.fillSubtle)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1)
        }
        .onHover { isHovering = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool { selectedSubAgentID == id }

    private var statusLabel: Text {
        switch status {
        case .running: Text("実行中")
        case .completed: Text("完了")
        case .failed: Text("失敗")
        }
    }

    /// 色は注意の状態（失敗＝エラー）だけ。
    private var statusColor: Color {
        switch status {
        case .running: DSColor.chatTextPrimary
        case .completed: DSColor.textTertiary
        case .failed: DSColor.attentionInk(.error)
        }
    }
}

struct ThinkingIndicatorCell: View {
    let descriptor: AgentDescriptor
    /// orb と状態語に出す活動状態。
    var state: AgentActivityState = .thinking
    var hangAssessment: ((Date) -> ChatHangAssessment?)? = nil
    /// 下段の「いま何をしているか」（04 A1・B1）。
    var recap: ((Date) -> ChatRecap.Summary?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    @State private var isInViewport = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    /// 表示ライフサイクルのイベントでのみ更新する。アニメーション状態には使わない。
    @State private var isInViewHierarchy = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(
        descriptor: AgentDescriptor,
        state: AgentActivityState = .thinking,
        hangAssessment: ((Date) -> ChatHangAssessment?)? = nil,
        recap: ((Date) -> ChatRecap.Summary?)? = nil,
        onInterrupt: (() async -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.state = state
        self.hangAssessment = hangAssessment
        self.recap = recap
        self.onInterrupt = onInterrupt
    }

    /// セルのライフサイクル、transcript の viewport、シーンがバックグラウンドではないことから導出する。
    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInViewport,
            scenePhase: scenePhase
        )
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow {
            if let hangAssessment {
                TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                    row(scale: scale, assessment: hangAssessment(context.date), recap: recap?(context.date))
                }
            } else {
                row(scale: scale, assessment: nil, recap: nil)
            }
        }
        .onAppear {
            isInViewHierarchy = true
        }
        .onDisappear {
            isInViewHierarchy = false
        }
        .onViewportVisibilityChange { isInViewport = $0 }
    }

    /// 無応答（04 B5）では行全体を紫の面と縁で囲み、経過と「中断」を右に出す。
    private func row(scale: CGFloat, assessment: ChatHangAssessment?, recap: ChatRecap.Summary?) -> some View {
        let isStalled = assessment?.isStalled ?? false
        let detail = Self.detailText(recap: recap, assessment: assessment)
        return HStack(spacing: DSSpacing.m) {
            ThinkingOrbView(state: state, size: .inline, isVisible: isTimelineVisible)
            VStack(alignment: .leading, spacing: 1) {
                // PhloxChat.dc.html の isThinking: 13pt 斜体・要約 11.5pt 弱い文字色。
                ShimmerTextView(
                    text: state.orbLabel(locale: locale),
                    font: .system(size: 13 * scale).italic(),
                    pointSize: 13 * scale,
                    // 帯の明度で不透明度を変調するため、基準色は本文色。下限（0.55）で
                    // ちょうど secondary 相当の濃さになり、帯の頂点で本文色まで濃くなる。
                    color: DSColor.chatTextPrimary,
                    isVisible: isTimelineVisible
                )
                if let detail {
                    detail
                        .font(.system(size: 11.5 * scale))
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("ChatHang.status")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(detail.map { Text("\(state.orbLabel(locale: locale))、\($0)") } ?? Text(verbatim: state.orbLabel(locale: locale)))
            Spacer(minLength: 0)
            if isStalled, let assessment {
                Text("無応答 \(Self.clockText(assessment.silence))")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.attentionInk(.stalled))
                if let onInterrupt {
                    Button {
                        Task { await onInterrupt() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("中断")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(DSColor.textPrimary)
                            Text(verbatim: "Esc")
                                .font(.system(size: 10.5 * scale))
                                .foregroundStyle(DSColor.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DSColor.controlBorder, lineWidth: 0.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("中断"))
                    .accessibilityIdentifier("ChatHang.interruptButton")
                }
            }
        }
        .padding(.vertical, isStalled ? 9 : TranscriptTypography.metadataGap)
        .padding(.horizontal, isStalled ? DSSpacing.m : 0)
        .background {
            if isStalled {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DSColor.attentionTint(.stalled))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DSColor.attentionMark(.stalled), lineWidth: 1)
            }
        }
    }

    /// 「swift build を実行中 · 38 秒」。要約が無ければ経過だけ。無応答の間は経過を右に出すので要約だけ。
    static func detailText(recap: ChatRecap.Summary?, assessment: ChatHangAssessment?) -> Text? {
        let recapText: Text? = recap.map { summary in
            switch summary {
            case .activity(.reading(let x)): Text("\(ThinkingRecap.clamp(x)) を読み込み中")
            case .activity(.running(let x)): Text("\(ThinkingRecap.clamp(x)) を実行中")
            case .activity(.editing(let x)): Text("\(ThinkingRecap.clamp(x)) を編集中")
            case .headline(let x): Text(verbatim: x)
            }
        }
        guard let assessment else { return recapText }
        if assessment.isStalled { return recapText }
        let elapsed = elapsedLabel(assessment.elapsed)
        guard let recapText else { return elapsed }
        return Text("\(recapText) · \(elapsed)")
    }

    private static func elapsedLabel(_ interval: TimeInterval) -> Text {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds < 60 { return Text("\(seconds) 秒") }
        return Text(verbatim: clockText(interval))
    }

    static func clockText(_ interval: TimeInterval) -> String { StallClock.text(interval) }
}

struct ReasoningSummaryView: View {
    let text: String
    let timestamp: Date
    @State private var userOverride: Bool?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.reasoning(
            text: text,
            summary: TranscriptMarkdownPresentation.summary(text)
        )
        if presentation.isVisible {
            TranscriptCard(
                isExpanded: Binding(
                    get: {
                        TranscriptItemPresentation.isExpanded(
                            userOverride: userOverride,
                            defaultExpanded: presentation.defaultExpanded
                        )
                    },
                    set: { userOverride = $0 }
                ),
                label: Text("思考"),
                summary: presentation.subtitle
            ) {
                AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)
                    .font(.system(size: 12.5 * scale))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .chatTextSelection()
                    .lineSpacing(6 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.top, 9)
                    .padding(.bottom, 10)
            }
        }
    }
}

typealias ReasoningPresentation = ChatReasoningPresentation

enum CommandGroupDisplayedRows {
    static func make(
        items: [ChatItem],
        lastTranscriptID: String?,
        isTurnRunning: Bool,
        limit: Int
    ) -> CommandGroupRowsSlice {
        CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning,
            limit: limit
        )
    }
}

/// FilePatchChange から共有の値型へ変換する macOS 側の薄いアダプタ。
enum FileChangePresentation {
    typealias Counts = ChatFileChangePresentation.Counts

    static func verb(for kind: String?) -> String {
        ChatFileChangePresentation.verb(for: kind)
    }

    static func counts(for changes: [FilePatchChange]) -> Counts {
        ChatFileChangePresentation.counts(for: changes.map {
            ChatFilePatch(path: $0.path, diff: $0.diff, kind: $0.kind)
        })
    }

    static func title(for changes: [FilePatchChange]) -> String {
        ChatFileChangePresentation.title(for: changes.map {
            ChatFilePatch(path: $0.path, diff: $0.diff, kind: $0.kind)
        })
    }
}

/// 単独のコマンド（04 A1 の「コマンド」カード）。見出しに「$ コマンド」、開くと出力の行。
struct CommandExecutionCell: View {
    let command: String?
    let output: String
    let timestamp: Date
    let isRunning: Bool
    @State private var userOverride: Bool?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let _ = themeID
        let presentation = TranscriptItemPresentation.command(
            path: .single,
            itemCount: 1,
            isRunning: isRunning,
            hasNonBlankOutput: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasFailed: (CommandExitCode.parse(output) ?? 0) != 0,
            runningSubtitle: "実行中",
            outputAvailableSubtitle: UIWording.text(.outputAvailable, languageCode: languageCode)
        )
        TranscriptCard(
            isExpanded: Binding(
                get: {
                    TranscriptItemPresentation.isExpanded(
                        userOverride: userOverride,
                        defaultExpanded: presentation.defaultExpanded
                    )
                },
                set: { userOverride = $0 }
            ),
            label: Text("コマンド"),
            summary: command?.isEmpty == false ? "$ \(command!)" : UIWording.text(.missingCommand, languageCode: languageCode),
            isRunning: isRunning,
            badges: isRunning
                ? [TranscriptCardBadge(id: "running", text: Text("実行中"), color: DSColor.chatTextPrimary, weight: .medium)]
                : [CommandExitCode.badge(for: output)].compactMap { $0 }
        ) {
            CommandCardOutput(output: output)
        }
    }
}

struct FileChangeCell: View {
    let changes: [FilePatchChange]
    let timestamp: Date
    var itemID: String? = nil
    @Environment(\.fileChangeRevealRequest) private var revealRequest
    /// ユーザーが明示トグルしたときだけ設定される override。nil の間は policy 由来の既定に追随する。
    @State private var userExpandedOverride: Bool?
    @State private var showAllLines = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
    @Environment(\.locale) private var locale

    struct DiffSection: Identifiable {
        let id: Int
        let path: String
        let copyText: String
        let codeView: DiffCodeViewData

    }

    /// 全 change の diff 総行数（メモ化済みの classify を使う）。
    private var totalLineCount: Int {
        changes.reduce(0) { $0 + ChatMessageRenderCache.diffLines($1.diff).count }
    }

    /// 展開状態を body で純導出（override 優先・未操作なら現在行数から既定）。読むだけで @Observable を書かない。
    /// diff が同一 id のまま置換され行数が変われば、未操作時は既定折りたたみが自動追随する。
    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { FileChangeDisplayPolicy.isExpanded(userOverride: userExpandedOverride, lineCount: totalLineCount) },
            // 書込はトグル操作（DisclosureGroup の action 文脈）でのみ発火し、body 評価中には起きない。
            set: { userExpandedOverride = $0 }
        )
    }

    /// 展開中でも一度に描画する行数が上限を超えるとき、「さらに表示」まで一部だけ描く。
    private var isTruncated: Bool {
        !showAllLines && totalLineCount > FileChangeDisplayPolicy.visibleLineLimit
    }

    /// 描画対象の各 change と行。非省略時は全行（＝従来と同一構造）、省略時は上限まで先頭を残す。
    var visibleSections: [DiffSection] {
        guard isTruncated else {
            return changes.enumerated().map { index, change in
                DiffSection(
                    id: index,
                    path: change.path,
                    copyText: change.diff,
                    codeView: ChatMessageRenderCache.diffCodeView(diff: change.diff, path: change.path)
                )
            }
        }
        var budget = FileChangeDisplayPolicy.visibleLineLimit
        return changes.enumerated().map { index, change in
            let codeView = ChatMessageRenderCache.diffCodeView(diff: change.diff, path: change.path)
            let take = max(0, min(codeView.sourceLineCount, budget))
            budget -= take
            return DiffSection(
                id: index,
                path: change.path,
                copyText: change.diff,
                codeView: codeView.prefix(sourceLineCount: take)
            )
        }
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let counts = FileChangePresentation.counts(for: changes)
        let verb = AppLocalizedString.string(FileChangePresentation.verb(for: changes.first?.kind), locale: locale)
        let summary = Self.summaryPath(for: changes, locale: locale)
        TranscriptCard(
            isExpanded: expansionBinding,
            label: Text(verbatim: verb),
            summary: summary,
            badges: [
                TranscriptCardBadge(id: "add", text: Text(verbatim: "+\(counts.additions)"), color: DSColor.diffAdded, monospaced: true),
                TranscriptCardBadge(id: "del", text: Text(verbatim: "\u{2212}\(counts.deletions)"), color: DSColor.diffRemoved, monospaced: true),
            ]
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleSections) { section in
                    if changes.count > 1 {
                        Text(verbatim: section.path)
                            .font(.system(size: 11 * scale, design: .monospaced))
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(section.codeView.lines) { codeLine in
                            diffLineView(codeLine, showsLineNumbers: section.codeView.hasLineNumbers, scale: scale)
                        }
                    }
                    .padding(.vertical, 4)
                }
                TranscriptCardFooter(
                    hiddenLineCount: isTruncated ? totalLineCount - FileChangeDisplayPolicy.visibleLineLimit : 0,
                    onShowMore: { showAllLines = true },
                    copyText: changes.map(\.diff).joined(separator: "\n")
                )
            }
            .help(Text("差分の行は選択できません — 「セクションをコピー」を使う"))
        }
        .onChange(of: revealRequest) { _, request in
            if let request, request.itemID == itemID { userExpandedOverride = true }
        }
    }

    /// 見出しの等幅のパス: 1 件は末尾 2 階層、複数は件数。
    static func summaryPath(for changes: [FilePatchChange], locale: Locale) -> String {
        guard changes.count == 1, let path = changes.first?.path else {
            return String(format: AppLocalizedString.string("%lld 件のファイル", locale: locale), changes.count)
        }
        return path.split(separator: "/").suffix(2).joined(separator: "/")
    }

    /// 1 行: 旧・新の行番号（各 30pt）→「+ 」「− 」→ 本文。追加・削除は淡い面。
    /// 行番号は hunk 見出しがある差分だけ（Claude の Write / Edit には無い）。無いときは番号の列ごと出さない。
    private func diffLineView(_ codeLine: DiffCodeLine, showsLineNumbers: Bool, scale: CGFloat) -> some View {
        let line = codeLine.line
        return HStack(spacing: 0) {
            if showsLineNumbers {
                lineNumber(line.kind == .addition ? nil : line.oldLineNumber, scale: scale)
                lineNumber(line.kind == .deletion ? nil : line.newLineNumber, scale: scale)
                    .padding(.trailing, 10)
            }
            Text(verbatim: marker(for: line.kind))
                .foregroundStyle(markerForeground(for: line.kind))
            Text(codeLine.body)
                .foregroundStyle(DSColor.chatTextPrimary)
        }
        .font(.system(size: 11.5 * scale, design: .monospaced))
        .lineLimit(1)
        .padding(.leading, showsLineNumbers ? 0 : 12)
        .padding(.trailing, 12)
        .frame(minHeight: 19 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle().fill(background(for: line.kind))
        }
        .diffLineTextSelection()
    }

    private func lineNumber(_ number: Int?, scale: CGFloat) -> some View {
        Text(verbatim: number.map(String.init) ?? "")
            .foregroundStyle(DSColor.textTertiary)
            .frame(width: 30 * scale, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private func marker(for kind: DiffLineKind) -> String {
        switch kind {
        case .addition: "+ "
        case .deletion: "\u{2212} "
        case .context: "  "
        case .fileHeader, .hunk: ""
        }
    }

    private func markerForeground(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: DSColor.diffAdded
        case .deletion: DSColor.diffRemoved
        case .hunk, .fileHeader, .context: DSColor.textTertiary
        }
    }

    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: DSColor.diffAddedTint
        case .deletion: DSColor.diffRemovedTint
        case .hunk, .fileHeader, .context: .clear
        }
    }
}
