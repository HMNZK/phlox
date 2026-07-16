import SwiftUI
import DesignSystemIOS
import PhloxCore

/// Usageリミット画面の文言（テスト可能なコピー層）。
enum UsageCopy {
    static let title = "Usageリミット"
    static let emptyTitle = "使用量データがありません"
    static let emptySubtitle = "エージェントの CLI 使用量はまだ取得されていません。"
    static let failedTitle = "取得に失敗しました"
    static let failedSubtitle = "しばらくしてから再試行してください。"
    static let unavailableLabel = "利用不可"
}

/// アカウント単位の CLI 使用量一覧（task-8）。task-7 がタブにホストする。
public struct UsageView: View {
    @State private var model: UsageViewModel

    public init(model: UsageViewModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        content
            .background(DSColor.background)
            .navigationTitle(UsageCopy.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable { await model.load() }
            .task {
                guard !isUITesting else { return }
                await model.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            failedState
        case .loaded:
            if model.isEmpty {
                emptyState
            } else {
                agentList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.m) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.title)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(UsageCopy.emptyTitle)
                .font(DSFont.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text(UsageCopy.emptySubtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        VStack(spacing: DSSpacing.m) {
            Spacer()
            Image(systemName: DSIcon.unreachable)
                .font(.title)
                .foregroundStyle(DSColor.statusError)
                .accessibilityHidden(true)
            Text(UsageCopy.failedTitle)
                .font(DSFont.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text(UsageCopy.failedSubtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
            DSButton("再試行", variant: .secondary) {
                Task { await model.load() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.m) {
                ForEach(model.agents, id: \.kind) { usage in
                    agentCard(usage)
                }
            }
            .padding(DSSpacing.l)
        }
    }

    private func agentCard(_ usage: CLIUsage) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.m) {
                DSAgentAvatar(kind: usage.kind, size: 38)
                Text(usage.kind.displayName)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.s)
                if UsageViewModel.isUnavailable(usage) {
                    unavailableBadge
                }
            }

            if UsageViewModel.isUnavailable(usage) {
                Text(UsageCopy.unavailableLabel)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(usage.buckets) { bucket in
                    bucketRow(bucket)
                }
            }
        }
        .padding(DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DSColor.surfaceElevated,
            in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.border, lineWidth: 1)
        )
    }

    private var unavailableBadge: some View {
        Text(UsageCopy.unavailableLabel)
            .font(DSFont.caption.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                DSColor.campSurfaceDialog,
                in: Capsule(style: .continuous)
            )
    }

    private func bucketRow(_ bucket: UsageBucket) -> some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.label)
                    .font(DSFont.subheadline.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.s)
                Text(UsageViewModel.formattedUsedPercent(bucket.usedPercent))
                    .font(DSFont.subheadline.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            usageProgressBar(percent: bucket.usedPercent)
            if let resetsLabel = UsageViewModel.resetsAtLabel(for: bucket.resetsAt, now: now) {
                Text(resetsLabel)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
    }

    private func usageProgressBar(percent: Double) -> some View {
        let clamped = min(100, max(0, percent)) / 100
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(DSColor.border.opacity(0.35))
                Capsule(style: .continuous)
                    .fill(DSColor.accent)
                    .frame(width: geometry.size.width * clamped)
            }
        }
        .frame(height: DSSpacing.xs)
        .accessibilityLabel("使用率 \(UsageViewModel.formattedUsedPercent(percent))")
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }
}

#if DEBUG
#Preview("loaded") {
    let fixture: [CLIUsage] = [
        CLIUsage(
            kind: .claudeCode,
            state: .ok,
            buckets: [
                UsageBucket(id: "5h", label: "5-hour", usedPercent: 42.0, resetsAt: Date().addingTimeInterval(7200)),
                UsageBucket(id: "weekly", label: "Weekly", usedPercent: 12.5, resetsAt: nil),
            ],
            updatedAt: nil,
            dataAsOf: nil
        ),
        CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil),
    ]
    let stub = PreviewUsageAPI(agents: fixture)
    return NavigationStack {
        UsageView(model: UsageViewModel(api: stub))
    }
}

@MainActor
private final class PreviewUsageAPI: PhloxAPI {
    let agents: [CLIUsage]

    init(agents: [CLIUsage]) {
        self.agents = agents
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "x", name: "x", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: .distantPast)
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func cliUsage() async throws -> [CLIUsage] { agents }
}
#endif
