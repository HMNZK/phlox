import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

struct DashboardDetailView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Binding var pendingDeletion: SelectedSessionNode?
    @Binding var renamingSession: SelectedSessionNode?
    @Binding var pendingWorkspaceChange: SessionViewModel?
    @Binding var draftName: String
    let gridColumns: GridColumns
    let onChooseProjectDirectory: () -> Void
    let isCreating: Bool
    let onSelectAgentKind: (AgentKind, SessionBackend) -> Void
    let measuredTrailingOverlayHeight: CGFloat

    var body: some View {
        // 操作系はオーバーレイで前面に描くので、ここは本文のみ。トップバー実測高から上余白を
        // 確保し、本文が操作系オーバーレイの下に潜らないようにする。
        detailMainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(
                .top,
                TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: measuredTrailingOverlayHeight)
            )
    }

    private var filteredGridSessions: [SessionNode] {
        viewModel.filteredGridSessionNodes(projectID: router.gridFilterProjectID)
    }

    @ViewBuilder
    private var detailMainContent: some View {
        if viewModel.projects.isEmpty {
            detailEmptyState
        } else {
            switch router.viewMode {
            case .single:
                singleDetail
            case .grid:
                SessionGridView(
                    sessions: filteredGridSessions,
                    gridColumns: gridColumns,
                    arrangement: gridColumns.fixedCount.map { viewModel.gridArrangement(size: $0) },
                    focusedID: $router.selectedSession,
                    onRemove: { session in pendingDeletion = SelectedSessionNode(session) },
                    onRename: { session in
                        renamingSession = SelectedSessionNode(session)
                        draftName = session.name
                    },
                    onChangeWorkspace: { session in pendingWorkspaceChange = session },
                    onReorder: { moved, target in
                        viewModel.reorderSession(moved, with: target)
                    },
                    onGridAction: { action in
                        if let size = gridColumns.fixedCount {
                            viewModel.handleGridAction(action, size: size)
                        }
                    }
                )
            case .team:
                TeamTimelineView(
                    viewModel: viewModel,
                    router: router,
                    isCreating: isCreating,
                    onSelectAgentKind: onSelectAgentKind
                )
            }
        }
    }

    @ViewBuilder
    private var singleDetail: some View {
        if let selectedID = router.selectedSession,
           let session = viewModel.sessionNode(id: selectedID) {
            switch session {
            case .pty(let session):
                SessionView(viewModel: session)
            case .appServer(let session):
                ChatSessionView(viewModel: session)
                    .id(session.id)
            }
        } else {
            singleSelectEmptyState
        }
    }

    private var detailEmptyState: some View {
        VStack(spacing: DSSpacing.l) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DSColor.textTertiary)
            VStack(spacing: DSSpacing.xs) {
                Text("プロジェクトを追加してください")
                    .font(DSFont.heroTitle)
                    .foregroundStyle(DSColor.textPrimary)
                Text("左の Projects 見出しの「+」から作業フォルダを選び、配下でセッションを開始します。")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onChooseProjectDirectory()
            } label: {
                Label("プロジェクトを追加", systemImage: "folder.badge.plus")
                    .font(DSFont.body)
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
            }
            .buttonStyle(HoverableSoftButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.l)
    }

    @ViewBuilder
    private var singleSelectEmptyState: some View {
        // R4: プロジェクト選択時のみカード。未選択時はプレースホルダ（判定は StartAreaPolicy）。
        switch StartAreaPolicy.content(
            hasSelectedProject: router.selectedProjectID != nil,
            hasSelectedSession: false
        ) {
        case .selectProjectPlaceholder:
            SelectProjectPlaceholderView()
        case .agentStartCards, .sessionContent:
            AgentStartCardsView(
                cards: AgentStartCardsModel.cards(available: viewModel.availableAgentKinds),
                isCreating: isCreating,
                onSelect: onSelectAgentKind
            )
        }
    }
}
