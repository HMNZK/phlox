import SwiftUI
import AgentDomain
import PhloxCore

/// セッション一覧の通常行（カンプ②「実行中・その他」）。区切り線・エージェントロゴ・
/// 状態チップ・補助行（subtitle · 相対時刻）を表示する。承認待ちは `DSAttentionRow` を使う。
public struct DSSessionRow: View {
    public static let agentLogoSize: CGFloat = 38

    let session: Session
    let now: Date
    let showsDivider: Bool
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    public init(
        session: Session,
        now: Date = Date(),
        showsDivider: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.session = session
        self.now = now
        self.showsDivider = showsDivider
        self.onTap = onTap
    }

    /// カンプ準拠の相対時刻。`DSRelativeTime.compact` へ委譲。
    public static func campRelativeTime(from date: Date, now: Date) -> String {
        DSRelativeTime.compact(from: date, now: now)
    }

    /// 補助行テキスト。「{subtitle} · {時刻}」または subtitle 空時は「{状態} · {時刻}」。
    public static func campDetailLine(
        subtitle: String,
        statusLabel: String,
        updatedAt: Date,
        now: Date
    ) -> String {
        let time = campRelativeTime(from: updatedAt, now: now)
        let lead = subtitle.isEmpty ? statusLabel : subtitle
        return "\(lead) · \(time)"
    }

    /// 行全体の不透明度（完了 .82 / 待機 .7 / その他 1.0）。
    public static func rowOpacity(for status: SessionStatus) -> Double {
        switch status {
        case .idle:
            return 0.7
        case .completed:
            return 0.82
        default:
            return 1.0
        }
    }

    private var statusLabel: String {
        IOSStatusVocabulary.presentation(for: session.status, locale: locale).label ?? ""
    }

    private var detailLine: String {
        guard session.status != .idle else { return "" }
        return Self.campDetailLine(
            subtitle: session.subtitle,
            statusLabel: statusLabel,
            updatedAt: session.updatedAt,
            now: now
        )
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.m) {
                DSAgentBrandIcon(kind: session.agent, size: Self.agentLogoSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(session.name)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)

                    if !detailLine.isEmpty {
                        Text(detailLine)
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DSSpacing.s)

                DSStatusChip(status: session.status)
            }
            .padding(.vertical, DSSpacing.m)
            .padding(.leading, DSSpacing.xs)
            .padding(.trailing, DSSpacing.m - DSSpacing.xxs)
            .frame(minHeight: DSTouch.rowMinHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(IOSColor.bg.separator)
                        .frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(Self.rowOpacity(for: session.status))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(AgentRegistry.descriptor(for: session.agent).displayName)、\(session.name)、\(statusLabel)、\(detailLine)"))
        .accessibilityHint(Text("詳細を開く"))
    }
}

#if DEBUG
private struct DSSessionRowPreviewHost: View {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    var body: some View {
        VStack(spacing: 0) {
            DSSessionRow(
                session: Session(
                    id: "1", name: "implement spawn flow", agent: .claudeCode,
                    status: .running, subtitle: "出力中",
                    updatedAt: now.addingTimeInterval(-12)
                ),
                now: now
            ) {}
            DSSessionRow(
                session: Session(
                    id: "2", name: "write unit tests", agent: .codex,
                    status: .completed(exitCode: 0), subtitle: "完了",
                    updatedAt: now.addingTimeInterval(-300)
                ),
                now: now
            ) {}
            DSSessionRow(
                session: Session(
                    id: "3", name: "docs: README 更新", agent: .cursor,
                    status: .idle, subtitle: "",
                    updatedAt: now.addingTimeInterval(-1080)
                ),
                now: now,
                showsDivider: false
            ) {}
        }
        .padding(DSSpacing.m)
        .background(DSColor.background)
    }
}

#Preview("DSSessionRow") {
    DSSessionRowPreviewHost()
}
#endif
