import SwiftUI
import ChatRenderKit
import DesignSystem
import DesignSystemIOS
import PhloxCore

struct MobileAgentStatusCard<MessageContent: View, ActionContent: View>: View {
    let card: MobileStatusTranscript.Card
    let messages: [ChatMessage]
    let onInterrupt: () -> Void
    @ViewBuilder let messageContent: (ChatMessage) -> MessageContent
    @ViewBuilder let actionContent: (ChatMessage) -> ActionContent
    @State private var disclosure = MobileStatusCardDisclosure()
    @State private var rowLimit = 30
    @State private var entryLimits: [String: Int] = [:]
    @State private var openActions: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLive: Bool { [.running, .stalled, .awaitingReply].contains(card.state) }

    var body: some View {
        DSChatCodeCard(isRunning: isLive, showsDivider: !card.rows.isEmpty) {
            TimelineView(.animation(minimumInterval: 1, paused: !isLive)) { context in
                header(now: context.date)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(card.rows.suffix(rowLimit)), id: \.id) { row in
                    taskRow(row)
                }
                if card.rows.count > rowLimit {
                    moreButton(count: card.rows.count - rowLimit) { rowLimit += 30 }
                }
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
        }
        .accessibilityIdentifier("AgentStatusCard.\(card.id)")
    }

    private func header(now: Date) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: DSSpacing.s))
        return layout {
            HStack(spacing: DSSpacing.s) {
                if isLive {
                    ThinkingOrbView(state: card.activityState, isVisible: card.state != .awaitingReply)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: cardSymbol).foregroundStyle(IOSColor.text.tertiary)
                        .accessibilityHidden(true)
                }
                Text(card.title).font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if card.state != .ended {
                Text(card.state == .stalled
                     ? "無応答 \(ChatDurationFormat.clock(card.silence ?? 0))"
                     : ChatDurationFormat.clock((card.endedAt ?? (isLive ? now : card.startedAt)).timeIntervalSince(card.startedAt)))
                    .font(DSFont.iosCaption2).monospacedDigit()
                    .foregroundStyle(IOSColor.text.secondary)
            }
            if card.state == .stalled {
                Button("中断", action: onInterrupt)
                    .font(DSFont.subheadline)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .buttonStyle(DSPressFeedbackStyle())
                    .accessibilityIdentifier("AgentStatusCard.interrupt")
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private var cardSymbol: String {
        switch card.state {
        case .completed: "checkmark"
        case .error: "exclamationmark.triangle"
        case .ended: "minus"
        default: "stop.circle"
        }
    }

    @ViewBuilder private func taskRow(_ row: MobileStatusTranscript.Row) -> some View {
        let textOnly = MobileStatusCardDisclosure.isTextOnly(row)
        let expanded = disclosure.isExpanded(row)
        VStack(alignment: .leading, spacing: 0) {
            if !textOnly {
                TimelineView(.animation(minimumInterval: 1, paused: row.state != .inProgress && row.state != .running)) { context in
                    if row.entries.isEmpty {
                        taskHeader(row, expanded: expanded, now: context.date)
                    } else {
                        Button { disclosure.toggle(row) } label: {
                            taskHeader(row, expanded: expanded, now: context.date)
                        }
                        .buttonStyle(DSPressFeedbackStyle())
                        .accessibilityValue(expanded ? "展開中" : "折りたたみ中")
                    }
                }
            }
            if textOnly || expanded {
                let limit = entryLimits[row.id] ?? 30
                ForEach(Array(row.entries.suffix(limit).enumerated()), id: \.offset) { _, entry in
                    switch entry {
                    case .message(let id):
                        if let message = messages.first(where: { $0.id == id }) { messageContent(message) }
                    case .action(let action):
                        actionRow(action)
                    }
                }
                if row.entries.count > limit {
                    moreButton(count: row.entries.count - limit) { entryLimits[row.id] = limit + 30 }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !textOnly, row.id != card.rows.last?.id {
                Rectangle().fill(IOSColor.bg.separator).frame(width: 1)
                    .padding(.leading, 24).padding(.top, DSTouch.minSize)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .padding(.leading, textOnly ? 0 : DSSpacing.s)
        .accessibilityIdentifier("AgentStatusCard.row.\(row.id)")
    }

    private func taskHeader(_ row: MobileStatusTranscript.Row, expanded: Bool, now: Date) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .opacity(row.entries.isEmpty ? 0 : 1)
                .font(DSFont.iosCaption2)
                .accessibilityHidden(true)
            Group {
                if row.state == .inProgress || row.state == .running {
                    ThinkingOrbView(state: .thinking).scaleEffect(0.7)
                } else {
                    Text(rowSymbol(row.state))
                }
            }
            .frame(width: 20)
            .foregroundStyle(IOSColor.text.tertiary)
            .accessibilityHidden(true)
            Text(row.title)
                .strikethrough(row.state == .completed)
                .foregroundStyle(row.state == .completed || row.state == .pending ? IOSColor.text.tertiary : IOSColor.text.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let start = row.startedAt,
               let end = row.endedAt ?? ((row.state == .inProgress || row.state == .running) ? now : nil) {
                Text(ChatDurationFormat.clock(end.timeIntervalSince(start)))
                    .font(DSFont.iosCaption2).monospacedDigit().foregroundStyle(IOSColor.text.tertiary)
            }
        }
        .font(DSFont.subheadline)
        .frame(minHeight: DSTouch.minSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowState(row.state))、\(row.title)")
    }

    private func actionRow(_ action: MobileStatusTranscript.Action) -> some View {
        let items = action.messageIDs.compactMap { id in messages.first { $0.id == id } }
        let allowsDisclosure = items.contains { if case .subAgent = $0 { return false }; return true }
        let expanded = openActions.contains(action.id)
        return VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1, paused: action.state != .running)) { context in
                let duration = action.duration ?? action.startedAt.map { context.date.timeIntervalSince($0) }
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: action.symbolName).foregroundStyle(IOSColor.text.tertiary).accessibilityHidden(true)
                    SessionDetailTranscriptCardHeader(
                        label: rowSymbol(.init(rawValue: action.state.rawValue) ?? .unknown), summary: action.title,
                        badges: [.init(id: "state", text: rowState(.init(rawValue: action.state.rawValue) ?? .unknown), color: IOSColor.text.tertiary)]
                            + (duration.map { [.init(id: "duration", text: ChatDurationFormat.action($0), color: IOSColor.text.tertiary, monospaced: true)] } ?? []),
                        isExpanded: expanded, allowsDisclosure: allowsDisclosure,
                        onToggle: { if expanded { openActions.remove(action.id) } else { openActions.insert(action.id) } }
                    )
                    .accessibilityHint("AgentStatusCard.actionToggle.\(action.id)")
                }
            }
            DSDisclosureContent(isExpanded: expanded && allowsDisclosure) {
                ForEach(items) { message in actionContent(message) }
            }
        }
        .padding(.leading, DSSpacing.s)
        .accessibilityIdentifier("AgentStatusCard.action.\(action.id)")
    }

    private func moreButton(count: Int, action: @escaping () -> Void) -> some View {
        Button("さらに表示（古い作業 \(count) 件）", action: action)
            .font(DSFont.iosCaption2).foregroundStyle(IOSColor.text.secondary)
            .frame(minHeight: DSTouch.minSize).buttonStyle(DSPressFeedbackStyle())
    }

    private func rowSymbol(_ state: MobileStatusTranscript.RowState) -> String {
        switch state {
        case .completed: "✓"
        case .pending: "○"
        case .running, .inProgress: "◌"
        case .interrupted: "◼︎"
        case .failed: "⚠︎"
        case .unknown: "?"
        }
    }

    private func rowState(_ state: MobileStatusTranscript.RowState) -> String {
        switch state {
        case .pending: "未着手"
        case .running, .inProgress: "進行中"
        case .completed: "完了"
        case .interrupted: "中断"
        case .failed: "失敗"
        case .unknown: "記録なし"
        }
    }
}
