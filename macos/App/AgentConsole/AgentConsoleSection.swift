import AgentConfigKit
import SwiftUI
import DesignSystem

extension AgentConsoleAgent {
    /// グループ見出しの色。セッション一覧の色分けとは独立に、ここだけで完結させる。
    var tint: Color {
        switch self {
        case .claude: return DSColor.accent
        case .codex: return DSColor.statusCompleted
        case .cursor: return DSColor.statusRunning
        }
    }
}
