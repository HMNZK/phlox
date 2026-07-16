import SwiftUI
import AgentDomain
import DesignSystem

/// エージェントアバター（SVG ブランドロゴ版）。共有 DesignSystem の AgentBrandIcon
/// （Claude/Codex/Cursor の SVG アセット）をモバイルのバッジ形状で包む。
/// テキスト略号バッジ（DSCampAgentBadge）の置き換え先（task-6）。
/// 契約は Tests/DesignSystemIOSTests/AgentAvatarAcceptanceTests.swift。
public struct DSAgentAvatar: View {
    /// バッジ内ブランドロゴの描画スケール（略号テキストの視覚重量に合わせる）。
    static let brandIconScale: CGFloat = 0.58

    public let kind: AgentKind
    public let size: CGFloat

    public init(kind: AgentKind, size: CGFloat) {
        self.kind = kind
        self.size = size
    }

    /// ブランド SVG アセットで描画されるか（3 ビルトインは true）。
    public nonisolated static func usesBrandArtwork(for kind: AgentKind) -> Bool {
        switch kind {
        case .claudeCode, .codex, .cursor:
            return true
        }
    }

    /// DSCampAgentBadge の角丸寸法に合わせた cornerRadius（既知サイズは固定値、他は sessionRow 比でスケール）。
    public static func cornerRadius(for size: CGFloat) -> CGFloat {
        switch size {
        case DSCampAgentBadge.chatAvatarSize:
            return DSCampAgentBadge.chatAvatarCornerRadius
        case DSCampAgentBadge.sessionRowSize:
            return DSCampAgentBadge.sessionRowCornerRadius
        default:
            return size * (DSCampAgentBadge.sessionRowCornerRadius / DSCampAgentBadge.sessionRowSize)
        }
    }

    private var descriptor: AgentDescriptor {
        AgentRegistry.descriptor(for: kind)
    }

    private var brandIconSize: CGFloat {
        size * Self.brandIconScale
    }

    public var body: some View {
        let color = DSColor.campAgentColor(for: kind)
        let cornerRadius = Self.cornerRadius(for: size)

        AgentBrandIcon(descriptor: descriptor, size: brandIconSize)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .accessibilityLabel(descriptor.displayName)
    }
}

#if DEBUG
#Preview("DSAgentAvatar") {
    HStack(spacing: DSSpacing.m) {
        DSAgentAvatar(kind: .claudeCode, size: DSCampAgentBadge.sessionRowSize)
        DSAgentAvatar(kind: .codex, size: DSCampAgentBadge.sessionRowSize)
        DSAgentAvatar(kind: .cursor, size: DSCampAgentBadge.sessionRowSize)
        DSAgentAvatar(kind: .claudeCode, size: DSCampAgentBadge.chatAvatarSize)
        DSAgentAvatar(kind: .codex, size: DSCampAgentBadge.chatAvatarSize)
    }
    .padding(DSSpacing.l)
}
#endif
