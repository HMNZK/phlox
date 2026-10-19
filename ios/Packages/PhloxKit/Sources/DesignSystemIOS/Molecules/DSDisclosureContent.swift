import SwiftUI

/// 本文を縮めず、表示領域の高さだけを開閉する。
public struct DSDisclosureContent<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isExpanded: Bool
    private let content: () -> Content

    public init(isExpanded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .transition(.modifier(
                    active: DSDisclosureHeightModifier(expansion: 0),
                    identity: DSDisclosureHeightModifier(expansion: 1)
                ))
            }
        }
        .animation(DSMotion.disclosureAnimation(reduceMotion: reduceMotion), value: isExpanded)
        .accessibilityHidden(!isExpanded)
        .allowsHitTesting(isExpanded)
    }
}

private struct DSDisclosureHeightModifier: ViewModifier, Animatable {
    var expansion: CGFloat

    nonisolated var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func body(content: Content) -> some View {
        DSDisclosureHeightLayout(expansion: expansion) {
            content
        }
        .clipped()
    }
}

struct DSDisclosureHeightLayout: Layout {
    var expansion: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: size.width, height: size.height * expansion)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
