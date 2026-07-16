import SwiftUI
import AgentDomain

/// カンプ準拠のエージェント略号バッジ（CC / Cx / Cu）。セッション行・チャットアバター等で共有する。
public struct DSCampAgentBadge: View {
    public enum Size: Sendable, Equatable {
        case sessionRow
        case chatAvatar
    }

    /// セッション行アバター寸法（design.md §2.3 / カンプ②）。
    public static let sessionRowSize: CGFloat = 38
    public static let sessionRowCornerRadius: CGFloat = 10
    /// チャットエージェントアバター（カンプ⑦）。
    public static let chatAvatarSize: CGFloat = 28
    public static let chatAvatarCornerRadius: CGFloat = 8

    let kind: AgentKind
    let size: Size

    public init(kind: AgentKind, size: Size = .sessionRow) {
        self.kind = kind
        self.size = size
    }

    /// カンプのモノ略号（CC / Cx / Cu）。
    public static func abbreviation(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: return "CC"
        case .codex: return "Cx"
        case .cursor: return "Cu"
        default:
            let name = AgentRegistry.descriptor(for: kind).displayName
            return String(name.prefix(2))
        }
    }

    private var dimension: CGFloat {
        switch size {
        case .sessionRow: return Self.sessionRowSize
        case .chatAvatar: return Self.chatAvatarSize
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .sessionRow: return Self.sessionRowCornerRadius
        case .chatAvatar: return Self.chatAvatarCornerRadius
        }
    }

    private var labelFont: Font {
        switch size {
        case .sessionRow: return DSFont.campMono.weight(.bold)
        case .chatAvatar: return DSFont.campMonoCaption.weight(.bold)
        }
    }

    public var body: some View {
        let color = DSColor.campAgentColor(for: kind)
        Text(Self.abbreviation(for: kind))
            .font(labelFont)
            .foregroundStyle(color)
            .frame(width: dimension, height: dimension)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("DSCampAgentBadge") {
    HStack(spacing: DSSpacing.m) {
        DSCampAgentBadge(kind: .claudeCode)
        DSCampAgentBadge(kind: .codex)
        DSCampAgentBadge(kind: .cursor)
        DSCampAgentBadge(kind: .claudeCode, size: .chatAvatar)
        DSCampAgentBadge(kind: .codex, size: .chatAvatar)
    }
    .padding(DSSpacing.l)
}
#endif
