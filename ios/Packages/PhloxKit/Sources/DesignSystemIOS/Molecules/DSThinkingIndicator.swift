import AgentDomain
import DesignSystem
import SwiftUI

/// 応答生成中インジケータ。点描の orb + 状態語 + 任意の reasoning プレビュー（3行まで）。
/// accessibilityReduceMotion への追従は `ThinkingOrbView` が内部で行う。
public struct DSThinkingIndicator: View {
    let state: AgentActivityState
    let reasoningPreview: String?

    public init(state: AgentActivityState = .thinking, reasoningPreview: String? = nil) {
        self.state = state
        self.reasoningPreview = reasoningPreview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                ThinkingOrbView(state: state, size: .inline)
                Text(state.orbLabel)
                    .font(DSFont.body.italic())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.orbLabel)
            if let reasoningPreview, !reasoningPreview.isEmpty {
                Text(reasoningPreview)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(3)
            }
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
