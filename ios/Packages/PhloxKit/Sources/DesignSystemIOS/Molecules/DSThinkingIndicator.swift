import AgentDomain
import DesignSystem
import PhloxCore
import SwiftUI

/// 応答生成中インジケータ。点描の orb + 状態語 + 任意の reasoning プレビュー（3行まで）。
/// accessibilityReduceMotion への追従は `ThinkingOrbView` が内部で行う。
public struct DSThinkingIndicator: View {
    let state: AgentActivityState
    let reasoningPreview: String?
    let status: SessionStatus?
    @Environment(\.locale) private var locale

    public init(
        state: AgentActivityState = .thinking,
        reasoningPreview: String? = nil,
        status: SessionStatus? = nil
    ) {
        self.state = state
        self.reasoningPreview = reasoningPreview
        self.status = status
    }

    public var body: some View {
        let presentation = pendingStatusPresentation(locale: locale)
        let label = displayLabel(locale: locale)
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                ThinkingOrbView(state: state, size: .inline)
                ShimmerTextView(
                    text: label,
                    font: DSFont.body.weight(presentation?.weight?.fontWeight ?? .regular),
                    pointSize: DSFont.bodyPointSize,
                    // 帯の明度で不透明度を変調するため、基準色は本文色（下限で secondary 相当）。
                    color: presentation?.color ?? IOSColor.text.primary
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            if let reasoningPreview, !reasoningPreview.isEmpty {
                Text(reasoningPreview)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(3)
            }
        }
    }

    func displayLabel(locale: Locale) -> String {
        pendingStatusPresentation(locale: locale)?.label ?? state.orbLabel(locale: locale)
    }

    private func pendingStatusPresentation(locale: Locale) -> IOSStatusPresentation? {
        guard let status else { return nil }
        switch status {
        case .awaitingApproval, .awaitingUserQuestion:
            return IOSStatusVocabulary.presentation(for: status, locale: locale)
        default:
            return nil
        }
    }
}

#if DEBUG
#Preview("DSThinkingIndicator") {
    VStack(alignment: .leading, spacing: DSSpacing.m) {
        ForEach(AgentActivityState.allCases, id: \.self) { state in
            DSThinkingIndicator(state: state)
        }
        DSThinkingIndicator(
            state: .searching,
            reasoningPreview: "実装方針を検討中。既存 DS トークンに合わせて視覚を揃える。"
        )
    }
    .padding(DSSpacing.l)
}
#endif
