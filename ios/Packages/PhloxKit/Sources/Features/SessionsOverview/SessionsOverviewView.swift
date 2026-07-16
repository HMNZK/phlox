import SwiftUI
import DesignSystemIOS
import PhloxCore

/// セッション俯瞰画面。グリッド（複数カード）とシングル（1 件集中）を切り替える。
public struct SessionsOverviewView: View {
    /// テスト用契約: グリッドモードが LazyVGrid で描画されるとき true。
    public static let gridUsesLazyVGrid = true

    @Bindable var viewModel: SessionsOverviewViewModel
    @Environment(\.scenePhase) private var scenePhase
    let onSelectDetail: (String) -> Void
    let onSpawn: () -> Void

    public init(
        viewModel: SessionsOverviewViewModel,
        onSelectDetail: @escaping (String) -> Void,
        onSpawn: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onSelectDetail = onSelectDetail
        self.onSpawn = onSpawn
    }

    public var body: some View {
        content
            .background(DSColor.background)
            .navigationTitle("セッション")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar { toolbarContent }
            .task {
                guard !isUITesting else { return }
                viewModel.start()
            }
            .onChange(of: scenePhase) { _, phase in
                guard !isUITesting else { return }
                if phase == .active { viewModel.start() } else { viewModel.stop() }
            }
            .accessibilityIdentifier(SessionsOverviewAccessibilityID.overview)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            modeToggleButton
        }
        #else
        ToolbarItem(placement: .automatic) {
            modeToggleButton
        }
        #endif
    }

    private var modeToggleButton: some View {
        Button(action: viewModel.toggleMode) {
            Image(systemName: viewModel.mode == .grid ? "square.grid.2x2" : "rectangle")
                .font(.body.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.mode == .grid ? "グリッド表示" : "シングル表示")
        .accessibilityIdentifier(SessionsOverviewAccessibilityID.modeToggle)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            EmptyStateView(onCreate: onSpawn)
        } else {
            switch viewModel.mode {
            case .grid:
                gridContent
            case .single:
                singleContent
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: SessionsOverviewMetrics.gridRowSpacing
            ) {
                ForEach(viewModel.gridSessions) { session in
                    SessionOverviewCard(
                        session: session,
                        isSelected: session.id == viewModel.singleSession?.id
                    ) {
                        viewModel.selectSession(id: session.id)
                        onSelectDetail(session.id)
                    }
                    .accessibilityIdentifier(SessionsOverviewAccessibilityID.gridCard(session.id))
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.l)
        }
        .accessibilityIdentifier(SessionsOverviewAccessibilityID.grid)
    }

    private var singleContent: some View {
        ScrollView {
            VStack(spacing: DSSpacing.l) {
                if let session = viewModel.singleSession {
                    singleFocusedCard(for: session)
                        .accessibilityIdentifier(SessionsOverviewAccessibilityID.singleCard(session.id))

                    if viewModel.gridSessions.count > 1 {
                        singlePicker
                    }
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.l)
        }
        .accessibilityIdentifier(SessionsOverviewAccessibilityID.single)
    }

    @ViewBuilder
    private func singleFocusedCard(for session: Session) -> some View {
        if session.needsAttention {
            DSAttentionRow(session: session) {
                onSelectDetail(session.id)
            }
        } else {
            VStack(spacing: 0) {
                DSSessionRow(session: session, showsDivider: false) {
                    onSelectDetail(session.id)
                }
            }
            .padding(SessionsOverviewMetrics.singleCardPadding)
            .background(DSColor.campSurfaceEmphasis, in: RoundedRectangle(cornerRadius: SessionsOverviewMetrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SessionsOverviewMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
            )
        }
    }

    private var singlePicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionLabel("他のセッション")
                .padding(.horizontal, DSSpacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.s) {
                    ForEach(viewModel.gridSessions) { session in
                        Button {
                            viewModel.selectSession(id: session.id)
                        } label: {
                            Text(session.name)
                                .font(DSFont.footnote.weight(.semibold))
                                .foregroundStyle(
                                    session.id == viewModel.singleSession?.id
                                        ? DSColor.textPrimary
                                        : DSColor.textSecondary
                                )
                                .padding(.horizontal, DSSpacing.m)
                                .padding(.vertical, DSSpacing.s)
                                .background(
                                    session.id == viewModel.singleSession?.id
                                        ? DSColor.campSurfaceEmphasis
                                        : DSColor.surface,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(SessionsOverviewAccessibilityID.singlePickerChip(session.id))
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: SessionsOverviewMetrics.gridMinimumCardWidth),
                spacing: SessionsOverviewMetrics.gridColumnSpacing
            )
        ]
    }
}

/// XCUITest 用 identifier（task-7 ホスト時に参照可能）。
public enum SessionsOverviewAccessibilityID {
    public static let overview = "sessionsOverview"
    public static let modeToggle = "sessionsOverview.modeToggle"
    public static let grid = "sessionsOverview.grid"
    public static let single = "sessionsOverview.single"

    public static func gridCard(_ id: String) -> String { "sessionsOverview.gridCard.\(id)" }
    public static func singleCard(_ id: String) -> String { "sessionsOverview.singleCard.\(id)" }
    public static func singlePickerChip(_ id: String) -> String { "sessionsOverview.singlePicker.\(id)" }
}

#if DEBUG
#Preview("Grid") {
    let sessions = [
        Session(id: "1", name: "Rose", agent: .claudeCode, status: .running, subtitle: "実行中", updatedAt: Date()),
        Session(id: "2", name: "Tulip", agent: .codex, status: .idle, subtitle: "待機中", updatedAt: Date()),
        Session(id: "3", name: "Iris", agent: .cursor, status: .completed(exitCode: 0), subtitle: "完了", updatedAt: Date()),
    ]
    return NavigationStack {
        SessionsOverviewView(
            viewModel: SessionsOverviewViewModel(sessions: sessions),
            onSelectDetail: { _ in }
        )
    }
}

#Preview("Single") {
    let sessions = [
        Session(id: "1", name: "Rose", agent: .claudeCode, status: .awaitingApproval(prompt: "削除を承認?"), subtitle: "承認待ち", updatedAt: Date()),
        Session(id: "2", name: "Tulip", agent: .codex, status: .running, subtitle: "実行中", updatedAt: Date()),
    ]
    let viewModel = SessionsOverviewViewModel(sessions: sessions)
    viewModel.toggleMode()
    return NavigationStack {
        SessionsOverviewView(
            viewModel: viewModel,
            onSelectDetail: { _ in }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        SessionsOverviewView(
            viewModel: SessionsOverviewViewModel(sessions: []),
            onSelectDetail: { _ in }
        )
    }
}
#endif
