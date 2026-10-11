import SwiftUI
import AgentDomain

public struct AgentBrandIcon: View {
    public let descriptor: AgentDescriptor
    public let size: CGFloat
    private let monochromeBuiltInMark: Bool

    public init(descriptor: AgentDescriptor, size: CGFloat, monochromeBuiltInMark: Bool = false) {
        self.descriptor = descriptor
        self.size = size
        self.monochromeBuiltInMark = monochromeBuiltInMark
    }

    public init(kind: AgentKind, size: CGFloat, monochromeBuiltInMark: Bool = false) {
        self.init(descriptor: AgentRegistry.descriptor(for: kind), size: size, monochromeBuiltInMark: monochromeBuiltInMark)
    }

    public nonisolated static var assetBundle: Bundle { .module }

    public var body: some View {
        Group {
            if let assetName = brandAssetName(for: descriptor.ref.builtinKind) {
                brandImage(named: assetName, kind: descriptor.ref.builtinKind)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(descriptor.displayName)
    }

    private func brandAssetName(for kind: AgentKind?) -> String? {
        switch kind {
        case .claudeCode: "agent-brand-claude"
        case .codex: "agent-brand-codex"
        case .cursor: "agent-brand-cursor"
        default: nil
        }
    }

    @ViewBuilder
    private func brandImage(named name: String, kind: AgentKind?) -> some View {
        let base = Image(name, bundle: Self.assetBundle)
        let usesTemplate = kind == .codex || (kind == .claudeCode && monochromeBuiltInMark)
        let image = usesTemplate ? base.renderingMode(.template) : base
        if usesTemplate {
            image
                .resizable()
                .scaledToFit()
                .foregroundStyle(DSColor.textPrimary)
        } else {
            image
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        let color = DSColor.agentColor(for: descriptor)
        if descriptor.symbolName.isEmpty {
            Text(initial)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color)
        } else {
            Image(systemName: descriptor.symbolName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var initial: String {
        descriptor.displayName.first.map { String($0).uppercased() } ?? "A"
    }
}
