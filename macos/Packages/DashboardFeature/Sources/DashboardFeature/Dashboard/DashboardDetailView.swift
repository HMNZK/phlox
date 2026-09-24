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
    /// カスタム種別を含む起動（08 S3・S4）。
    var onSelectAgent: ((AgentRef, SessionBackend) -> Void)? = nil
    /// 起動中の種別（08 S5）。
    var creatingRef: AgentRef? = nil
    /// 初回起動の案内をすべて出すか（08 S1: 一度もプロジェクトを追加していない）。
    var showsAllOnboardingSteps = true
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
        StartOnboardingView(
            entries: viewModel.agentStartEntries(languageCode: languageCode),
            showsAllSteps: showsAllOnboardingSteps,
            onAddFolder: onChooseProjectDirectory
        )
    }

    @Environment(\.locale) private var locale

    private var languageCode: String {
        locale.language.languageCode?.identifier ?? "ja"
    }

    private var startHeader: AgentStartProjectHeader? {
        guard let project = viewModel.projects.first(where: { $0.id == router.selectedProjectID }) else { return nil }
        let running = viewModel.sessionNodes(in: project.id).filter {
            switch $0.status {
            case .completed, .error: false
            default: true
            }
        }.count
        return AgentStartProjectHeader(
            name: project.name,
            path: project.directoryPath,
            branch: GitBranchReader.currentBranch(at: project.directoryPath),
            isolates: project.usesWorktreeIsolation,
            runningCount: running
        )
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
                onSelect: onSelectAgentKind,
                entries: viewModel.agentStartEntries(languageCode: languageCode),
                onSelectRef: onSelectAgent,
                creatingRef: creatingRef,
                header: startHeader,
                defaultBackend: DefaultSessionBackendPreference.stored()
            )
        }
    }
}
