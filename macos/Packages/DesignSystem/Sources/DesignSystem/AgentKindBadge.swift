import SwiftUI
import AgentDomain

public struct AgentKindBadge: View {
    public let descriptor: AgentDescriptor
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(kind: AgentKind) {
        self.descriptor = AgentRegistry.descriptor(for: kind)
    }

    public init(descriptor: AgentDescriptor) {
        self.descriptor = descriptor
    }

    public var body: some View {
        let color = DSColor.agentColor(for: descriptor)
        Text(descriptor.displayName)
            .font(DSFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xxs)
            .background(DSColor.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(descriptor.displayName)
    }
}
