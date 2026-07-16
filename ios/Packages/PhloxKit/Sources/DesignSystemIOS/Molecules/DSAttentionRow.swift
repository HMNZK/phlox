import SwiftUI
import AgentDomain
import PhloxCore

/// 「あなたの番」セクション用の行（カンプ②）。強調カード（ピンク左帯・#221A33 地・薄ピンク枠）に
/// エージェントバッジ・タイトル・補助（相対時刻）・黄チップ（承認待ち/質問待ち）を載せる。
public struct DSAttentionRow: View {
    let session: Session
    let now: Date
    let onTap: () -> Void
    @Environment(\.locale) private var locale

    public init(session: Session, now: Date = Date(), onTap: @escaping () -> Void) {
        self.session = session
        self.now = now
        self.onTap = onTap
    }

    /// カンプ左端ピンク帯の幅（4px = `DSSpacing.xs`）。
    static let accentBarWidth = DSSpacing.xs
    /// 強調カード角丸（14px）。
    static let cornerRadius = DSRadius.card
    /// 左端ピンク帯色（`#F472B6`）。
    static var accentColor: Color { DSColor.campAttention }
    /// 強調行背景（`#221A33`）。
    static var surfaceColor: Color { DSColor.campSurfaceEmphasis }
    /// 薄ピンク枠（`rgba(244,114,182,.32)`）。
    static var borderColor: Color { DSColor.campAttention.opacity(0.32) }
    /// 黄チップのティント（承認待ち・質問待ち共通）。
    static var chipTint: Color { DSColor.statusAwaitingApproval }

    /// 承認待ちと質問待ちの区別（サブラベル `回答待ち:` で質問を識別）。
    public enum AttentionKind: Equatable {
        case approval
        case question
    }

    public static func attentionKind(for session: Session) -> AttentionKind {
        session.subtitle.hasPrefix("回答待ち") ? .question : .approval
    }

    /// 黄チップ文言（承認待ち / 質問待ち）。
    public static func chipLabel(for session: Session, locale: Locale) -> String {
        switch attentionKind(for: session) {
        case .approval:
            return StatusBadge.localizedLabel(for: session.status, locale: locale)
        case .question:
            let isJapanese = locale.language.languageCode?.identifier == "ja"
            return isJapanese ? "質問待ち" : "question"
        }
    }

    /// 表示する承認プロンプト（テスト可能な決定点）。awaitingApproval なら prompt、
    /// それ以外は subtitle にフォールバック。
    var promptPreview: String {
        if case .awaitingApproval(let prompt) = session.status, !prompt.isEmpty {
            return prompt
        }
        return session.subtitle
    }

    /// 補助行（「ファイル削除の承認待ち · 2分前」「回答待ち: 『…』」）。
    var subtitleLine: String {
        Self.subtitleLine(for: session, now: now)
    }

    static func subtitleLine(for session: Session, now: Date) -> String {
        if !session.subtitle.isEmpty {
            if session.subtitle.contains("分前")
                || session.subtitle.contains("時間前")
                || session.subtitle.contains("日前")
                || session.subtitle.hasSuffix("今")
                || session.subtitle.hasPrefix("回答待ち") {
                return session.subtitle
            }
            let relative = DSRelativeTime.compact(from: session.updatedAt, now: now)
            return "\(session.subtitle) · \(relative)"
        }
        if case .awaitingApproval(let prompt) = session.status, !prompt.isEmpty {
            return "回答待ち: 「\(prompt)」"
        }
        return DSRelativeTime.compact(from: session.updatedAt, now: now)
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.m) {
                DSAgentBadge(kind: session.agent)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(session.name)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(subtitleLine)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: DSSpacing.s)

                attentionChip
            }
            .padding(.vertical, DSSpacing.m)
            .padding(.trailing, DSSpacing.m)
            .padding(.leading, DSSpacing.m)
            .frame(minHeight: DSTouch.rowMinHeight)
            .background(Self.surfaceColor, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Self.borderColor, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Self.accentColor
                    .frame(width: Self.accentBarWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityHint(Text("承認画面を開く"))
    }

    private var attentionChip: some View {
        let label = Self.chipLabel(for: session, locale: locale)
        let tint = Self.chipTint
        return HStack(spacing: DSSpacing.xs) {
            Image(systemName: StatusBadge.iconName(for: session.status))
                .imageScale(.small)
            Text(label)
                .font(DSFont.captionStrong)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(tint.opacity(0.34), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityLabel(Text(label))
    }

    private var accessibilitySummary: String {
        let chip = Self.chipLabel(for: session, locale: locale)
        return "あなたの番、\(session.name)、\(subtitleLine)、\(chip)"
    }
}

#if DEBUG
#Preview("DSAttentionRow") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return VStack(spacing: DSSpacing.s) {
        DSAttentionRow(
            session: Session(
                id: "1",
                name: "refactor: ControlServer proxy",
                agent: .claudeCode,
                status: .awaitingApproval(prompt: "ControlServer.swift を削除して続行しますか？"),
                subtitle: "ファイル削除の承認待ち",
                updatedAt: now.addingTimeInterval(-120)
            ),
            now: now
        ) {}
        DSAttentionRow(
            session: Session(
                id: "2",
                name: "add /approvals endpoint",
                agent: .codex,
                status: .awaitingApproval(prompt: "v2 契約で進めますか？"),
                subtitle: "回答待ち: 「v2 契約で進めますか？」",
                updatedAt: now.addingTimeInterval(-300)
            ),
            now: now
        ) {}
    }
    .padding(DSSpacing.l)
}
#endif
