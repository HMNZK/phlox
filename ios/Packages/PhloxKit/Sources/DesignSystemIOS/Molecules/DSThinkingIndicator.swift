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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previousLabel: String?
    @ScaledMetric(relativeTo: .footnote) private var labelPointSize: CGFloat = 13

    public init(
        state: AgentActivityState = .thinking,
        reasoningPreview: String? = nil
    ) {
        self.state = state
        self.reasoningPreview = reasoningPreview
    }

    public var body: some View {
        let label = displayLabel(locale: locale)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: DSSpacing.s))
        layout {
            ShimmerTextView(
                text: label,
                font: DSFont.sessionDetailSubtitle,
                pointSize: labelPointSize,
                color: IOSColor.text.primary
            )
            if let reasoningPreview, !reasoningPreview.isEmpty {
                Text(reasoningPreview)
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(IOSColor.text.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, reasoningPreview].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "。"))
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
