import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 右端のインスペクタ（07）。上の切り替えで「セッション」と「使用量」を出し分ける。
struct InspectorView: View {
    @Bindable var router: AppRouter
    let monitor: UsageMonitor
    let session: SessionNode?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(spacing: 0) {
            NeutralSegmentedControl(
                selection: $router.inspectorTab,
                options: [(InspectorTab.session, "セッション"), (InspectorTab.usage, "使用量")]
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            switch router.inspectorTab {
            case .session:
                ScrollView {
                    if let session {
                        SessionInfoPanel(session: session)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 14)
                    } else {
                        Text("セッションが選択されていません")
                            .font(.system(size: 12))
                            .foregroundStyle(DSColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DSSpacing.l)
                    }
                }
            case .usage:
                UsageSidebarView(monitor: monitor)
            }
        }
        .background(DSColor.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("インスペクタ"))
    }
}

/// インスペクタの「使用量」（07 U1〜U6）。CLI ごとのカードに全バケットの残量とリセットまでの時間。
/// 取得に失敗したら理由と時刻、何分前の値かを書く。初回の取得中だけ骨組みを出す。
public struct UsageSidebarView: View {
    @Bindable var monitor: UsageMonitor
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false
    @AppStorage(UsageSettings.autoRefreshKey) private var autoRefresh = true
    @Environment(\.locale) private var locale

    public init(monitor: UsageMonitor) {
        _monitor = Bindable(wrappedValue: monitor)
    }

    private var visibleKinds: [AgentKind] {
        UsageDisplay.visibleKinds(usages: monitor.usages, showUnavailable: showUnavailable)
    }

    /// 初回の取得中（まだ何も届いていない）。
    private var isFirstLoad: Bool {
        monitor.usages.isEmpty && monitor.isRefreshing
    }

    private var shownKinds: [AgentKind] {
        isFirstLoad ? AgentKind.allCases : visibleKinds
    }

    /// 出しているカードがすべて取得失敗の前回値か。
    private var allFailed: Bool {
        !shownKinds.isEmpty && shownKinds.allSatisfy { monitor.failures[$0] != nil }
    }

    public var body: some View {
        let _ = themeID
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    VStack(spacing: 10) {
                        if allFailed, let failure = shownKinds.compactMap({ monitor.failures[$0] }).first {
                            failureBanner(failure, now: context.date)
                        }
                        if shownKinds.isEmpty {
                            Text("表示できる使用量がありません")
                                .font(.system(size: 12))
                                .foregroundStyle(DSColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DSSpacing.l)
                        }
                        ForEach(shownKinds) { kind in
                            UsageCLICard(
                                kind: kind,
                                usage: monitor.usages[kind],
                                failure: monitor.failures[kind],
                                isLoading: isFirstLoad,
                                now: context.date
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
                footer
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    private func failureBanner(_ failure: UsageFailure, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("使用量を更新できませんでした")
                .fontWeight(.semibold)
                .foregroundStyle(DSColor.attentionInk(.error))
            Text(verbatim: bannerDetail(failure, now: now))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.attentionMark(.error), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// 「ネットワークに接続できません（14:32）。下の値は 2 時間前のものです。」
    private func bannerDetail(_ failure: UsageFailure, now: Date) -> String {
        let time = failure.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        var text = String(format: AppLocalizedString.string("%@（%@）。", locale: locale), failure.reason, time)
        if let succeeded = monitor.lastSucceededAt {
            text += String(format: AppLocalizedString.string("下の値は %@のものです。", locale: locale), UsageText.ago(succeeded, now: now, locale: locale))
        }
        return text
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    HStack(spacing: 6) {
                        if monitor.isRefreshing {
                            ProgressView().controlSize(.mini)
                        }
                        Text(refreshLabel)
                    }
                    .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(monitor.isRefreshing)
                .help(Text("使用量を更新"))
            }
            Text("自動更新・Claude の取得・未取得の CLI の表示は 設定 > 詳細")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 失敗の記録があるか、出しているカードがどれも取れていない（初回の失敗など）。
    private var hasFailure: Bool {
        !monitor.failures.isEmpty
            || (!shownKinds.isEmpty && shownKinds.allSatisfy { if case .unavailable = monitor.usages[$0]?.state { true } else { false } })
    }

    private var refreshLabel: LocalizedStringKey {
        if monitor.isRefreshing { return "更新中" }
        return hasFailure ? "再試行" : "更新"
    }

    /// 「最終更新 14:32 · 自動更新 オン」、失敗なら「最終更新 12:31（失敗 14:32）」。
    private var footerText: String {
        if monitor.isRefreshing { return AppLocalizedString.string("更新中…", locale: locale) }
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        guard let succeeded = monitor.lastSucceededAt ?? monitor.lastRefreshedAt else {
            return AppLocalizedString.string("未更新", locale: locale)
        }
        let last = String(format: AppLocalizedString.string("最終更新 %@", locale: locale), succeeded.formatted(style))
        if let failedAt = monitor.failures.values.map(\.at).max() {
            return last + String(format: AppLocalizedString.string("（失敗 %@）", locale: locale), failedAt.formatted(style))
        }
        let auto = AppLocalizedString.string(autoRefresh ? "自動更新 オン" : "自動更新 オフ", locale: locale)
        return "\(last) · \(auto)"
    }
}

/// 使用量の文言（相対時刻・リセットまで）。表示言語に合わせる。
enum UsageText {
    /// 「2 時間前」。
    static func ago(_ date: Date, now: Date, locale: Locale) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .abbreviated, locale: locale))
    }

    /// 「1 時間 42 分後にリセット」。1 日以上は日だけ。
    static func resetsIn(_ resetsAt: Date, now: Date, locale: Locale) -> String {
        let seconds = max(60, resetsAt.timeIntervalSince(now))
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 86_400 ? [.day] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        let span = formatter.string(from: seconds) ?? ""
        return String(format: AppLocalizedString.string("%@後にリセット", locale: locale), span)
    }
}

struct UsageCLICard: View {
    let kind: AgentKind
    let usage: CLIUsage?
    let failure: UsageFailure?
    let isLoading: Bool
    let now: Date
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    private var buckets: [UsageBucket] {
        if case .ok(let buckets) = usage?.state { return buckets }
        return []
    }

    /// Claude の鮮度（ClaudeUsageStaleness の閾値）。
    private var staleNote: String? {
        guard kind == .claudeCode, let usage, usage.dataAsOf != nil, case .ok = usage.state else { return nil }
        return ClaudeUsageStaleness.note(now: now, dataAsOf: usage.dataAsOf)
    }

    /// 取得失敗か古い値。数字を淡くし、注記を琥珀にする。
    private var isStale: Bool { failure != nil || staleNote != nil }

    private var hasLowBucket: Bool {
        buckets.contains { UsageDisplay.isLowRemaining(usedPercent: $0.usedPercent) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                AgentBrandIcon(kind: kind, size: 14)
                Text(verbatim: kind.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 4)
                if let note {
                    Text(verbatim: note)
                        .font(.system(size: 11, weight: isStale ? .semibold : .regular))
                        .foregroundStyle(isStale ? DSColor.attentionInk(.approval) : DSColor.textTertiary)
                        .lineLimit(1)
                }
            }

            if isLoading || usage == nil {
                skeleton
            } else if case .unavailable(let reason) = usage?.state {
                Text(verbatim: reason)
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if usage?.action == .installCursor {
                    Button {
                        openURL(URL(string: "https://cursor.com/downloads")!)
                    } label: {
                        Text("Cursor をインストールしに行く ↗")
                            .font(.system(size: 12))
                    }
                    .controlSize(.small)
                }
            } else {
                ForEach(buckets) { bucket in
                    UsageBucketRow(bucket: bucket, isStale: isStale, now: now)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(hasLowBucket ? DSColor.attentionMark(.approval) : DSColor.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// 取得中…／2 時間前の値／43 分前に取得・古い可能性（Claude）／12 分前に取得（Claude）。
    private var note: String? {
        if isLoading || usage == nil { return AppLocalizedString.string("取得中…", locale: locale) }
        if failure != nil, let usage {
            return String(format: AppLocalizedString.string("%@の値", locale: locale), UsageText.ago(usage.dataAsOf ?? usage.updatedAt, now: now, locale: locale))
        }
        if let staleNote { return staleNote }
        if case .unavailable = usage?.state { return AppLocalizedString.string("未取得", locale: locale) }
        if let dataAsOf = usage?.dataAsOf {
            return String(format: AppLocalizedString.string("%@に取得", locale: locale), UsageText.ago(dataAsOf, now: now, locale: locale))
        }
        return nil
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(DSColor.fillSelected).frame(width: 140, height: 10)
            RoundedRectangle(cornerRadius: 3).fill(DSColor.fillSelected).frame(height: 5)
            RoundedRectangle(cornerRadius: 4).fill(DSColor.fillSelected).frame(width: 90, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct UsageBucketRow: View {
    let bucket: UsageBucket
    let isStale: Bool
    let now: Date
    @Environment(\.locale) private var locale

    private var remaining: Int { Int(round(100 - max(0, min(100, bucket.usedPercent)))) }
    private var isLow: Bool { UsageDisplay.isLowRemaining(usedPercent: bucket.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AppLocalizedString.string(bucket.label, locale: locale))
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 4)
                Text(verbatim: String(format: AppLocalizedString.string("残り %lld%%", locale: locale), remaining))
                    .fontWeight(isLow ? .bold : .medium)
                    .foregroundStyle(isLow ? DSColor.attentionInk(.approval) : DSColor.textPrimary)
                    .monospacedDigit()
                    .opacity(isStale ? 0.6 : 1)
            }
            .font(.system(size: 12))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(DSColor.fillSelected)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLow ? DSColor.attentionMark(.approval) : DSColor.textSecondary)
                        .frame(width: geometry.size.width * CGFloat(remaining) / 100)
                        .opacity(isStale ? 0.45 : 1)
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.5), value: bucket.usedPercent)

            if let resetsAt = bucket.resetsAt {
                let reset = UsageText.resetsIn(resetsAt, now: now, locale: locale)
                Text(verbatim: isLow ? reset + AppLocalizedString.string(" · 上限間近", locale: locale) : reset)
                    .font(.system(size: 11, weight: isLow ? .semibold : .regular))
                    .foregroundStyle(isLow ? DSColor.attentionInk(.approval) : DSColor.textTertiary)
            }
        }
    }
}
