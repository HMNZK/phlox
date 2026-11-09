import SwiftUI
import AgentDomain
import DesignSystem

// エージェント状態カードの見出し（1 行目。見本 10-Anatomy「見出しの全状態」、要件 §4.2）。
// 組み立ての結果 `AgentStatusHeader`（時刻を持たない値）と、表示の時計・無応答の判定から描く。
// 時刻は `TimelineView(HangStatusTimelineSchedule)` の中だけで読む（NFR-1。新しいタイマーは足さない）。

/// 見出しの右に出す値（時刻から導く）。
enum AgentStatusHeaderTrailing: Equatable {
    case none
    /// 実行中・待機中の経過。
    case elapsed(TimeInterval)
    /// 無応答の長さ。
    case stalled(TimeInterval)
    /// 終わったカードの所要時間。
    case duration(TimeInterval)
}

extension AgentStatusHeader {
    /// 実行中の見出しが、今の無応答判定で「応答なし」かどうかまで含めた状態。
    /// 判定は時刻で変わるので、組み立ての結果ではなく表示の時計から決める。評価が無ければ組み立ての結果のまま。
    func resolvedState(assessment: ChatHangAssessment?) -> State {
        guard isLive, state != .awaitingReply, let assessment else { return state }
        return assessment.isStalled ? .stalled : .running
    }

    func trailing(now: Date, assessment: ChatHangAssessment?) -> AgentStatusHeaderTrailing {
        switch resolvedState(assessment: assessment) {
        case .running, .awaitingReply:
            return .elapsed(max(0, now.timeIntervalSince(startedAt)))
        case .stalled:
            return .stalled(assessment?.silence ?? silence ?? 0)
        case .completed, .interrupted, .error, .superseded, .ended:
            return endedAt.map { .duration(max(0, $0.timeIntervalSince(startedAt))) } ?? .none
        }
    }

    /// VoiceOver の 1 つのラベル（見本: 「実行中。api.swift を編集中。経過 13 秒」）。
    func spokenLabel(
        state resolved: State, trailing: AgentStatusHeaderTrailing, locale: Locale, bundle: Bundle = .main
    ) -> String {
        func word(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        func spoken(_ seconds: TimeInterval) -> String {
            AgentStatusDurationFormat.spoken(seconds, locale: locale, bundle: bundle)
        }
        var parts: [String]
        switch resolved {
        case .running: parts = [word("実行中"), title(locale: locale, bundle: bundle)]
        case .stalled: parts = [word("応答なし"), title(locale: locale, bundle: bundle)]
        default: parts = [title(locale: locale, bundle: bundle)]
        }
        switch trailing {
        case .none: break
        case .elapsed(let seconds): parts.append(String(format: word("経過 %@"), spoken(seconds)))
        case .stalled(let seconds): parts.append(String(format: word("無応答 %@"), spoken(seconds)))
        case .duration(let seconds): parts.append(String(format: word("所要 %@"), spoken(seconds)))
        }
        return AgentStatusSpeech.join(parts, locale: locale)
    }
}

enum AgentStatusSpeech {
    /// 日本語は「。」、それ以外は「. 」で区切って 1 つのラベルにする。
    static func join(_ parts: [String], locale: Locale) -> String {
        parts.joined(separator: locale.language.languageCode?.identifier == "ja" ? "。" : ". ")
    }
}

extension AgentStatusAction.Label {
    /// 作業の種類のアイコン（ADR 0227: カードの中に限って戻す）。
    var symbolName: String {
        switch self {
        case .read: "doc"
        case .search, .searches: "magnifyingglass"
        case .edit, .editFiles: "pencil"
        case .write: "square.and.pencil"
        case .run, .command: "terminal"
        case .tool: "wrench"
        case .subAgent: "arrow.triangle.branch"
        }
    }

    /// 行の中で濃い字にする部分（見本の `.f`。ファイル名）。
    var emphasis: String? {
        switch self {
        case .read(let file, _), .edit(let file), .write(let file): file
        default: nil
        }
    }

    /// 1 つのファイルだけを指す行のファイル名（読み上げで文言の代わりに読む）。
    var singleFile: String? {
        switch self {
        case .read(let file, 0), .edit(let file), .write(let file): file
        default: nil
        }
    }

    /// VoiceOver で先に読む種類の語（見本: 「編集。client.go。0.6 秒。展開できます」）。
    var spokenKindKey: String {
        switch self {
        case .read: "読み込み"
        case .search, .searches: "検索"
        case .edit, .editFiles: "編集"
        case .write: "書き込み"
        case .run, .command: "実行"
        case .tool: "ツール"
        case .subAgent: "サブエージェント"
        }
    }
}

struct AgentStatusHeaderView: View {
    let header: AgentStatusHeader
    let scale: CGFloat
    /// 点描を動かすか（見えていて、圧縮中・接続待ちでない）。
    let isAnimating: Bool
    /// 時計を進めるか（見えているか）。
    let isTimelineVisible: Bool
    /// グリッドの狭い列（左右の余白を詰める）。
    var isNarrow = false
    var hangAssessment: ((Date) -> ChatHangAssessment?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    var body: some View {
        if header.isLive {
            TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                row(now: context.date, assessment: hangAssessment?(context.date))
            }
        } else {
            row(now: header.endedAt ?? header.startedAt, assessment: nil)
        }
    }

    private func row(now: Date, assessment: ChatHangAssessment?) -> some View {
        let state = header.resolvedState(assessment: assessment)
        let trailing = header.trailing(now: now, assessment: assessment)
        return HStack(spacing: AgentStatusCardLayout.headerGap) {
            HStack(spacing: AgentStatusCardLayout.headerGap) {
                lead(state: state)
                nowText(state: state)
                trailingText(trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: header.spokenLabel(
                state: state, trailing: trailing, locale: locale, bundle: bundle
            )))
            .accessibilityIdentifier("AgentStatusCard.header")
            if state == .stalled, let onInterrupt {
                // 長い作業名に押されて「esc」が欠けないよう、右側を先に確保する。
                interruptButton(onInterrupt).fixedSize().layoutPriority(1)
            }
        }
        .padding(.leading, AgentStatusCardLayout.headerLeading(isNarrow: isNarrow))
        .padding(.trailing, AgentStatusCardLayout.headerTrailing(isNarrow: isNarrow))
        .frame(minHeight: AgentStatusCardLayout.headerHeight * scale)
    }

    // MARK: - 左の印

    @ViewBuilder
    private func lead(state: AgentStatusHeader.State) -> some View {
        switch state {
        case .running, .stalled, .awaitingReply:
            // 承認・質問待ちは点描を止めて薄くする（見本 `.dots.wait`）。
            ThinkingOrbView(
                state: header.orbState,
                size: .inline,
                isVisible: isAnimating && state != .awaitingReply
            )
            .opacity(state == .awaitingReply ? 0.5 : 1)
            .frame(width: AgentStatusCardLayout.leadSize, height: AgentStatusCardLayout.leadSize)
            .accessibilityHidden(true)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: AgentStatusCardLayout.leadSize, height: AgentStatusCardLayout.leadSize)
                .accessibilityHidden(true)
        case .interrupted, .superseded:
            AgentStatusStopMark(diameter: 15)
                .frame(width: AgentStatusCardLayout.leadSize, height: AgentStatusCardLayout.leadSize)
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12 * scale))
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: AgentStatusCardLayout.leadSize, height: AgentStatusCardLayout.leadSize)
                .accessibilityHidden(true)
        case .ended:
            // 終わり方の記録が無い。印も所要時間も出さない（要件 §4.2）。
            Color.clear.frame(width: AgentStatusCardLayout.leadSize, height: AgentStatusCardLayout.leadSize)
        }
    }

    // MARK: - 中央

    private func nowText(state: AgentStatusHeader.State) -> some View {
        let isQuiet = header.current == nil && state != .completed && state != .interrupted
            && state != .error && state != .superseded
        return HStack(spacing: 7) {
            if state == .running || state == .stalled, let current = header.current {
                Image(systemName: current.symbolName)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: header.title(locale: locale, bundle: bundle))
                // コマンドそのものを出すときは等幅（見本 06）。
                .font(isCommand ? .system(size: 12.5 * scale, weight: .medium, design: .monospaced) : .system(size: 13 * scale))
                .foregroundStyle(isQuiet ? DSColor.chatTextSecondary : DSColor.chatTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCommand: Bool {
        if case .command? = header.current { true } else { false }
    }

    // MARK: - 右

    @ViewBuilder
    private func trailingText(_ trailing: AgentStatusHeaderTrailing) -> some View {
        switch trailing {
        case .none:
            EmptyView()
        case .elapsed(let seconds), .duration(let seconds):
            Text(verbatim: AgentStatusDurationFormat.clock(seconds))
                .font(.system(size: 12 * scale))
                .monospacedDigit()
                .foregroundStyle(DSColor.chatTextSecondary)
                .fixedSize()
        case .stalled(let seconds):
            Text(verbatim: String(
                format: AppLocalizedString.string("無応答 %@", locale: locale, bundle: bundle),
                AgentStatusDurationFormat.clock(seconds)
            ))
            .font(.system(size: 12 * scale, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(DSColor.chatTextPrimary)
            .fixedSize()
            .accessibilityIdentifier("ChatHang.status")
        }
    }

    /// 無応答の間だけ出す「中断 esc」（見本 `.sbtn`）。
    private func interruptButton(_ onInterrupt: @escaping () async -> Void) -> some View {
        Button {
            Task { await onInterrupt() }
        } label: {
            HStack(spacing: 5) {
                Text("中断")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(DSColor.chatTextPrimary)
                Text(verbatim: "esc")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 17 * scale)
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                            .strokeBorder(DSColor.border, lineWidth: 1)
                    }
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .frame(minHeight: 24 * scale)
            .background(DSColor.chatBackground, in: RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("中断"))
        .accessibilityIdentifier("ChatHang.interruptButton")
    }
}

/// 中断の印（丸の中に小さい四角。見本 `.mstop`）。
struct AgentStatusStopMark: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(DSColor.textTertiary, lineWidth: 1.3)
            .frame(width: diameter, height: diameter)
            .overlay {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DSColor.textTertiary)
                    .frame(width: 5, height: 5)
            }
    }
}
