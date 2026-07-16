import SwiftUI
import AgentDomain

public struct AgentSessionIcon: View {
    public let descriptor: AgentDescriptor
    public let status: SessionStatus
    public let size: CGFloat
    @Environment(\.locale) private var locale

    public init(descriptor: AgentDescriptor, status: SessionStatus, size: CGFloat) {
        self.descriptor = descriptor
        self.status = status
        self.size = size
    }

    var showsRunningIndicator: Bool {
        return false
    }

    public var body: some View {
        AgentBrandIcon(descriptor: descriptor, size: size)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(descriptor.displayName), \(StatusBadge.localizedLabel(for: status, locale: locale))")
    }
}
