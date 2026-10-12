import SwiftUI
import AgentDomain

public struct AgentBrandIcon: View {
    public let descriptor: AgentDescriptor
    public let size: CGFloat

    public init(descriptor: AgentDescriptor, size: CGFloat) {
        self.descriptor = descriptor
        self.size = size
    }

    public init(kind: AgentKind, size: CGFloat) {
        self.init(descriptor: AgentRegistry.descriptor(for: kind), size: size)
    }

    public nonisolated static var assetBundle: Bundle { .module }

    public var body: some View {
        brandImage(named: brandAssetName(for: kind), kind: kind)
            .frame(width: size, height: size)
            .accessibilityLabel(descriptor.displayName)
    }

    private var kind: AgentKind {
        guard case .builtin(let kind) = descriptor.ref else { preconditionFailure("AgentRef must be built-in") }
        return kind
    }

    private func brandAssetName(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: "agent-brand-claude"
        case .codex: "agent-brand-codex"
        case .cursor: "agent-brand-cursor"
        }
    }

    @ViewBuilder
    private func brandImage(named name: String, kind: AgentKind) -> some View {
        let base = Image(name, bundle: Self.assetBundle)
        if kind == .cursor {
            base
                .resizable()
                .scaledToFit()
        } else {
            base
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(DSColor.textSecondary)
        }
    }
}
