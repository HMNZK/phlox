import SwiftUI
import AgentDomain
import DesignSystem

struct UsageTopBarView: View {
    let monitor: UsageMonitor
    /// チップ群が使ってよい横幅。ウィンドウ幅・サイドバー・右上コントロール群の実測から
    /// `TrailingTopBarLayout.usageAvailableWidth` で算出して渡す。これを超える表示はせず、
    /// ゲージ付き→直列テキスト→非表示の順に自動で縮退する。
    let availableWidth: CGFloat

    private static let gaugeWidth: CGFloat = 72

    private struct TopBarChip: Identifiable {
        let kind: AgentKind
        let allBuckets: [UsageBucket]
        let shownBuckets: [UsageBucket]
        let unavailableReason: String?
        let staleNote: String?

        var id: AgentKind { kind }

        var isUnavailable: Bool { unavailableReason != nil }
    }

    private var visibleKinds: [AgentKind] {
        UsageDisplay.visibleKinds(usages: monitor.usages, showUnavailable: false)
    }

    private var constrainedWidth: CGFloat {
        max(0, availableWidth.rounded(.down))
    }

    private var chips: [TopBarChip] {
        visibleKinds.compactMap { kind -> TopBarChip? in
            guard let usage = monitor.usages[kind] else { return nil }
            if kind == .claudeCode {
                switch usage.state {
                case .unavailable(let reason):
                    return TopBarChip(
                        kind: kind,
                        allBuckets: [],
                        shownBuckets: [],
                        unavailableReason: reason,
                        staleNote: nil
                    )
                case .ok(let buckets):
                    let shown = UsageDisplay.topBarBuckets(buckets)
                    guard !shown.isEmpty else { return nil }
                    return TopBarChip(
                        kind: kind,
                        allBuckets: buckets,
                        shownBuckets: shown,
                        unavailableReason: nil,
                        // 実データ表示中の「未取得」注記の矛盾を避ける（PM 裁定・task-16 レビュー LOW）
                        staleNote: usage.dataAsOf != nil
                            ? ClaudeUsageStaleness.note(now: Date(), dataAsOf: usage.dataAsOf)
                            : nil
                    )
                }
            }
            guard case .ok(let buckets) = usage.state else { return nil }
            let shown = UsageDisplay.topBarBuckets(buckets)
            guard !shown.isEmpty else { return nil }
            return TopBarChip(
                kind: kind,
                allBuckets: buckets,
                shownBuckets: shown,
                unavailableReason: nil,
                staleNote: nil
            )
        }
    }

    var body: some View {
        let chips = chips
        if !chips.isEmpty, constrainedWidth > 0 {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timedChips = chips.map { chip -> TopBarChip in
                    guard chip.kind == .claudeCode, !chip.isUnavailable,
                          let dataAsOf = monitor.usages[chip.kind]?.dataAsOf else { return chip }
                    let staleNote = ClaudeUsageStaleness.note(
                        now: context.date,
                        dataAsOf: dataAsOf
                    )
                    return TopBarChip(
                        kind: chip.kind,
                        allBuckets: chip.allBuckets,
                        shownBuckets: chip.shownBuckets,
                        unavailableReason: chip.unavailableReason,
                        staleNote: staleNote
                    )
                }
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
                    Text(chip.kind.displayName)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    if let reason = chip.unavailableReason {
                        Text(reason)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else if showsGauge {
                HStack(spacing: DSSpacing.xs) {
                    Text(chip.kind.displayName)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        ForEach(chip.shownBuckets) { bucket in
                            gaugeRow(kind: chip.kind, bucket: bucket, isPercentDimmed: chip.staleNote != nil)
                        }
                        if let staleNote = chip.staleNote {
                            Text(staleNote)
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                HStack(spacing: DSSpacing.xs) {
                    Text(chip.kind.displayName)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    ForEach(Array(chip.shownBuckets.enumerated()), id: \.element.id) { index, bucket in
                        if index > 0 {
                            Text("・")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                        shortLabelText(for: bucket)
                        percentText(for: bucket, isDimmed: chip.staleNote != nil)
                    }
                    if let staleNote = chip.staleNote {
                        Text(staleNote)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
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

    private func gaugeRow(kind: AgentKind, bucket: UsageBucket, isPercentDimmed: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            shortLabelText(for: bucket)
            gauge(kind: kind, bucket: bucket)
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
    private func gauge(kind: AgentKind, bucket: UsageBucket) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(DSColor.separator)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DSColor.agentColor(for: kind), DSColor.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
