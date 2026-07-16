import SwiftUI
import DesignSystemIOS
import PhloxCore

/// セッション一覧ヘッダの文言（カンプ②⑪）。`SessionListViewModel.listSubtitle` への後方互換。
public enum SessionListHeaderCopy {
    public static func loadedSubtitle(sessionCount: Int, host: String) -> String {
        "\(sessionCount) 件 · \(host)"
    }
}

/// セッション一覧画面（カンプ② / ⑩）。状態に応じて表示を切り替える。
public struct SessionListView: View {
    public static let listTitle = "Projects"
    public static let providesPerProjectAddSessionRow = true
    public static let providesSpawnFAB = false
    public static let providesListSubtitle = false

    @Bindable var viewModel: SessionListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var expandedGroupIDs: Set<String> = []
    let reachability: Reachability
    let host: String
    let onSelectDetail: (String) -> Void
    let onAnswerQuestion: (String) -> Void
    let onAddSession: (String) -> Void
    let onReconnect: () async -> Void
    let onSettings: () -> Void

    public init(
        viewModel: SessionListViewModel,
        reachability: Reachability = .unknown,
        host: String? = nil,
        onSelectDetail: @escaping (String) -> Void,
        onAnswerQuestion: @escaping (String) -> Void,
        onAddSession: @escaping (String) -> Void,
        onReconnect: @escaping () async -> Void = {},
        onSettings: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.reachability = reachability
        self.host = host ?? viewModel.connectionHost
        self.onSelectDetail = onSelectDetail
        self.onAnswerQuestion = onAnswerQuestion
        self.onAddSession = onAddSession
        self.onReconnect = onReconnect
        self.onSettings = onSettings
    }

    public var body: some View {
        content
            .background(DSColor.background)
            .navigationTitle(Self.listTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable { await viewModel.refresh() }
            .task {
                guard !isUITesting else { return }
                viewModel.start()
            }
            .onChange(of: scenePhase) { _, phase in
                guard !isUITesting else { return }
                if phase == .active { viewModel.start() } else { viewModel.stop() }
            }
            .accessibilityIdentifier(AccessibilityID.sessionList)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            EmptyStateView(onCreate: { onAddSession("") })
        case .offline:
            offlineOverlay
        case .error(let error):
            VStack(spacing: DSSpacing.m) {
                DSResultBanner(message: error.presentation.message, isError: true)
                DSButton("再試行", variant: .secondary) { Task { await viewModel.refresh() } }
            }
            .padding(DSSpacing.l)
        case .loaded:
            loadedList
        }
    }

    private var offlineOverlay: some View {
        VStack(spacing: 0) {
            offlineBanner
            ZStack(alignment: .bottom) {
                skeletonBackground
                UnreachableView(viewModel: unreachableViewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offlineBanner: some View {
        Text(unreachableViewModel.bannerText())
            .font(DSFont.subheadline)
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .background(DSColor.statusError.opacity(0.15))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DSColor.statusError.opacity(0.35))
                    .frame(height: 1)
            }
            .accessibilityLabel(Text(unreachableViewModel.bannerText()))
    }

    private var skeletonBackground: some View {
        ScrollView {
            VStack(spacing: 0) {
                DSSkeletonRow(agentKind: .claudeCode)
                DSSkeletonRow(agentKind: .codex, primaryBarWidthRatio: 0.55, secondaryBarWidthRatio: 0.35)
                DSSkeletonRow(agentKind: .cursor, primaryBarWidthRatio: 0.5, secondaryBarWidthRatio: 0.3)
                DSSkeletonRow(agentKind: .claudeCode, showsDivider: false, primaryBarWidthRatio: 0.6, secondaryBarWidthRatio: 0.38)
            }
            .padding(.top, DSSpacing.xs)
        }
        .opacity(OfflineOverlayMetrics.skeletonOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var unreachableViewModel: UnreachableViewModel {
        UnreachableViewModel(
            reachability: offlineReachability,
            host: host,
            lastUpdated: offlineLastUpdated,
            onRetry: {
                await onReconnect()
                await viewModel.refresh()
            }
        )
    }

    private var offlineReachability: Reachability {
        switch reachability {
        case .offlineNetwork, .unreachableHost:
            return reachability
        default:
            return .unreachableHost
        }
    }

    private var offlineLastUpdated: Date? {
        if isUnreachableUITestScreen {
            return Date().addingTimeInterval(-180)
        }
        return viewModel.lastFetchedAt
    }

    private var isUnreachableUITestScreen: Bool {
        ProcessInfo.processInfo.arguments.contains("-UIScreen=unreachable")
    }

    private var loadedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.attentionSessions.isEmpty {
                    attentionSectionHeader
                        .padding(.bottom, DSSpacing.s)

                    ForEach(viewModel.attentionSessions) { session in
                        DSAttentionRow(session: session) { selectAttentionSession(session) }
                            .padding(.bottom, DSSpacing.s)
                            .accessibilityIdentifier(AccessibilityID.attentionRow(session.id))
                    }
                    .padding(.bottom, DSSpacing.m)
                }

                projectGroupsList
            }
            .padding(.horizontal, SessionListMetrics.listHorizontalPadding)
            .padding(.bottom, DSSpacing.l)
        }
        .onChange(of: viewModel.groupedOtherSessions.map(\.id), initial: true) { _, groupIDs in
            expandedGroupIDs.formUnion(groupIDs)
        }
    }

    @ViewBuilder
    private var projectGroupsList: some View {
        let groups = viewModel.groupedOtherSessions
        if groups.isEmpty {
            // 全セッションが attention セクションに入り project グループが空でも、
            // セッション追加導線が消えないよう単独の追加行を出す
            // （セッション皆無の .empty 状態は EmptyStateView が担うので、ここは loaded で groups だけ空のケース）。
            addSessionRow(projectID: "")
        } else {
            VStack(spacing: DSSpacing.m) {
                ForEach(groups) { group in
                    projectGroupDisclosure(group)
                }
            }
        }
    }

    private func projectGroupDisclosure(_ group: ProjectGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedGroupIDs.contains(group.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedGroupIDs.insert(group.id)
                    } else {
                        expandedGroupIDs.remove(group.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                projectSessionsCard(group.sessions)
                addSessionRow(projectID: group.id)
            }
            .padding(.top, DSSpacing.xs)
        } label: {
            Text(group.title)
                .font(DSFont.footnote.weight(.bold))
                .kerning(SessionListMetrics.sectionHeaderKerning)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.campTextQuaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func projectSessionsCard(_ sessions: [Session]) -> some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    DSSessionRow(
                        session: session,
                        showsDivider: index < sessions.count - 1
                    ) {
                        onSelectDetail(session.id)
                    }
                    .accessibilityIdentifier(AccessibilityID.sessionRow(session.id))
                }
            }
            .background(DSColor.campSurfaceEmphasis, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
            )
        }
    }

    private var attentionSectionHeader: some View {
        HStack(spacing: DSSpacing.s) {
            Circle()
                .fill(DSColor.campAttention)
                .frame(width: SessionListMetrics.glowDotSize, height: SessionListMetrics.glowDotSize)
                .shadow(color: DSColor.campAttention, radius: SessionListMetrics.glowDotShadowRadius)
            Text(viewModel.attentionSectionTitle)
                .font(DSFont.footnote.weight(.bold))
                .kerning(SessionListMetrics.sectionHeaderKerning)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.campAttention)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("あなたの番")
    }

    private func addSessionRow(projectID: String) -> some View {
        Button {
            onAddSession(projectID)
        } label: {
            Text("+ セッションを追加")
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.campAccentBright)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DSSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("+ セッションを追加")
    }

    private func selectAttentionSession(_ session: Session) {
        if session.subtitle.hasPrefix("回答待ち") {
            onAnswerQuestion(session.id)
        } else {
            onSelectDetail(session.id)
        }
    }
}

// MARK: - Camp metrics（カンプ②）

private enum SessionListMetrics {
    static let listHorizontalPadding = DSSpacing.m - DSSpacing.xxs
    static let glowDotSize: CGFloat = 7
    static let glowDotShadowRadius: CGFloat = 8
    static let sectionHeaderKerning: CGFloat = 0.8
}

private enum OfflineOverlayMetrics {
    static let skeletonOpacity = 0.32
}

#if DEBUG
#Preview("Loaded") {
    let sessions = [
        Session(id: "1", name: "Rose", agent: .claudeCode, status: .awaitingApproval(prompt: "削除を承認?"), subtitle: "承認待ち", updatedAt: Date()),
        Session(id: "2", name: "Tulip", agent: .codex, status: .running, subtitle: "実行中", updatedAt: Date()),
    ]
    return NavigationStack {
        SessionListView(
            viewModel: SessionListViewModel(
                repository: StubSessionRepository(states: [.loaded(sessions)]),
                configStore: InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765))
            ),
            onSelectDetail: { _ in },
            onAnswerQuestion: { _ in },
            onAddSession: { _ in }
        )
    }
}

#Preview("Offline overlay") {
    NavigationStack {
        SessionListView(
            viewModel: SessionListViewModel(repository: StubSessionRepository(states: [.offline])),
            reachability: .unreachableHost,
            host: "100.64.0.1",
            onSelectDetail: { _ in },
            onAnswerQuestion: { _ in },
            onAddSession: { _ in },
            onReconnect: {}
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        SessionListView(
            viewModel: SessionListViewModel(repository: StubSessionRepository(states: [.empty])),
            onSelectDetail: { _ in },
            onAnswerQuestion: { _ in },
            onAddSession: { _ in }
        )
    }
}
#endif
