import AgentDomain
import SessionFeature

extension DashboardViewModel {
    /// 正準パスごとの共有セッション集合。衝突判定の規則は AgentDomain に委譲する。
    public var workspaceCollisions: [String: Set<SessionID>] {
        WorkspaceCollisionPolicy.collisions(among: workspaceSessionWorkspaces)
    }

    /// 現在のセッション一覧で作業ディレクトリを共有しているセッション ID。
    public var workspaceCollisionSessionIDs: Set<SessionID> {
        workspaceCollisions.values.reduce(into: Set<SessionID>()) { result, sessionIDs in
            result.formUnion(sessionIDs)
        }
    }

    private var workspaceSessionWorkspaces: [SessionWorkspace] {
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
