import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

struct SubAgentMarkerCell: View {
    let id: String
    let subagentType: String
    let description: String
    let status: SubAgentStatus
    let onSelect: ((String) -> Void)?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        Button {
            onSelect?(id)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .help(onSelect == nil ? "" : "サブエージェントを表示")
        .accessibilityIdentifier("SubAgentMarkerCell")
    }

    @ViewBuilder
    private var content: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack(spacing: DSSpacing.s) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(description.isEmpty ? "Sub-agent" : description)
                    .font(ChatScaledFont.body(scale: scale))
                    .foregroundStyle(DSColor.chatTextPrimary)
                Text("\(subagentType) · \(status.rawValue)")
                    .font(ChatScaledFont.caption(scale: scale))
                    .foregroundStyle(DSColor.chatTextSecondary)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var statusIcon: some View {
        Group {
            switch status {
            case .running:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DSColor.chatSuccess)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DSColor.statusError)
            }
        }
    }
}

struct ThinkingIndicatorCell: View {
    let descriptor: AgentDescriptor
    /// orb と状態語に出す活動状態。
    var state: AgentActivityState = .thinking
    var hangAssessment: ((Date) -> ChatHangAssessment?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    /// transcript 最下部が viewport 内にあるか。スクロール位置のイベントから親が渡す。
    var isInTranscriptViewport = true
    @Environment(\.scenePhase) private var scenePhase
    /// 表示ライフサイクルのイベントでのみ更新する。アニメーション状態には使わない。
    @State private var isInViewHierarchy = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(
        descriptor: AgentDescriptor,
        state: AgentActivityState = .thinking,
        hangAssessment: ((Date) -> ChatHangAssessment?)? = nil,
        onInterrupt: (() async -> Void)? = nil,
        isInTranscriptViewport: Bool = true
    ) {
        self.descriptor = descriptor
        self.state = state
        self.hangAssessment = hangAssessment
        self.onInterrupt = onInterrupt
        self.isInTranscriptViewport = isInTranscriptViewport
    }

    /// セルのライフサイクル、transcript の viewport、シーンのアクティブ状態から導出する。
    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInTranscriptViewport,
            isSceneActive: scenePhase == .active
        )
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    ThinkingOrbView(state: state, size: .inline, isVisible: isTimelineVisible)
                    ShimmerTextView(
                        text: state.orbLabel,
                        font: ChatScaledFont.body(scale: scale),
                        pointSize: ChatScaledFont.bodyPointSize(scale: scale),
                        // 帯の明度で不透明度を変調するため、基準色は本文色。下限（0.55）で
                        // ちょうど secondary 相当の濃さになり、帯の頂点で本文色まで濃くなる。
                        color: DSColor.chatTextPrimary,
                        isVisible: isTimelineVisible
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.orbLabel)
                if let hangAssessment {
                    TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                        if let assessment = hangAssessment(context.date) {
                            RunningTurnStatusView(
                                assessment: assessment,
                                scale: scale,
                                onInterrupt: onInterrupt
                            )
                        }
                    }
                }
            }
            .padding(.vertical, DSSpacing.xs)
        }
        .onAppear {
            isInViewHierarchy = true
        }
        .onDisappear {
            isInViewHierarchy = false
        }
    }

}

private struct RunningTurnStatusView: View {
    let assessment: ChatHangAssessment
    let scale: CGFloat
    let onInterrupt: (() async -> Void)?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(Self.elapsedText(assessment.elapsed))
                .font(ChatScaledFont.caption(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)

            if assessment.isStalled {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DSColor.statusAwaitingApproval)
                    Text("応答がありません（\(Self.secondsText(assessment.silence)) 無応答）")
                        .font(ChatScaledFont.captionStrong(scale: scale))
                        .foregroundStyle(DSColor.chatTextPrimary)
                    if let onInterrupt {
                        Button("中断") {
                            Task { await onInterrupt() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("ChatHang.interruptButton")
                    }
                }
            }
        }
        .accessibilityIdentifier("ChatHang.status")
    }

    private static func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
    }

    private static func secondsText(_ interval: TimeInterval) -> String {
        "\(max(0, Int(interval.rounded(.down))))s"
    }
}

struct ReasoningSummaryView: View {
    let text: String
    let timestamp: Date
    @State private var isExpanded = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = ReasoningPresentation(text: text)
        Group {
            if presentation.usesDisclosure {
                DisclosureCard(
                    isExpanded: $isExpanded,
                    title: presentation.headline,
                    subtitle: nil,
                    isToolCall: true
                ) {
                    Text(text)
                        .font(ChatScaledFont.body(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .chatTextSelection()
                        .lineSpacing(3)
                        .padding(.top, DSSpacing.s)
                }
            } else {
                Text(presentation.trimmedText)
                    .font(ChatScaledFont.body(scale: scale))
                    .foregroundStyle(DSColor.chatToolCallText)
                    .chatTextSelection()
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

struct ReasoningPresentation: Equatable {
    let headline: String
    let trimmedText: String

    init(text: String) {
        trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        headline = ThinkingRecap.headline(from: text) ?? "Reasoning"
    }

    var usesDisclosure: Bool { trimmedText != headline }
}

enum FileChangePresentation {
    struct Counts: Equatable {
        let additions: Int
        let deletions: Int
    }

    static func verb(for kind: String?) -> String {
        let normalized = kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.contains("edit") { return "編集済み" }
        if normalized.contains("write") || normalized.contains("create") { return "作成済み" }
        if normalized.contains("delete") { return "削除済み" }
        return "変更済み"
    }

    static func counts(for changes: [FilePatchChange]) -> Counts {
        let lines = changes.flatMap { DiffLineClassifier.classify($0.diff) }
        return Counts(
            additions: lines.count { $0.kind == .addition },
            deletions: lines.count { $0.kind == .deletion }
        )
    }

    static func title(for changes: [FilePatchChange]) -> String {
        let verb = verb(for: changes.first?.kind)
        if changes.count == 1, let path = changes.first?.path {
            return "\(verb) \(filename(from: path))"
        }
        return "\(verb) \(changes.count) 件のファイル"
    }

    private static func filename(from path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
    }
}

struct CommandExecutionCell: View {
    let command: String?
    let output: String
    let timestamp: Date
    let isRunning: Bool
    @State private var isExpanded = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        DisclosureCard(
            isExpanded: $isExpanded,
            title: command?.isEmpty == false ? command! : "Command",
            subtitle: isRunning ? "実行中" : (output.isEmpty ? nil : "Output available"),
            isToolCall: true
        ) {
            if !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output)
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .chatTextSelection()
                        .padding(.leading, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, DSSpacing.s)
            }
        }
        .frame(maxWidth: 800, alignment: .leading)
    }
}

struct FileChangeCell: View {
    let changes: [FilePatchChange]
    let timestamp: Date
    /// ユーザーが明示トグルしたときだけ設定される override。nil の間は policy 由来の既定に追随する。
    @State private var userExpandedOverride: Bool?
    @State private var showAllLines = false
    @State private var isHovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    struct DiffSection: Identifiable {
        let id: Int
        let path: String
        let copyText: String
        let codeView: DiffCodeViewData

        var displayPath: String {
            DiffPathDisplay.shorten(path)
        }
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
        DisclosureCard(
            isExpanded: expansionBinding,
            subtitle: nil,
            titleContent: {
                HStack(spacing: DSSpacing.xxs) {
                    Text(FileChangePresentation.title(for: changes))
                    Text("+\(counts.additions)")
                        .foregroundStyle(DSColor.diffAdded)
                    Text("-\(counts.deletions)")
                        .foregroundStyle(DSColor.diffRemoved)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                ForEach(visibleSections) { section in
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        HStack(spacing: DSSpacing.s) {
                            Image(systemName: "doc.text")
                                .font(ChatScaledFont.captionStrong(scale: scale))
                                .foregroundStyle(DSColor.chatTextPrimary)
                            Text(section.displayPath)
                                .font(ChatScaledFont.captionStrong(scale: scale))
                                .foregroundStyle(DSColor.chatTextPrimary)
                                .help(section.path)
                            Spacer(minLength: DSSpacing.s)
                            // 省略表示中も画面上の prefix ではなく、元の file section 全文をコピーする。
                            MessageCopyButton(
                                text: section.copyText,
                                accessibilityIdentifier: "FileChange.copyDiff.\(section.id)",
                                scale: scale,
                                isVisible: isHovering
                            )
                        }
                        .onHover { isHovering = $0 }
                        .animation(.easeInOut(duration: 0.12), value: isHovering)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(section.codeView.lines) { codeLine in
                                diffLineView(codeLine, lineNumberWidth: section.codeView.lineNumberWidth, scale: scale)
                            }
                        }
                        .background(DSColor.chatBackground, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                    }
                }
                if isTruncated {
                    Button {
                        showAllLines = true
                    } label: {
                        Label(
                            "さらに \(totalLineCount - FileChangeDisplayPolicy.visibleLineLimit) 行を表示",
                            systemImage: "chevron.down"
                        )
                        .font(ChatScaledFont.captionStrong(scale: scale))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.chatAccent)
                    .padding(.top, DSSpacing.xs)
                    .accessibilityIdentifier("FileChange.showMoreButton")
                }
            }
            .padding(.top, DSSpacing.s)
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private func diffLineView(_ codeLine: DiffCodeLine, lineNumberWidth: Int, scale: CGFloat) -> some View {
        let line = codeLine.line
        return HStack(spacing: DSSpacing.s) {
            Text(line.displayLineNumber.map(String.init) ?? "")
                .font(ChatScaledFont.monoCaption(scale: scale))
                .foregroundStyle(lineNumberForeground(for: line.kind))
                .frame(width: CGFloat(lineNumberWidth) * 7 * scale, alignment: .trailing)
            Text(marker(for: line.kind))
                .font(ChatScaledFont.monoCaption(scale: scale))
                .foregroundStyle(markerForeground(for: line.kind))
                .frame(width: 8 * scale, alignment: .leading)
            if line.kind == .hunk {
                Text(line.text)
                    .font(ChatScaledFont.monoCaption(scale: scale))
                    .foregroundStyle(DSColor.chatTextSecondary)
            } else {
                Text(codeLine.body)
                    .font(ChatScaledFont.monoCaption(scale: scale))
            }
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle().fill(background(for: line.kind))
        }
        .diffLineTextSelection()
    }

    private func marker(for kind: DiffLineKind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        case .fileHeader, .hunk: ""
        }
    }

    private func markerForeground(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition:
            DSColor.diffAdded
        case .deletion:
            DSColor.diffRemoved
        case .hunk:
            DSColor.chatTextSecondary
        case .fileHeader:
            DSColor.chatTextSecondary
        case .context:
            DSColor.chatTextPrimary
        }
    }

    private func lineNumberForeground(for kind: DiffLineKind) -> Color {
        markerForeground(for: kind)
    }

    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition:
            DSColor.diffAdded.opacity(0.12)
        case .deletion:
            DSColor.diffRemoved.opacity(0.12)
        case .hunk:
            .clear
        case .fileHeader, .context:
            .clear
        }
    }
}
