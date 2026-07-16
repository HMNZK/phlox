import SwiftUI
import AgentDomain

/// 到達不可・ローディング時のプレースホルダ行（カンプ⑩）。操作不可オーバーレイの背後に並べる。
public struct DSSkeletonRow: View {
    let agentKind: AgentKind
    let showsDivider: Bool
    let primaryBarWidthRatio: CGFloat
    let secondaryBarWidthRatio: CGFloat

    public init(
        agentKind: AgentKind,
        showsDivider: Bool = true,
        primaryBarWidthRatio: CGFloat = 0.6,
        secondaryBarWidthRatio: CGFloat = 0.4
    ) {
        self.agentKind = agentKind
        self.showsDivider = showsDivider
        self.primaryBarWidthRatio = primaryBarWidthRatio
        self.secondaryBarWidthRatio = secondaryBarWidthRatio
    }

    /// セッション行アバターと同寸（design.md §2.3）。
    public static let agentBadgeSize = DSSessionRow.agentBadgeSize

    public var body: some View {
        HStack(spacing: DSSpacing.m) {
            skeletonAgentBadge
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                skeletonBar(height: DSSkeletonMetrics.primaryBarHeight, widthRatio: primaryBarWidthRatio)
                skeletonBar(height: DSSkeletonMetrics.secondaryBarHeight, widthRatio: secondaryBarWidthRatio)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DSSpacing.m)
        .padding(.leading, DSSpacing.xs)
        .padding(.trailing, DSSpacing.m - DSSpacing.xxs)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(DSColor.campCardBorder)
                    .frame(height: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var skeletonAgentBadge: some View {
        let color = DSColor.campAgentColor(for: agentKind)
        return RoundedRectangle(cornerRadius: DSSessionRow.agentBadgeCornerRadius, style: .continuous)
            .fill(color.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: DSSessionRow.agentBadgeCornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .frame(width: Self.agentBadgeSize, height: Self.agentBadgeSize)
    }

    private func skeletonBar(height: CGFloat, widthRatio: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .fill(height == DSSkeletonMetrics.primaryBarHeight
                      ? DSColor.textTertiary.opacity(0.35)
                      : DSColor.fillSubtle)
                .frame(width: proxy.size.width * widthRatio, height: height)
        }
        .frame(height: height)
    }
}

private enum DSSkeletonMetrics {
    static let primaryBarHeight: CGFloat = 13
    static let secondaryBarHeight: CGFloat = 10
}

#if DEBUG
#Preview("DSSkeletonRow") {
    VStack(spacing: 0) {
        DSSkeletonRow(agentKind: .claudeCode)
        DSSkeletonRow(agentKind: .codex, primaryBarWidthRatio: 0.5, secondaryBarWidthRatio: 0.35)
        DSSkeletonRow(agentKind: .cursor, showsDivider: false, primaryBarWidthRatio: 0.55, secondaryBarWidthRatio: 0.3)
    }
    .padding(DSSpacing.m)
    .opacity(0.32)
    .background(DSColor.background)
}
#endif
