import SwiftUI
import AgentDomain

enum SessionSidebarRowIconLayout {
    static let brandIconSize: CGFloat = 15

    static func descriptor(for agentRef: AgentRef) -> AgentDescriptor {
        switch agentRef {
        case .builtin(let kind):
            return AgentRegistry.descriptor(for: kind)
        }
    }
}
