import SwiftUI
import DesignSystemIOS
import PhloxCore

/// グリッド俯瞰用のコンパクトセッションカード。
struct SessionOverviewCard: View {
    let session: Session
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                HStack(spacing: DSSpacing.s) {
                    DSAgentAvatar(kind: session.agent, size: SessionsOverviewCardMetrics.badgeSize)
                    Spacer(minLength: 0)
                    DSStatusChip(status: session.status)
                }

                Text(session.name)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(detailLine)
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(SessionsOverviewCardMetrics.contentPadding)
            .frame(maxWidth: .infinity, minHeight: SessionsOverviewCardMetrics.minHeight, alignment: .topLeading)
            .background(DSColor.campSurfaceEmphasis, in: cardShape)
            .overlay(cardShape.strokeBorder(borderColor, lineWidth: 1))
            .opacity(DSSessionRow.rowOpacity(for: session.status))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SessionsOverviewMetrics.cardCornerRadius, style: .continuous)
    }

    private var borderColor: Color {
        isSelected ? DSColor.campAccentBright.opacity(0.55) : DSColor.campCardBorder
    }

    private var detailLine: String {
        let statusLabel = StatusBadge.localizedLabel(for: session.status, locale: locale)
        return DSSessionRow.campDetailLine(
            subtitle: session.subtitle,
            statusLabel: statusLabel,
            updatedAt: session.updatedAt,
            now: Date()
        )
    }
}

enum SessionsOverviewCardMetrics {
    static let badgeSize: CGFloat = 32
    static let contentPadding = DSSpacing.m
    static let minHeight: CGFloat = 132
}

#if DEBUG
#Preview("SessionOverviewCard") {
    SessionOverviewCard(
        session: Session(
            id: "1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            subtitle: "実行中",
            updatedAt: Date()
        ),
        isSelected: false,
        onTap: {}
    )
    .padding()
    .background(DSColor.background)
}
#endif
