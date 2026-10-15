import SwiftUI
import AgentDomain
import DesignSystem

struct UsageBottomBarView: View {
    let monitor: UsageMonitor

    @AppStorage(UsageSettings.showInHeaderKey) private var showUsage = true
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false
    @AppStorage(UsageSettings.bottomBarStyleKey) private var style = UsageSettings.BottomBarStyle.bar
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @ViewBuilder
    var body: some View {
        if showUsage {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                let now = monitor.currentDate
                let groups = UsageDisplay.bottomBarGroups(usages: monitor.usages, showUnavailable: showUnavailable)
                if !groups.isEmpty {
                    GeometryReader { geometry in
                        row(groups, width: geometry.size.width, now: now)
                            .padding(.horizontal, DSSpacing.m)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: DSLayout.usageBarHeight)
                    .background(DSColor.toolbarBackground)
                    .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(UsageDisplay.bottomBarAccessibilityLabel(
                        groups: groups, now: now, locale: locale, bundle: localizationBundle,
                        staleKinds: monitor.failures[.claudeCode] == nil ? [] : [.claudeCode]
                    )))
                }
            }
        }
    }

    private func row(_ groups: [UsageDisplay.BottomBarGroup], width: CGFloat, now: Date) -> some View {
        let stage = UsageDisplay.bottomBarStage(forWidth: width)
        return HStack(spacing: 18) {
            ForEach(groups) { group in
                HStack(spacing: 7) {
                    AgentBrandIcon(kind: group.kind, size: 12)
                        .accessibilityHidden(true)
                    if let buckets = group.buckets {
                        HStack(spacing: 0) {
                            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                                if index > 0 {
                                    Text(verbatim: locale.language.languageCode?.identifier == "en" ? " · " : "・")
                                        .font(DSFont.meta)
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                                bucketText(
                                    bucket,
                                    showsLabel: stage != .percentageOnly,
                                    showsReset: stage == .full,
                                    barWidth: stage == .full ? 64 : 36,
                                    now: now
                                )
                            }
                        }
                        if group.kind == .claudeCode, let failure = monitor.failures[group.kind] {
                            Text(verbatim: UsageDisplay.previousValueText(locale: locale, bundle: localizationBundle))
                                .font(DSFont.meta)
                                .help(Text(verbatim: failure.reason + "\n" + (monitor.usages[group.kind]?.dataAsOf ?? failure.at).formatted(date: .numeric, time: .standard)))
                        }
                    } else {
                        Text(UsageDisplay.bottomBarUnavailableText(locale: locale, bundle: localizationBundle))
                            .font(DSFont.meta)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .foregroundStyle(DSColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bucketText(_ bucket: UsageBucket, showsLabel: Bool, showsReset: Bool, barWidth: CGFloat, now: Date) -> some View {
        let isLow = UsageDisplay.isLowRemaining(usedPercent: bucket.usedPercent)
        let font = DSFont.meta.weight(isLow ? .semibold : .regular)
        let color = isLow ? DSColor.attentionInk(.approval) : DSColor.textSecondary
        switch style {
        case .percent:
            Text(verbatim: UsageDisplay.bottomBarBucketText(
                bucket, showsLabel: showsLabel, showsReset: showsReset, now: now, locale: locale
            ))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
        case .bar:
            HStack(spacing: 5) {
                if showsLabel {
                    Text(verbatim: bucket.label).font(font).foregroundStyle(color)
                }
                DSMeterBar(
                    fraction: UsageDisplay.remainingPercent(usedPercent: bucket.usedPercent) / 100,
                    tint: isLow ? DSColor.attentionMark(.approval) : DSColor.textSecondary
                )
                .frame(width: barWidth)
                if showsReset, let reset = UsageDisplay.bottomBarResetSuffix(for: bucket, now: now, locale: locale) {
                    Text(verbatim: reset).font(font).monospacedDigit().foregroundStyle(color)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
