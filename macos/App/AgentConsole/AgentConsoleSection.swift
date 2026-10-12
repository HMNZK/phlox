import AgentConfigKit
import SwiftUI
import DesignSystem

extension AgentConsoleAgent {
    /// ハーネスごとの色は使わず、中立色で表示する。
    var tint: Color {
        DSColor.textSecondary
    }
}
