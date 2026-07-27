import AgentDomain

public enum SessionReachability {
    public nonisolated static func isReachable(
        launchContext: SessionLaunchContext,
        projectID: ProjectID?
    ) -> Bool {
        DashboardViewModel.isVisibleInGrid(launchContext: launchContext) || projectID != nil
    }
}
