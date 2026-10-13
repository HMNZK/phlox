import SwiftUI
import AgentDomain
import DesignSystem

struct UsageBottomBarView: View {
    let monitor: UsageMonitor

    @AppStorage(UsageSettings.showInHeaderKey) private var showUsage = true
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @ViewBuilder
    var body: some View {
        if showUsage {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let groups = UsageDisplay.bottomBarGroups(usages: monitor.usages, showUnavailable: showUnavailable)
                if !groups.isEmpty {
                    GeometryReader { geometry in
                        row(groups, width: geometry.size.width, now: context.date)
                            .padding(.horizontal, DSSpacing.m)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: DSLayout.usageBarHeight)
                    .background(DSColor.toolbarBackground)
                    .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(UsageDisplay.bottomBarAccessibilityLabel(
                        groups: groups, now: context.date, locale: locale, bundle: localizationBundle
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
                                    now: now
                                )
                            }
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

    private func bucketText(_ bucket: UsageBucket, showsLabel: Bool, showsReset: Bool, now: Date) -> some View {
        let text = UsageDisplay.bottomBarBucketText(
            bucket, showsLabel: showsLabel, showsReset: showsReset, now: now, locale: locale
        )
        let isLow = UsageDisplay.isLowRemaining(usedPercent: bucket.usedPercent)
        return Text(verbatim: text)
            .font(DSFont.meta.weight(isLow ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isLow ? DSColor.attentionInk(.approval) : DSColor.textSecondary)
            .accessibilityHidden(true)
    }
}
