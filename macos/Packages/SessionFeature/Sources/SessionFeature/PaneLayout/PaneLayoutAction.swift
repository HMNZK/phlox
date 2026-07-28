import AgentDomain

/// ビュー（SessionFeature）が発行し VM（DashboardFeature）が処理するレイアウト操作。
public enum PaneLayoutAction: Equatable, Sendable {
    case setDivider(PaneDividerID, leadingFraction: Double)
    case insertBySplitting(session: SessionID, target: SessionID, edge: PaneEdge)
    case swap(SessionID, SessionID)
    case equalize(PaneID)
    case applyPreset(PaneLayoutPreset)
}
