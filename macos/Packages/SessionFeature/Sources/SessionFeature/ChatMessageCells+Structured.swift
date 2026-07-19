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
    var reasoningPreview: String? = nil
    var hangAssessment: ((Date) -> ChatHangAssessment?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    /// transcript 最下部が viewport 内にあるか。スクロール位置のイベントから親が渡す。
    var isInTranscriptViewport = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// 表示ライフサイクルのイベントでのみ更新する。アニメーション状態には使わない。
    @State private var isInViewHierarchy = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

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
        AvatarMessageRow(descriptor: descriptor, timestamp: .distantPast) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if reduceMotion {
                    HStack(spacing: DSSpacing.s) {
                        staticThinkingText(scale: scale)
                        StaticThinkingDots()
                    }
                } else {
                    TimelineView(ThinkingAnimationModel.timelineSchedule(isVisible: isTimelineVisible)) { context in
                        HStack(spacing: DSSpacing.s) {
                            shimmeringThinkingText(scale: scale, date: context.date)
                            StaticThinkingDots(date: context.date)
                        }
                    }
                }
                if let reasoningPreview {
                    Text(reasoningPreview)
                        .font(ChatScaledFont.caption(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .lineLimit(3)
                }
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

    private func staticThinkingText(scale: CGFloat) -> some View {
        Text("Thinking...")
            .font(ChatScaledFont.body(scale: scale).italic())
            .foregroundStyle(DSColor.chatTextSecondary)
    }

    private func shimmeringThinkingText(scale: CGFloat, date: Date) -> some View {
        let phase = ThinkingAnimationModel.shimmerPhase(date: date)
        let stops = (0...20).map { index in
            let position = Double(index) / 20
            let brightness = ThinkingAnimationModel.shimmerBrightness(
                position: position,
                phase: phase
            )
            return Gradient.Stop(
                color: DSColor.chatTextSecondary.opacity(brightness),
                location: CGFloat(position)
            )
        }

        return Text("Thinking...")
            .font(ChatScaledFont.body(scale: scale).italic())
            .foregroundStyle(
                LinearGradient(
                    stops: stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
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
        DisclosureCard(
            isExpanded: $isExpanded,
            title: "Reasoning",
            subtitle: nil,
            timestamp: timestamp,
            systemImage: "brain.head.profile",
            accent: DSColor.chatAccent,
            status: .complete
        ) {
            Text(text)
                .font(ChatScaledFont.body(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.top, DSSpacing.s)
        }
        .frame(maxWidth: 720, alignment: .leading)
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
            subtitle: output.isEmpty ? nil : "Output available",
            timestamp: timestamp,
            systemImage: "terminal",
            accent: isRunning ? DSColor.statusAwaitingApproval : DSColor.chatSuccess,
            status: isRunning ? .running : .complete
        ) {
            if !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output)
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .textSelection(.enabled)
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
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    private struct DiffSection: Identifiable {
        let id: Int
        let path: String
        let lines: [ClassifiedDiffLine]
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
    private var visibleSections: [DiffSection] {
        guard isTruncated else {
            return changes.enumerated().map { index, change in
                DiffSection(id: index, path: change.path, lines: ChatMessageRenderCache.diffLines(change.diff))
            }
        }
        var budget = FileChangeDisplayPolicy.visibleLineLimit
        return changes.enumerated().map { index, change in
            let lines = ChatMessageRenderCache.diffLines(change.diff)
            let take = max(0, min(lines.count, budget))
            budget -= take
            return DiffSection(id: index, path: change.path, lines: Array(lines.prefix(take)))
        }
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        DisclosureCard(
            isExpanded: expansionBinding,
            title: changes.count == 1 ? "File Change" : "\(changes.count) File Changes",
            subtitle: changes.first?.path,
            timestamp: timestamp,
            systemImage: "doc.badge.gearshape",
            accent: DSColor.chatSuccess,
            status: .complete
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                ForEach(visibleSections) { section in
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        Label(section.path, systemImage: "doc.text")
                            .font(ChatScaledFont.captionStrong(scale: scale))
                            .foregroundStyle(DSColor.chatTextPrimary)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(section.lines) { line in
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(ChatScaledFont.monoCaption(scale: scale))
                                    .foregroundStyle(foreground(for: line.kind))
                                    .padding(.horizontal, DSSpacing.s)
                                    .padding(.vertical, 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(background(for: line.kind))
                                    .textSelection(.enabled)
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

    private func foreground(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition:
            DSColor.diffAdded
        case .deletion:
            DSColor.diffRemoved
        case .hunk:
            DSColor.chatAccent
        case .fileHeader:
            DSColor.chatTextSecondary
        case .context:
            DSColor.chatTextPrimary
        }
    }

    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition:
            DSColor.diffAdded.opacity(0.12)
        case .deletion:
            DSColor.diffRemoved.opacity(0.12)
        case .hunk:
            DSColor.chatAccent.opacity(0.12)
        case .fileHeader, .context:
            .clear
        }
    }
}
