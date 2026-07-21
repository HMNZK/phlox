import SwiftUI
import AgentDomain
import DesignSystem

struct UsageTopBarView: View {
    let monitor: UsageMonitor
    /// チップ群が使ってよい横幅。ウィンドウ幅・サイドバー・右上コントロール群の実測から
    /// `TrailingTopBarLayout.usageAvailableWidth` で算出して渡す。これを超える表示はせず、
    /// ゲージ付き→直列テキスト→非表示の順に自動で縮退する。
    let availableWidth: CGFloat

    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false

    private static let gaugeWidth: CGFloat = 72

    private typealias TopBarChip = UsageDisplay.TopBarChip

    private func agentBrandIcon(for kind: AgentKind) -> some View {
        AgentBrandIcon(kind: kind, size: UsageDisplay.topBarBrandIconSize)
    }

    private var constrainedWidth: CGFloat {
        max(0, availableWidth.rounded(.down))
    }

    private var chips: [TopBarChip] {
        // 実データ表示中の「未取得」注記の矛盾を避ける（PM 裁定・task-16 レビュー LOW）は
        // UsageDisplay.topBarChips 側で保持済み。
        UsageDisplay.topBarChips(usages: monitor.usages, showUnavailable: showUnavailable, now: Date())
    }

    var body: some View {
        if !chips.isEmpty, constrainedWidth > 0 {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // staleNote は now に依存する唯一の要素。毎分 context.date で純関数を呼び直し、
                // 表示専用ロジックの重複（View 側での再計算）を作らない（PM 裁定・レビュー MEDIUM）。
                let timedChips = UsageDisplay.topBarChips(
                    usages: monitor.usages,
                    showUnavailable: showUnavailable,
                    now: context.date
                )
                ViewThatFits(in: .horizontal) {
                    // fixedSize が無いと内部 Text が折り返しで「収まった」と報告し、
                    // 次段への縮退が発動せず縦潰れ表示になる（フェーズ4目視で検出）。
                    chipsRow(timedChips, showsGauge: true).fixedSize()
                    chipsRow(timedChips, showsGauge: false).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
                .frame(width: constrainedWidth, alignment: .trailing)
            }
        }
    }

    private func chipsRow(_ chips: [TopBarChip], showsGauge: Bool) -> some View {
        HStack(spacing: DSSpacing.s) {
            ForEach(chips) { chip in
                usageChip(chip: chip, showsGauge: showsGauge)
            }
        }
    }

    private func usageChip(chip: TopBarChip, showsGauge: Bool) -> some View {
        Group {
            if chip.isUnavailable {
                HStack(spacing: DSSpacing.xs) {
                    agentBrandIcon(for: chip.kind)
                    if let reason = chip.unavailableReason {
                        Text(reason)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else if showsGauge {
                HStack(spacing: DSSpacing.xs) {
                    agentBrandIcon(for: chip.kind)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        ForEach(chip.shownBuckets) { bucket in
                            gaugeRow(bucket: bucket, isPercentDimmed: chip.staleNote != nil)
                        }
                    }
                }
            } else {
                HStack(spacing: DSSpacing.xs) {
                    agentBrandIcon(for: chip.kind)
                    ForEach(Array(chip.shownBuckets.enumerated()), id: \.element.id) { index, bucket in
                        if index > 0 {
                            Text("・")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                        shortLabelText(for: bucket)
                        percentText(for: bucket, isDimmed: chip.staleNote != nil)
                    }
                }
            }
        }
        .help(chipHelp(chip))
    }

    private func chipHelp(_ chip: TopBarChip) -> String {
        if let reason = chip.unavailableReason {
            return reason
        }
        var lines = chip.allBuckets.map { bucket in
            "\(bucket.label) 残り\(Int(round(100 - bucket.usedPercent)))%"
        }
        if let staleNote = chip.staleNote {
            lines.append(staleNote)
        }
        return lines.joined(separator: "\n")
    }

    private func gaugeRow(bucket: UsageBucket, isPercentDimmed: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            shortLabelText(for: bucket)
            gauge(bucket: bucket)
            percentText(for: bucket, isDimmed: isPercentDimmed)
        }
    }

    private func shortLabelText(for bucket: UsageBucket) -> some View {
        // 5h は残り1時間以下、7d(週次)は残り1日以下でラベルを赤くする。毎分 now を更新して追従。
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(UsageDisplay.topBarShortLabel(for: bucket))
                .font(DSFont.caption)
                .foregroundStyle(
                    UsageDisplay.isResetUrgent(for: bucket, now: context.date)
                        ? UsageDisplay.urgentResetColor
                        : DSColor.textTertiary
                )
        }
    }

    private func percentText(for bucket: UsageBucket, isDimmed: Bool = false) -> some View {
        Text("\(Int(round(100 - bucket.usedPercent)))%")
            .font(DSFont.captionStrong)
            .foregroundStyle(
                isDimmed
                    ? DSColor.textTertiary
                    : UsageDisplay.usageColor(for: bucket.usedPercent)
            )
            .monospacedDigit()
    }

    /// サイドバーのバケット行と同じ「残量分だけ塗る」ミニゲージ。
    private func gauge(bucket: UsageBucket) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(DSColor.separator)
            Capsule(style: .continuous)
                .fill(UsageDisplay.usageColor(for: bucket.usedPercent))
                .frame(width: max(0, Self.gaugeWidth * (100 - bucket.usedPercent) / 100))
        }
        .frame(width: Self.gaugeWidth, height: 4)
        .animation(.easeOut(duration: 0.5), value: bucket.usedPercent)
    }
}

#Preview("Usage top bar — wide (gauge)") {
    UsageTopBarPreviewContainer(availableWidth: 800)
        .padding()
        .background(DSColor.background)
}

#Preview("Usage top bar — narrow (text only)") {
    UsageTopBarPreviewContainer(availableWidth: 420)
        .padding()
        .background(DSColor.background)
}

@MainActor
private struct UsageTopBarPreviewContainer: View {
    @State private var monitor: UsageMonitor
    private let availableWidth: CGFloat

    init(availableWidth: CGFloat) {
        self.availableWidth = availableWidth
        _monitor = State(initialValue: UsageMonitor(providers: [
            .codex: TopBarPreviewUsageProvider(usage: CLIUsage(
                kind: .codex,
                state: .ok([
                    UsageBucket(id: "5h", label: "5時間", usedPercent: 99),
                    UsageBucket(id: "weekly", label: "週次", usedPercent: 34),
                ]),
                updatedAt: .now
            )),
            .claudeCode: TopBarPreviewUsageProvider(usage: CLIUsage(
                kind: .claudeCode,
                state: .ok([UsageBucket(id: "weekly", label: "週次", usedPercent: 41)]),
                updatedAt: .now
            )),
            .cursor: TopBarPreviewUsageProvider(usage: CLIUsage(
                kind: .cursor,
                state: .unavailable(reason: "未取得"),
                updatedAt: .now
            )),
        ]))
    }

    var body: some View {
        UsageTopBarView(monitor: monitor, availableWidth: availableWidth)
            .task { await monitor.refresh() }
    }
}

private struct TopBarPreviewUsageProvider: UsageProvider {
    let usage: CLIUsage
    var kind: AgentKind { usage.kind }

    func fetch() async -> CLIUsage {
        usage
    }
}
