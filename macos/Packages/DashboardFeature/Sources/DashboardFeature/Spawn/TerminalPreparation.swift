import AgentDomain
import TerminalUI

/// Spawn 直前に TerminalCoordinator へ適用する準備処理をまとめる名前空間。
/// 「いつ scrollback を切るか」のポリシー判断を DashboardViewModel から切り離す。
public enum TerminalPreparation {
    @MainActor
    public static func apply(_ policy: ScrollbackPolicy, to coordinator: TerminalCoordinator) {
        switch policy {
        case .keep:
            break
        case .disableBeforeSpawn:
            coordinator.disableScrollback()
        }
    }
}
