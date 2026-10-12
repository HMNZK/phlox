import SwiftUI
import AgentDomain
import DesignSystem

struct UsageBottomBarView: View {
    let monitor: UsageMonitor
    @Bindable var router: AppRouter

    @AppStorage(UsageSettings.showInHeaderKey) private var showUsage = true
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @ViewBuilder
    var body: some View {
        if showUsage {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let groups = UsageDisplay.bottomBarGroups(usages: monitor.usages)
                if !groups.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            router.showUsageInInspector()
                        }
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            row(groups, showsLabels: true, showsResets: true, now: context.date).fixedSize()
                            row(groups, showsLabels: true, showsResets: false, now: context.date).fixedSize()
                            row(groups, showsLabels: false, showsResets: false, now: context.date).fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 24)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(DSColor.toolbarBackground)
                    .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                    .help(Text("使用量の詳細を開く"))
                    .accessibilityLabel(Text(UsageDisplay.bottomBarAccessibilityLabel(
                        groups: groups, now: context.date, locale: locale, bundle: localizationBundle
                    )))
                }
            }
        }
    }

    private func row(_ groups: [UsageDisplay.BottomBarGroup], showsLabels: Bool, showsResets: Bool, now: Date) -> some View {
        HStack(spacing: 18) {
            ForEach(groups) { group in
                HStack(spacing: 7) {
                    AgentBrandIcon(kind: group.kind, size: 12)
                        .accessibilityHidden(true)
                    if let buckets = group.buckets {
                        HStack(spacing: 9) {
                            ForEach(buckets) { bucket in
                                bucketText(bucket, showsLabel: showsLabels, showsReset: showsResets, now: now)
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
