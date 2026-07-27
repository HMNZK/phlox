import AgentDomain

/// 到達可能性を問うクライアント。出口ごとに「その通知が届く先」が違う。
public enum SessionSurfaceClient: Sendable, Equatable {
    /// macOS 本体の画面（グリッド／ワークスペース絞り込み／サイドバー）。
    case desktop
    /// iPhone アプリ（Control API の一覧）。
    case mobile
}

public enum SessionReachability {
    public nonisolated static func isReachable(
        from client: SessionSurfaceClient,
        launchContext: SessionLaunchContext,
        projectID: ProjectID?
    ) -> Bool {
        switch client {
        case .desktop:
            DashboardViewModel.isVisibleInGrid(launchContext: launchContext) || projectID != nil
        case .mobile:
            // iPhone の一覧は
            // macos/App/ControlActionDashboard+DashboardViewModel.swift:16-31 の
            // controlSessionSummaries と同じく launchContext で絞らず、全セッションを返す。
            // これはモバイル面の明示的な可視性ポリシーであり、将来その一覧に絞り込みを
            // 導入する際はここも更新すれば、APNs のゲートが同じ規則へ自動追従する。
            true
        }
    }
}
