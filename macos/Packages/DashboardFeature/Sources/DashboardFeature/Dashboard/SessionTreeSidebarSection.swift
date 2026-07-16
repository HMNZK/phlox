import SwiftUI
import AgentDomain

enum SessionSidebarRowIconLayout {
    static let brandIconSize: CGFloat = 15

    static func descriptor(for agentRef: AgentRef) -> AgentDescriptor {
        if let kind = agentRef.builtinKind {
            return AgentRegistry.descriptor(for: kind)
        }
        return AgentDescriptor(
            ref: agentRef,
            displayName: agentRef.id,
            binaryName: agentRef.id,
            symbolName: "terminal",
            colorRGB: AgentRGB(0x8A, 0x8F, 0x98),
            bypassKey: "phlox.bypass.\(agentRef.id)",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
    }
}
