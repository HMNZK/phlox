import AgentDomain

/// エディタパネルが対象とする選択セッションの値。
///
/// 全セッションの配列ではなく、選択中セッションとその作業ディレクトリ、共有相手数だけを
/// 持つことで、無関係なセッションの増減ではエディタの状態を無効化しない。
struct EditorPanelTarget: Equatable, Sendable {
    let selectedSessionID: SessionID?
    let workingDirectory: String?
    let peerCount: Int
}

/// 選択セッションからエディタパネルの更新対象を導く純粋な規則。
enum EditorPanelTargetPolicy {
    static func target(
        selectedSessionID: SessionID?,
        workspaces: [SessionWorkspace]
    ) -> EditorPanelTarget {
        guard let selectedSessionID,
              let selectedWorkspace = workspaces.first(where: {
                  $0.sessionID == selectedSessionID
              }) else {
            return EditorPanelTarget(
                selectedSessionID: selectedSessionID,
                workingDirectory: nil,
                peerCount: 0
            )
        }

        let peerCount = WorkspaceCollisionPolicy.activePeers(
            at: selectedWorkspace.workingDirectory,
            excluding: selectedSessionID,
            among: workspaces
        ).count
        return EditorPanelTarget(
            selectedSessionID: selectedSessionID,
            workingDirectory: selectedWorkspace.workingDirectory,
            peerCount: peerCount
        )
    }
}
