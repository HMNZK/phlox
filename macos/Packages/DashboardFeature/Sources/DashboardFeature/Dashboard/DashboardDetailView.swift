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
    let onChooseProjectDirectory: () -> Void
    let isCreating: Bool
    let onSelectAgentKind: (AgentKind, SessionBackend) -> Void
    /// グリッドのタイルの 会話 / 端末 / 変更（02 C3）。
    var tileTabs: GridTileTabs? = nil

    var body: some View {
        // ツールバーは上の行として別に並べるので、ここは本文だけ。
        detailMainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredGridSessions: [SessionNode] {
        viewModel.filteredGridSessionNodes(projectID: router.gridFilterProjectID)
    }

    /// 子セッションの親の名前（06 S7「↳ 親: …」）。
    private var parentNames: [SessionID: String] {
        var names: [SessionID: String] = [:]
        for node in filteredGridSessions {
            if let parent = node.controllable.parentSessionID, let parentNode = viewModel.sessionNode(id: parent) {
                names[node.id] = parentNode.displayName
            }
        }
        return names
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
                    paneLayout: viewModel.paneLayoutForDisplay(),
                    focusedID: $router.selectedSession,
                    onRemove: { session in pendingDeletion = SelectedSessionNode(session) },
                    onRename: { session in
                        renamingSession = SelectedSessionNode(session)
                        draftName = session.name
                    },
                    onChangeWorkspace: { session in pendingWorkspaceChange = session },
                    onLayoutAction: { viewModel.handlePaneLayoutAction($0) },
                    projectNames: Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, $0.name) }),
                    onRemoveFromGrid: { session in
                        if let next = viewModel.removeFromGrid(session.id), router.selectedSession == session.id {
                            router.selectedSession = next
                        }
                    },
                    onOpenSingle: { router.openSingle(sessionID: $0) },
                    parentNames: parentNames,
                    tileTabs: tileTabs
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
                ChatSessionView(viewModel: session, projectName: viewModel.projects.first(where: { $0.id == session.projectID })?.name)
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
