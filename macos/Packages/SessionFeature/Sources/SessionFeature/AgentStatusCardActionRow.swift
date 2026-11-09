import SwiftUI
import StructuredChatKit
import DesignSystem

// エージェント状態カードの作業の行（見本 10-Anatomy「作業の行」、要件 §4.4）。
// 1 行は「種類のアイコン・何をしたか・所要時間」。開くと今のツールカードの中身（差分・コマンド出力）を出す（FR-13）。
// サブエージェントは開けない（FR-14）。作業の行にスピナーは出さない（ADR 0227）。実行中は薄い文字と「〜中」で表す。

extension AgentStatusAction {
    /// 開けるか。サブエージェントは中身を見せない。
    var isExpandable: Bool {
        if case .subAgent = label { return false }
        return true
    }

    func spokenLabel(now: Date? = nil, locale: Locale, bundle: Bundle = .main) -> String {
        let subject = (isRunning ? nil : label.singleFile) ?? text(locale: locale, bundle: bundle)
        var parts = [AppLocalizedString.string(label.spokenKindKey, locale: locale, bundle: bundle), subject]
        if let duration = now.flatMap({ elapsed(at: $0) }) ?? duration {
            parts.append(AgentStatusDurationFormat.spoken(duration, locale: locale, bundle: bundle, fractional: true))
        }
        if isExpandable { parts.append(AppLocalizedString.string("展開できます", locale: locale, bundle: bundle)) }
        return AgentStatusSpeech.join(parts, locale: locale)
    }
}

struct AgentStatusActionRow: View {
    let action: AgentStatusAction
    let scale: CGFloat
    let isTimelineVisible: Bool
    @State private var isOpen: Bool
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    init(action: AgentStatusAction, scale: CGFloat, isTimelineVisible: Bool, startsOpen: Bool = false) {
        self.action = action
        self.scale = scale
        self.isTimelineVisible = isTimelineVisible
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if action.isRunning, action.startedAt != nil {
                TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                    header(now: context.date)
                }
            } else {
                header(now: nil)
            }
            if isOpen, action.isExpandable {
                detail
            }
        }
        .accessibilityIdentifier("AgentStatusCard.action.\(action.id)")
    }

    @ViewBuilder
    private func header(now: Date?) -> some View {
        if action.isExpandable {
            Button { isOpen.toggle() } label: { rowContent(now: now) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: action.spokenLabel(now: now, locale: locale, bundle: bundle)))
                .accessibilityValue(Text(AppLocalizedString.string(isOpen ? "展開中" : "折りたたみ中", locale: locale, bundle: bundle)))
        } else {
            rowContent(now: now)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: action.spokenLabel(now: now, locale: locale, bundle: bundle)))
        }
    }

    private func rowContent(now: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.label.symbolName)
                .font(.system(size: 12 * scale))
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: AgentStatusCardLayout.actionIconSize)
                .accessibilityHidden(true)
            label
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = now.flatMap({ action.elapsed(at: $0) }) ?? action.duration {
                Text(verbatim: AgentStatusDurationFormat.action(duration))
                    .font(.system(size: 11.5 * scale))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: AgentStatusCardLayout.actionRowHeight * scale)
        .background(isOpen ? DSColor.fillSubtle : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
    }

    private var font: Font {
        if case .command = action.label { return .system(size: 12 * scale, design: .monospaced) }
        return .system(size: 12.5 * scale)
    }

    /// 実行中は全体を薄く。終わった行はファイル名だけ濃く、残りは中くらい（見本 `.wr` `.f`）。
    private var label: Text {
        let text = action.text(locale: locale, bundle: bundle)
        let body = DSColor.chatTextSecondary
        if action.isRunning { return Text(verbatim: text).foregroundStyle(DSColor.textTertiary) }
        if case .subAgent(_, let type, let status) = action.label {
            return Text(verbatim: text).foregroundStyle(body)
                + Text(verbatim: " · \(type) · \(statusText(status))").foregroundStyle(DSColor.textTertiary)
        }
        guard let emphasis = action.label.emphasis, let range = text.range(of: emphasis) else {
            return Text(verbatim: text).foregroundStyle(body)
        }
        return Text(verbatim: String(text[..<range.lowerBound])).foregroundStyle(body)
            + Text(verbatim: emphasis).foregroundStyle(DSColor.chatTextPrimary)
            + Text(verbatim: String(text[range.upperBound...])).foregroundStyle(body)
    }

    private func statusText(_ status: SubAgentStatus) -> String {
        switch status {
        case .running: AppLocalizedString.string("実行中", locale: locale, bundle: bundle)
        case .completed: AppLocalizedString.string("完了", locale: locale, bundle: bundle)
        case .failed: AppLocalizedString.string("失敗", locale: locale, bundle: bundle)
        case .stopped: AgentStatusText.keyed("subagent.status.stopped", japanese: "停止", locale: locale, bundle: bundle)
        }
    }

    /// 開いた中身。今のセルの部品を再利用する（コマンドの出力・ファイルの差分）。
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(action.items) { item in
                switch item {
                case .commandExecution(_, let command, let output, _, _, _):
                    AgentStatusCommandDetail(command: command, output: output, scale: scale)
                case .fileChange(let id, let changes, let timestamp, _):
                    FileChangeCell(changes: changes, timestamp: timestamp, itemID: id, startsExpanded: true)
                default:
                    EmptyView()
                }
            }
        }
        .padding(.leading, AgentStatusCardLayout.textIndent)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

/// コマンドを開いた中身: 「$ コマンド」と終了コード、その下に出力（見本 `.wd`）。
private struct AgentStatusCommandDetail: View {
    let command: String?
    let output: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: "$ \(command ?? "")")
                    .font(.system(size: 11.5 * scale, design: .monospaced))
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = CommandExitCode.badge(for: output) {
                    badge.text
                        .font(.system(size: 11 * scale, weight: badge.weight))
                        .foregroundStyle(badge.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Rectangle().fill(DSColor.separator).frame(height: 1)
                CommandCardOutput(output: output)
            }
        }
        .background(DSColor.chatBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
    }
}
