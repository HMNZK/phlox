import SwiftUI
import AgentDomain
import DesignSystem

struct UsageTopBarView: View {
    let monitor: UsageMonitor
    /// ツールバーの幅の段階。狭い段階ほど小さい表示から始める。どの段階でも収まらなければ
    /// ゲージ付き→数字だけ→最小の残量 1 つの順に縮退する（01 D・07 のチップ）。
    let density: ToolbarDensity

    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false

    private static let gaugeWidth: CGFloat = 28

    private typealias TopBarChip = UsageDisplay.TopBarChip

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // staleNote は now に依存する唯一の要素。毎分 context.date で純関数を呼び直し、
            // 表示専用ロジックの重複（View 側での再計算）を作らない（PM 裁定・レビュー MEDIUM）。
            let chips = UsageDisplay.topBarChips(
                usages: monitor.usages,
                showUnavailable: showUnavailable,
                now: context.date
            )
            if !chips.isEmpty {
                ViewThatFits(in: .horizontal) {
                    // fixedSize が無いと内部 Text が折り返しで「収まった」と報告し、
                    // 次段への縮退が発動せず縦潰れ表示になる（フェーズ4目視で検出）。
                    if density == .full {
                        chipsRow(chips, showsGauge: true).fixedSize()
                    }
                    if density != .minimal {
                        chipsRow(chips, showsGauge: false).fixedSize()
                    }
                    minimumRemaining(chips).fixedSize()
                }
            }
        }
    }

    /// エージェントごとに一番少ないバケットの残量を 1 つ（07 論点）。
    private func chipsRow(_ chips: [TopBarChip], showsGauge: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(chips) { chip in
                HStack(spacing: 5) {
                    Text(verbatim: Self.shortName(chip.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.textSecondary)
                    // 取得に失敗して前回の値を出しているときは「—」（07 のチップ）。
                    let remaining = monitor.failures[chip.kind] == nil ? Self.remaining(chip) : nil
                    if showsGauge {
                        gauge(remaining: remaining, isDimmed: chip.staleNote != nil)
                    }
                    valueText(remaining: remaining, isDimmed: chip.staleNote != nil)
                }
                .help(UsageDisplay.topBarHelpText(chip: chip, now: Date()))
            }
        }
    }

    /// 最も狭い段階。残りが最小の 1 つだけを出す。
    @ViewBuilder
    private func minimumRemaining(_ chips: [TopBarChip]) -> some View {
        let values = chips.filter { monitor.failures[$0.kind] == nil }.compactMap(Self.remaining)
        valueText(remaining: values.min(), isDimmed: false)
    }

    /// 取得失敗は「—」、読込中（更新中）は淡く、残り 20% 未満は琥珀＋太字。
    private func valueText(remaining: Int?, isDimmed: Bool) -> some View {
        let isLow = remaining.map { Double($0) < UsageDisplay.lowRemainingThreshold } ?? false
        let isLoading = monitor.isRefreshing
        return Text(verbatim: remaining.map { "\($0)%" } ?? "—")
            .font(.system(size: 11, weight: isLow ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(
                isLow ? DSColor.attentionInk(.approval)
                    : (isLoading || isDimmed || remaining == nil) ? DSColor.textTertiary : DSColor.textPrimary
            )
    }

    private func gauge(remaining: Int?, isDimmed: Bool) -> some View {
        let value = CGFloat(remaining ?? 0)
        let isLow = Double(value) < UsageDisplay.lowRemainingThreshold && remaining != nil
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(DSColor.fillSelected)
            RoundedRectangle(cornerRadius: 2)
                .fill(isLow ? DSColor.attentionMark(.approval) : DSColor.textSecondary)
                .frame(width: Self.gaugeWidth * value / 100)
                .opacity(monitor.isRefreshing || isDimmed ? 0.4 : 1)
        }
        .frame(width: Self.gaugeWidth, height: 4)
        .animation(.easeOut(duration: 0.5), value: value)
    }

    /// 取得できていなければ nil（「—」）。
    private static func remaining(_ chip: TopBarChip) -> Int? {
        guard !chip.isUnavailable, let used = chip.allBuckets.map(\.usedPercent).max() else { return nil }
        return Int(round(100 - max(0, min(100, used))))
    }

    private static func shortName(_ kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
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
