import SwiftUI
import AgentDomain

/// `AgentKind` を識別色つきの角丸バッジで表示する。表示名・色は共有レジストリ（SSOT）から引く。
public struct DSAgentBadge: View {
    let kind: AgentKind

    public init(kind: AgentKind) {
        self.kind = kind
    }

    /// バッジが表示する CLI 表示名（テスト可能な解決点）。
    var displayName: String {
        AgentRegistry.descriptor(for: kind).displayName
    }

    public var body: some View {
        let color = DSColor.campAgentColor(for: kind)
        Text(displayName)
            .font(DSFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xxs)
            .background(DSColor.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(Text(displayName))
    }
}

#if DEBUG
#Preview("DSAgentBadge") {
    HStack(spacing: DSSpacing.s) {
        DSAgentBadge(kind: .claudeCode)
        DSAgentBadge(kind: .codex)
        DSAgentBadge(kind: .cursor)
    }
    .padding(DSSpacing.l)
}
#endif
