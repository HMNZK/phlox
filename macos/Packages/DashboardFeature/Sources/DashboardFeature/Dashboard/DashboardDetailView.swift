import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

struct DashboardDetailView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var newChatDraftStore: NewChatDraftStore
    @Binding var pendingDeletion: SelectedSessionNode?
    let onRenameSession: (SessionID) -> Void
    @Binding var pendingWorkspaceChange: SessionViewModel?
    let onNewChatLaunchFailure: (AgentRef, Error) -> Void
    var displayTab: ProjectTab? = nil

    private var displayedSessionID: SessionID? {
        if let displayTab {
            if case .chat(let id) = displayTab { return id }
            return nil
        }
        return router.selectedSession
    }

    var body: some View {
        // ツールバーは上の行として別に並べるので、ここは本文だけ。
        detailMainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 新規チャットの起動に失敗した行の「再起動」「閉じる」。単体表示とグリッドで同じものを使う。
    private var launchFailureActions: ChatLaunchFailureActions {
        ChatLaunchFailureActions(
            restart: { id in
                guard case .appServer(let session) = viewModel.sessionNode(id: id), let projectID = session.projectID else { return }
                Task {
                    do {
                        _ = try await viewModel.restartNewChat(id) { newID in
                            router.completeNewChat(sessionID: newID, projectID: projectID)
                        }
                    } catch {
                        onNewChatLaunchFailure(session.agentRef, error)
                    }
                }
            },
            close: { id in Task { await viewModel.removeSession(id) } },
            isRestarting: { viewModel.restartingNewChatIDs.contains($0) }
        )
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
        switch router.viewMode {
        case .single:
            singleDetail
        case .grid:
            SessionGridView(
                sessions: filteredGridSessions,
                paneLayout: viewModel.paneLayoutForDisplay(),
                focusedID: $router.selectedSession,
                onRemove: { session in pendingDeletion = SelectedSessionNode(session) },
                onRename: { session in onRenameSession(session.id) },
                onChangeWorkspace: { session in pendingWorkspaceChange = session },
                onLayoutAction: { viewModel.handlePaneLayoutAction($0) },
                projectNames: Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, $0.name) }),
                onRemoveFromGrid: { session in
                    if let next = viewModel.removeFromGrid(session.id), router.selectedSession == session.id {
                        router.selectedSession = next
                    }
                },
                onOpenSingle: { router.openSingle(sessionID: $0) },
                parentNames: parentNames
            )
            .environment(\.chatLaunchFailureActions, launchFailureActions)
            // ⌃⌥＋矢印で分割線を動かすときの下限の判定に、グリッドの実際の大きさを使う。
            // SessionGridView の余白（左右 s・下 s・上 xs）を除いた、タイルを並べる領域。
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                viewModel.gridCanvasSize = CGSize(
                    width: size.width - DSSpacing.s * 2,
                    height: size.height - DSSpacing.s - DSSpacing.xs
                )
            }
        }
    }

    @ViewBuilder
    private var singleDetail: some View {
        if displayTab == .newChat {
            newChatView(project: newChatProject)
        } else if let selectedID = displayedSessionID,
           let session = viewModel.sessionNode(id: selectedID) {
            switch session {
            case .pty(let session):
                SessionView(viewModel: session)
            case .appServer(let session):
                ChatSessionView(
                    viewModel: session,
                    projectName: viewModel.projects.first(where: { $0.id == session.projectID })?.name,
                    onLaunchFailureRestart: { launchFailureActions.restart(session.id) },
                    isLaunchFailureRestarting: launchFailureActions.isRestarting(session.id),
                    onLaunchFailureClose: { launchFailureActions.close(session.id) }
                )
                    // 「この会話から再開」で同じ ID の VM が差し替わったら、ビューも作り直して末尾へ寄せ直す（04 B3）。
                    .id(ObjectIdentifier(session))
            }
        } else {
            newChatView(project: newChatProject)
        }
    }

    private var newChatProject: Project? {
        viewModel.projects.first { $0.id == router.newChatProjectID }
    }

    private func newChatView(project: Project?) -> some View {
        NewChatView(
            viewModel: viewModel,
            router: router,
            draft: newChatDraftStore.draft,
            project: project,
            onLaunchFailure: onNewChatLaunchFailure
        )
    }
}
