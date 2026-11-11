import SwiftUI
import StructuredChatKit
import DesignSystem

// エージェント状態カードのタスクの行（見本 10-Anatomy「タスクの行」、要件 §4.3）。
// 開閉は `AgentStatusCardDisclosure` が決める。作業の行は開いたときだけ作る。

/// 行頭の印の種類（印はすべて文字と同じ半透明グレー。ADR 0227）。
enum AgentStatusTaskMarkKind: Equatable {
    case done
    case todo
    case stopped
    case unknown
    case failed
    case running
}

extension AgentStatusRow {
    var markKind: AgentStatusTaskMarkKind {
        switch self {
        case .outside(let group):
            switch group.state {
            case .running: .running
            case .completed: .done
            case .interrupted: .stopped
            case .failed: .failed
            case .unknown: .unknown
            }
        case .task(let task):
            switch task.state {
            case .pending: .todo
            case .inProgress: .running
            case .completed: .done
            case .interrupted: .stopped
            }
        }
    }

    /// 行の名前。タスク外の作業は件数つき（見本: 「タスク外の作業 · 2 件」）。
    func title(locale: Locale, bundle: Bundle = .main) -> String {
        switch self {
        case .task(let task):
            return task.title
        case .outside(let group):
            let count = group.totalActionCount ?? group.entries.filter { if case .action = $0 { true } else { false } }.count
            return String(
                format: AppLocalizedString.string("タスク外の作業 · %lld 件", locale: locale, bundle: bundle), count
            )
        }
    }

    func spokenLabel(
        isExpanded: Bool, locale: Locale, bundle: Bundle = .main
    ) -> String {
        func word(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        var parts: [String] = []
        var finishedDuration: TimeInterval?
        switch self {
        case .outside(let group):
            switch group.state {
            case .running: parts.append(word("進行中"))
            case .completed: parts.append(word("完了"))
            case .interrupted:
                parts.append(AgentStatusText.keyed("statusCard.interrupted", japanese: "中断", locale: locale, bundle: bundle))
            case .failed: parts.append(word("失敗"))
            case .unknown:
                parts.append(AgentStatusText.keyed("statusCard.unknown", japanese: "記録なし", locale: locale, bundle: bundle))
            }
        case .task(let task):
            switch task.state {
            case .pending: parts.append(word("未着手"))
            case .inProgress: parts.append(word("進行中"))
            case .completed: parts.append(word("完了"))
            case .interrupted:
                parts.append(AgentStatusText.keyed("statusCard.interrupted", japanese: "中断", locale: locale, bundle: bundle))
            }
            if task.state != .inProgress, let start = task.startedAt, let end = task.endedAt {
                finishedDuration = end.timeIntervalSince(start)
            }
        }
        parts.append(title(locale: locale, bundle: bundle))
        if let finishedDuration {
            parts.append(AgentStatusDurationFormat.spoken(finishedDuration, locale: locale, bundle: bundle))
        }
        if isExpandable {
            parts.append(word(isExpanded ? "展開済み" : "折りたたみ済み"))
        }
        return AgentStatusSpeech.join(parts, locale: locale)
    }
}

struct AgentStatusTaskRow: View {
    let row: AgentStatusRow
    /// 縦の線は最後の行にはつながない。
    let isLast: Bool
    let isExpanded: Bool
    /// 手で開いた行は、見出しの行に薄い面を付ける。
    var isManuallyOpened = false
    let entryLimit: Int
    let scale: CGFloat
    let isNarrow: Bool
    /// 進行中の小さい点描を動かすか。グリッドの狭い列では止める（動くものを増やさない）。
    let isAnimating: Bool
    /// 進行中のタスクの所要時間を数えるか（見えているか）。
    let isTimelineVisible: Bool
    /// 最初から開いている作業の行（画面外の描画用）。
    var openActionIDs: Set<String> = []
    let makeItemView: (ChatItem) -> ChatItemView
    let onToggle: () -> Void
    let onShowMore: () -> Void
    var runtime: RuntimeStatusCardPresentation? = nil
    var actionDisclosure: Binding<AgentStatusCardDisclosure>? = nil
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if row.isTextOnly {
                // 作業の無い行は見出しを付けず、文章だけを元の位置に出す（開閉しない）。
                entries
            } else {
                header
                if isExpanded, row.isExpandable {
                    entries
                }
            }
        }
        // 印の中心を 1pt の線でつなぐ。開いた作業の行の横も通す（見本「縦の線」）。
        .overlay(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(DSColor.border)
                    .frame(width: 1)
                    .padding(.leading, AgentStatusCardLayout.connectorX)
                    .padding(.top, row.isTextOnly ? 0 : AgentStatusCardLayout.connectorTop)
                    .padding(.bottom, -AgentStatusCardLayout.connectorOverlap)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("AgentStatusCard.row.\(row.id)")
    }

    // MARK: - 行

    @ViewBuilder
    private var header: some View {
        if row.isExpandable {
            Button(action: onToggle) { headerContent }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: row.spokenLabel(isExpanded: isExpanded, locale: locale, bundle: bundle)))
        } else {
            headerContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: row.spokenLabel(isExpanded: false, locale: locale, bundle: bundle)))
        }
    }

    private var headerContent: some View {
        HStack(spacing: AgentStatusCardLayout.taskColumnGap) {
            chevron
            mark
            Text(verbatim: row.title(locale: locale, bundle: bundle))
                .font(.system(size: 13 * scale))
                .foregroundStyle(titleColor)
                .strikethrough(row.markKind == .done, color: DSColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            duration
        }
        .padding(.horizontal, 2)
        .frame(minHeight: AgentStatusCardLayout.taskRowHeight * scale)
        .background(
            isManuallyOpened && isExpanded ? DSColor.fillSubtle : Color.clear,
            in: RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var titleColor: Color {
        switch row.markKind {
        case .done, .todo: DSColor.textTertiary
        case .unknown: DSColor.chatTextSecondary
        case .stopped, .running, .failed: DSColor.chatTextPrimary
        }
    }

    @ViewBuilder
    private var chevron: some View {
        Group {
            if row.isExpandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .frame(width: AgentStatusCardLayout.chevronSize, height: AgentStatusCardLayout.chevronSize)
    }

    private var mark: some View {
        Group {
            switch row.markKind {
            case .done:
                Circle()
                    .strokeBorder(DSColor.textTertiary, lineWidth: 1.3)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(DSColor.textTertiary)
                    }
            case .todo:
                Circle().strokeBorder(DSColor.border, lineWidth: 1.3).frame(width: 12, height: 12)
            case .stopped:
                AgentStatusStopMark(diameter: 14)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(DSColor.textTertiary)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(DSFont.row)
                    .foregroundStyle(DSColor.textTertiary)
            case .running:
                // 見出しと同じ点描を小さくして使う（新しい描画は足さない）。
                ThinkingOrbView(state: .thinking, size: .inline, isVisible: isAnimating)
                    .frame(width: 20, height: 20)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: AgentStatusCardLayout.markSize, height: AgentStatusCardLayout.markSize)
        // 縦の線を印の後ろで切る。
        .background(DSColor.chatCard)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var duration: some View {
        if case .task(let task) = row {
            switch task.state {
            case .inProgress:
                if let start = task.startedAt {
                    // 進行中は数え続ける。時計は見えているときだけ進める（NFR-1）。
                    TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                        durationText(context.date.timeIntervalSince(start))
                    }
                }
            case .completed, .interrupted:
                if let start = task.startedAt, let end = task.endedAt {
                    durationText(end.timeIntervalSince(start))
                }
            case .pending:
                EmptyView()
            }
        }
    }

    private func durationText(_ seconds: TimeInterval) -> some View {
        Text(verbatim: AgentStatusDurationFormat.clock(seconds))
            .font(.system(size: 11.5 * scale))
            .monospacedDigit()
            .foregroundStyle(DSColor.textTertiary)
            .padding(.leading, 10)
    }

    // MARK: - 開いた中身

    @ViewBuilder
    private var entries: some View {
        if let runtime {
            RuntimeCardEntriesView(presentation: runtime, rowID: row.id,
                scale: scale, isTimelineVisible: isTimelineVisible, actionDisclosure: actionDisclosure)
                .padding(.leading, AgentStatusCardLayout.actionIndent(isNarrow: isNarrow))
                .padding(.vertical, 4)
        } else {
            localEntries
        }
    }

    private var localEntries: some View {
        let window = AgentStatusCardDisclosure.window(row.entries, limit: entryLimit)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(window.visible) { entry in
                switch entry {
                case .action(let action):
                    AgentStatusActionRow(
                        action: action, scale: scale, isTimelineVisible: isTimelineVisible,
                        startsOpen: openActionIDs.contains(action.id)
                    )
                case .item(let item):
                    AgentStatusItemEntry(item: item, scale: scale, makeItemView: makeItemView)
                }
            }
            if window.hidden > 0 {
                Button(action: onShowMore) {
                    Text(verbatim: String(
                        format: AppLocalizedString.string("さらに表示（古い作業 %lld 件）", locale: locale, bundle: bundle),
                        window.hidden
                    ))
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.leading, AgentStatusCardLayout.textIndent)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("AgentStatusCard.showMore")
            }
        }
        .padding(.leading, AgentStatusCardLayout.actionIndent(isNarrow: isNarrow))
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

/// 作業の行の間に並ぶ、文章・思考・そのほかの item（回答済みの質問・エラーなど）。
struct AgentStatusItemEntry: View {
    let item: ChatItem
    let scale: CGFloat
    let makeItemView: (ChatItem) -> ChatItemView
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    var body: some View {
        switch item {
        case .agentMessage(_, let text, _):
            // 途中の文章はタスクの下に、作業と並べて小さめの文字で出す（見本 `.wt`）。
            AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)
                .font(.system(size: 12.5 * scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .padding(.leading, AgentStatusCardLayout.textIndent)
                .padding(.trailing, 4)
                .padding(.vertical, 3)
        case .reasoning(_, let text, _):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: reasoningLine(text))
                    .font(.system(size: 12.5 * scale).italic())
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, AgentStatusCardLayout.textIndent)
                    .padding(.trailing, 4)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            makeItemView(item)
                .equatable()
                .padding(.leading, 4)
                .padding(.vertical, 3)
        }
    }

    /// 「思考 · 見出し」。見出しが取れなければ「思考」だけ。
    private func reasoningLine(_ text: String) -> String {
        let label = AppLocalizedString.string("思考", locale: locale, bundle: bundle)
        guard let headline = TranscriptMarkdownPresentation.summary(text), !headline.isEmpty else { return label }
        return "\(label) · \(headline)"
    }
}
