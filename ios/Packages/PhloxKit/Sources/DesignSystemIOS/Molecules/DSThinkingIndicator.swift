import AgentDomain
import DesignSystem
import PhloxCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 会話末尾の実行状態と要約。
public struct DSThinkingIndicator: View {
    let state: AgentActivityState
    let reasoningPreview: String?
    @Environment(\.locale) private var locale
    @State private var previousLabel: String?

    public init(
        state: AgentActivityState = .thinking,
        reasoningPreview: String? = nil
    ) {
        self.state = state
        self.reasoningPreview = reasoningPreview
    }

    public var body: some View {
        let label = displayLabel(locale: locale)
        HStack(spacing: DSSpacing.s) {
            ShimmerTextView(
                text: label,
                font: DSFont.sessionDetailSubtitle,
                pointSize: 13,
                color: IOSColor.text.primary
            )
            if let reasoningPreview, !reasoningPreview.isEmpty {
                Text(reasoningPreview)
                    .font(DSFont.caption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onAppear { previousLabel = label }
        .onChange(of: label) { _, newLabel in
            guard previousLabel != newLabel else { return }
            previousLabel = newLabel
            #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: newLabel)
            #endif
        }
    }

    func displayLabel(locale: Locale) -> String {
        state.orbLabel(locale: locale)
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
