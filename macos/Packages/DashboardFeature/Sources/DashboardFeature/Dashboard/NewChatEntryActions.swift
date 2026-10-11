import AgentDomain

/// 新規チャットへ入る各 UI 操作の共通アクション。
@MainActor
public struct NewChatEntryActions {
    private let router: AppRouter?
    private let dashboard: DashboardViewModel?

    public init(router: AppRouter?, dashboard: DashboardViewModel?) {
        self.router = router
        self.dashboard = dashboard
    }

    public func fileMenu() {
        show(projectID: defaultProjectID())
    }

    public func sidebarFooter() {
        show(projectID: defaultProjectID())
    }

    public func projectPlus(_ projectID: ProjectID) {
        show(projectID: projectID)
    }

    public func projectMenu(_ projectID: ProjectID) {
        show(projectID: projectID)
    }

    public func gridEmptyState(projectID: ProjectID?) {
        show(projectID: projectID ?? defaultProjectID())
    }

    private func defaultProjectID() -> ProjectID? {
        guard let dashboard else { return router?.selectedProjectID }
        return dashboard.defaultProjectIDForNewChat(
            selectedProjectID: router?.selectedProjectID,
            selectedSessionID: router?.selectedSession
        )
    }

    private func show(projectID: ProjectID?) {
        router?.showNewChat(projectID: projectID)
    }
}
