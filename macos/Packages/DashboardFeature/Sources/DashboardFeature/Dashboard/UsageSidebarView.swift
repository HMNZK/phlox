import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

public struct UsageSidebarView: View {
    @Bindable var monitor: UsageMonitor
    var chatSession: ChatSessionViewModel?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false

    public init(monitor: UsageMonitor, chatSession: ChatSessionViewModel? = nil) {
        _monitor = Bindable(wrappedValue: monitor)
        self.chatSession = chatSession
    }

    private var visibleKinds: [AgentKind] {
        UsageDisplay.visibleKinds(usages: monitor.usages, showUnavailable: showUnavailable)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    if let chatSession {
                        SessionInfoPanel(
                            startedAt: chatSession.startedAt,
                            sessionTotalCostUSD: chatSession.sessionTotalCostUSD,
                            workspacePath: chatSession.workspacePath,
                            workspaceName: chatSession.workspaceName
                        )
                    }
                    if visibleKinds.isEmpty {
                        Text("表示できる使用量がありません")
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, DSSpacing.l)
                    } else {
                        ForEach(visibleKinds) { kind in
                            if let usage = monitor.usages[kind] {
                                UsageCLICard(usage: usage)
                            } else {
                                UsageCLICard(
                                    usage: CLIUsage(
                                        kind: kind,
                                        state: .unavailable(reason: String(localized: "未取得")),
                                        updatedAt: .distantPast
                                    )
                                )
                            }
                        }
                    }
                }
                .padding(DSSpacing.m)
            }

            footer
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(DSColor.surface)
        }
        .padding(.top, 28)
    }

    private var footer: some View {
        HStack(spacing: DSSpacing.s) {
            if let refreshedAt = monitor.lastRefreshedAt {
                Text("更新: \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            } else {
                Text("未更新")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }

            Spacer(minLength: 0)

            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: DSIconSize.l, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .disabled(monitor.isRefreshing)
            .help("使用量を更新")
        }
    }
}

struct UsageCLICard: View {
    let usage: CLIUsage
    @Environment(\.openURL) private var openURL
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentBrandIcon(kind: usage.kind, size: DSIconSize.l)

            switch usage.state {
            case .ok(let buckets):
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    // 実データ（.ok）表示中に「未取得」注記が重なる矛盾を避けるため、
                    // 鮮度判定は dataAsOf が判る場合のみ行う（PM 裁定・task-16 レビュー LOW）。
                    let staleNote = (usage.kind == .claudeCode && usage.dataAsOf != nil)
                        ? ClaudeUsageStaleness.note(now: context.date, dataAsOf: usage.dataAsOf)
                        : nil
                    VStack(alignment: .leading, spacing: DSSpacing.m) {
                        ForEach(buckets) { bucket in
                            UsageBucketRow(
                                bucket: bucket,
                                isPercentDimmed: staleNote != nil
                            )
                        }
                    }
                }
            case .unavailable(let reason):
                Text(reason)
                    .font(DSFont.caption)
                    .foregroundStyle(
                        usage.kind == .claudeCode ? DSColor.textTertiary : DSColor.textSecondary
                    )
                    .lineLimit(2)
                if usage.action == .installCursor {
                    Button {
                        openURL(URL(string: "https://cursor.com/downloads")!)
                    } label: {
                        Label("Cursorをインストールしに行く", systemImage: "arrow.down.circle")
                            .font(DSFont.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DSSpacing.m)
                            .padding(.vertical, DSSpacing.xs)
                            .background(DSColor.newSessionGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.m))
    }
}

private struct UsageBucketRow: View {
    let bucket: UsageBucket
    var isPercentDimmed = false
    @State private var revealed = false

    private var remainingPercent: Double {
        100 - bucket.usedPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(bucket.label)
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(DSColor.separator)
                    Capsule(style: .continuous)
                        .fill(UsageDisplay.usageColor(for: bucket.usedPercent))
                        .frame(width: revealed ? max(0, geometry.size.width * remainingPercent / 100) : 0)
                }
            }
            .frame(height: DSLayout.progressBarHeight)
            .animation(.easeOut(duration: 0.7), value: revealed)
            .animation(.easeOut(duration: 0.5), value: bucket.usedPercent)

            HStack(spacing: DSSpacing.xs) {
                Text("残り \(Int(round(remainingPercent)))%")
                    .font(DSFont.caption)
                    .foregroundStyle(
                        isPercentDimmed
                            ? DSColor.textTertiary
                            : UsageDisplay.usageColor(for: bucket.usedPercent)
                    )
                    .monospacedDigit()
                    .animation(.easeOut(duration: 0.5), value: bucket.usedPercent)

                Spacer(minLength: 0)

                if bucket.resetsAt != nil {
                    // 毎分 now を更新し、残り時間の表示と赤色判定を追従させる。
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let reset = UsageDisplay.sidebarResetDisplay(for: bucket, now: context.date) {
                            Text("リセット \(reset.text)")
                                .font(DSFont.caption)
                                .foregroundStyle(reset.isUrgent ? UsageDisplay.urgentResetColor : DSColor.textTertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .onAppear { revealed = true }
    }
}

#Preview("Usage sidebar — unavailable hidden") {
    UsageSidebarPreviewContainer()
        .frame(width: 300, height: 400)
        .background(DSColor.background)
}

@MainActor
private struct UsageSidebarPreviewContainer: View {
    @State private var monitor: UsageMonitor

    init() {
        _monitor = State(initialValue: UsageMonitor(providers: [
            .codex: PreviewUsageProvider(usage: CLIUsage(
                kind: .codex,
                state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 72)]),
                updatedAt: .now
            )),
            .cursor: PreviewUsageProvider(usage: CLIUsage(
                kind: .cursor,
                state: .unavailable(reason: "未取得"),
                updatedAt: .now
            )),
        ]))
    }

    var body: some View {
        UsageSidebarView(monitor: monitor)
            .task { await monitor.refresh() }
    }
}

private struct PreviewUsageProvider: UsageProvider {
    let usage: CLIUsage
    var kind: AgentKind { usage.kind }

    func fetch() async -> CLIUsage {
        usage
    }
}

#Preview("Usage card — ok") {
    UsageCLICard(
        usage: CLIUsage(
            kind: .codex,
            state: .ok([
                UsageBucket(
                    id: "5h",
                    label: "5時間",
                    usedPercent: 72,
                    resetsAt: Date(timeIntervalSince1970: 1_781_179_800)
                ),
                UsageBucket(id: "week", label: "週間", usedPercent: 41),
            ]),
            updatedAt: .now
        )
    )
    .padding()
    .background(DSColor.background)
}

#Preview("Usage card — unavailable") {
    UsageCLICard(
        usage: CLIUsage(
            kind: .claudeCode,
            state: .unavailable(reason: "認証情報が見つかりません"),
            updatedAt: .now
        )
    )
    .padding()
    .background(DSColor.background)
}
