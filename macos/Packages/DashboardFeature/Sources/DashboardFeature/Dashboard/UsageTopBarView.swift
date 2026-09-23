import SwiftUI
import AgentDomain
import DesignSystem

struct UsageTopBarView: View {
    let monitor: UsageMonitor
    /// ツールバーの幅の段階。狭い段階ほど小さい表示から始める。どの段階でも収まらなければ
    /// ゲージ付き→直列テキスト→最小の残量 1 つの順に縮退する（01 D）。
    let density: ToolbarDensity

    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false

    private static let gaugeWidth: CGFloat = 72

    private typealias TopBarChip = UsageDisplay.TopBarChip

    private func agentBrandIcon(for kind: AgentKind) -> some View {
        AgentBrandIcon(kind: kind, size: UsageDisplay.topBarBrandIconSize)
    }

    private var chips: [TopBarChip] {
        // 実データ表示中の「未取得」注記の矛盾を避ける（PM 裁定・task-16 レビュー LOW）は
        // UsageDisplay.topBarChips 側で保持済み。
        UsageDisplay.topBarChips(usages: monitor.usages, showUnavailable: showUnavailable, now: Date())
    }

    var body: some View {
        if !chips.isEmpty {
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
                    if density == .full {
                        chipsRow(timedChips, showsGauge: true).fixedSize()
                    }
                    if density != .minimal {
                        chipsRow(timedChips, showsGauge: false).fixedSize()
                    }
                    minimumRemaining(timedChips).fixedSize()
                }
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

    /// 最も狭い段階。残りが最小の 1 つだけを出す。
    @ViewBuilder
    private func minimumRemaining(_ chips: [TopBarChip]) -> some View {
        if let percent = UsageDisplay.minimumRemainingPercent(chips) {
            let isLow = Double(percent) < UsageDisplay.lowRemainingThreshold
            Text(verbatim: isLow ? "▲ \(percent)%" : "\(percent)%")
                .font(DSFont.captionStrong)
                .monospacedDigit()
                .foregroundStyle(isLow ? DSColor.attentionInk(.approval) : DSColor.textSecondary)
        }
    }

    private func chipHelp(_ chip: TopBarChip) -> String {
        UsageDisplay.topBarHelpText(chip: chip, now: Date())
    }

    private func gaugeRow(bucket: UsageBucket, isPercentDimmed: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            shortLabelText(for: bucket)
            gauge(bucket: bucket)
            percentText(for: bucket, isDimmed: isPercentDimmed)
        }
    }

    private func shortLabelText(for bucket: UsageBucket) -> some View {
        // 5h はあと1時間以下、7d(週次)はあと1日以下でラベルを赤くする。毎分 now を更新して追従。
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
        Text(UsageDisplay.remainingPercentText(usedPercent: bucket.usedPercent))
            .font(DSFont.captionStrong)
            .foregroundStyle(
                isDimmed
                    ? DSColor.textTertiary
                    : Self.remainingColor(usedPercent: bucket.usedPercent)
            )
            .monospacedDigit()
    }

    /// 色は対応待ちの状態にだけ使うため、残量は無彩色で示し、残りわずかのときだけ琥珀色にする。
    private static func remainingColor(usedPercent: Double) -> Color {
        UsageDisplay.isLowRemaining(usedPercent: usedPercent) ? DSColor.attentionInk(.approval) : DSColor.textSecondary
    }

    /// サイドバーのバケット行と同じ「残量分だけ塗る」ミニゲージ。
    private func gauge(bucket: UsageBucket) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(DSColor.separator)
            Capsule(style: .continuous)
                .fill(Self.remainingColor(usedPercent: bucket.usedPercent))
                .frame(width: max(0, Self.gaugeWidth * (100 - bucket.usedPercent) / 100))
        }
        .frame(width: Self.gaugeWidth, height: 4)
        .animation(.easeOut(duration: 0.5), value: bucket.usedPercent)
    }
}

#Preview("Usage top bar — wide (gauge)") {
    UsageTopBarPreviewContainer(density: .full)
        .padding()
        .background(DSColor.background)
}

#Preview("Usage top bar — narrow (text only)") {
    UsageTopBarPreviewContainer(density: .compact)
        .padding()
        .background(DSColor.background)
}

@MainActor
private struct UsageTopBarPreviewContainer: View {
    @State private var monitor: UsageMonitor
    private let density: ToolbarDensity

    init(density: ToolbarDensity) {
        self.density = density
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
        UsageTopBarView(monitor: monitor, density: density)
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
