import AgentDomain
import SessionFeature

extension DashboardViewModel {
    /// エディタパネルを含む共有判定の入力。セッションの重複除去と稼働中判定の正本。
    var workspaceSessionWorkspaces: [SessionWorkspace] {
        let ptyWorkspaces = sessions.map(Self.workspace(for:))
        let ptySessionIDs = Set(ptyWorkspaces.map(\.sessionID))
        let appServerWorkspaces = sessionNodes.compactMap { node -> SessionWorkspace? in
            guard let session = node.appServer,
                  !ptySessionIDs.contains(session.id)
            else {
                return nil
            }
            return Self.workspace(for: session)
        }
        return ptyWorkspaces + appServerWorkspaces
    }

    private static func workspace(for session: SessionViewModel) -> SessionWorkspace {
        SessionWorkspace(
            sessionID: session.id,
            workingDirectory: session.rawWorkspacePath,
            isActive: isActive(session.status)
        )
    }

    private static func workspace(for session: ChatSessionViewModel) -> SessionWorkspace {
        SessionWorkspace(
            sessionID: session.id,
            workingDirectory: session.rawWorkspacePath,
            isActive: isActive(session.status)
        )
    }

    private static func isActive(_ status: SessionStatus) -> Bool {
        switch status {
        case .starting, .idle, .running, .awaitingApproval, .awaitingUserQuestion:
            true
        case .completed, .error:
            false
        }
    }
}
