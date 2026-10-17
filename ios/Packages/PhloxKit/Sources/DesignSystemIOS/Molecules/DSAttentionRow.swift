import SwiftUI
import AgentDomain
import PhloxCore

/// 「あなたの番」セクション用の行（カンプ②）。状態に応じた面とエージェントロゴを表示する。
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

    /// 左端の状態色帯の幅。
    static let accentBarWidth = DSSpacing.xs
    /// 強調カード角丸（14px）。
    static let cornerRadius = DSRadius.card
    public enum AttentionKind: Equatable {
        case approval
        case question
    }

    public static func attentionKind(for session: Session) -> AttentionKind {
        if case .awaitingUserQuestion = session.status { return .question }
        return .approval
    }

    public static func chipLabel(for session: Session, locale: Locale) -> String {
        IOSStatusVocabulary.presentation(for: session.status, locale: locale).label ?? ""
    }

    static func tint(for session: Session) -> Color {
        IOSStatusVocabulary.presentation(for: session.status).color ?? IOSColor.status.approval
    }

    static func surface(for session: Session) -> Color {
        switch attentionKind(for: session) {
        case .approval: IOSColor.status.approvalBackground
        case .question: IOSColor.status.questionBackground
        }
    }

    static func border(for session: Session) -> Color {
        tint(for: session).opacity(0.32)
    }

    /// 表示する承認プロンプト（テスト可能な決定点）。awaitingApproval なら prompt、
    /// それ以外は subtitle にフォールバック。
    var promptPreview: String {
        if case .awaitingApproval(let prompt) = session.status, !prompt.isEmpty {
            return prompt
        }
        return session.subtitle
    }

    /// 補助行。質問の古い「回答待ち」前置きは状態語「質問あり」に揃える。
    var subtitleLine: String {
        Self.subtitleLine(for: session, now: now)
    }

    static func subtitleLine(for session: Session, now: Date) -> String {
        if !session.subtitle.isEmpty {
            if session.subtitle.contains("分前")
                || session.subtitle.contains("時間前")
                || session.subtitle.contains("日前")
                || session.subtitle.hasSuffix("今")
                || session.subtitle.hasPrefix("回答待ち")
                || session.subtitle.hasPrefix("質問あり") {
                return session.subtitle.replacingOccurrences(of: "回答待ち", with: "質問あり")
            }
            let relative = DSRelativeTime.compact(from: session.updatedAt, now: now)
            return "\(session.subtitle) · \(relative)"
        }
        if case .awaitingUserQuestion = session.status, !session.subtitle.isEmpty {
            return session.subtitle
        }
        return DSRelativeTime.compact(from: session.updatedAt, now: now)
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.m) {
                DSAgentBrandIcon(kind: session.agent, size: DSSessionRow.agentLogoSize)
                    .accessibilityHidden(true)

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
            .background(Self.surface(for: session), in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Self.border(for: session), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Self.tint(for: session)
                    .frame(width: Self.accentBarWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityHint(Text(Self.attentionKind(for: session) == .question ? "質問を開く" : "承認を開く"))
    }

    private var attentionChip: some View {
        let label = Self.chipLabel(for: session, locale: locale)
        let presentation = IOSStatusVocabulary.presentation(for: session.status, locale: locale)
        return Text(label)
        .font(DSFont.subheadline.weight((presentation.weight ?? .semibold).fontWeight))
        .foregroundStyle(presentation.color ?? IOSColor.status.approval)
        .fixedSize()
        .accessibilityLabel(Text(label))
    }

    private var accessibilitySummary: String {
        let chip = Self.chipLabel(for: session, locale: locale)
        let agentName = AgentRegistry.descriptor(for: session.agent).displayName
        return "あなたの番、\(agentName)、\(session.name)、\(subtitleLine)、\(chip)"
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
                status: .awaitingUserQuestion,
                subtitle: "質問あり: 「v2 契約で進めますか？」",
                updatedAt: now.addingTimeInterval(-300)
            ),
            now: now
        ) {}
    }
    .padding(DSSpacing.l)
}
#endif
