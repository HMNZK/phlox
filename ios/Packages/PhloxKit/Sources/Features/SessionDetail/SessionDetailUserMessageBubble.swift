import SwiftUI
import DesignSystemIOS
import PhloxCore
#if canImport(UIKit)
import UIKit
#endif

struct SessionDetailUserMessageBubble: View {
    let text: String
    let attachmentPreviews: [Data]

    var body: some View {
        SessionDetailBubbleLayout {
            VStack(alignment: .trailing, spacing: DSSpacing.s) {
                if !attachmentPreviews.isEmpty {
                    SessionDetailAttachmentLayout {
                        ForEach(Array(attachmentPreviews.enumerated()), id: \.offset) { _, data in
                            thumbnail(data)
                        }
                    }
                }
                let visibleText = SessionDetailTranscriptPresentation.userText(
                    text,
                    hasAttachments: !attachmentPreviews.isEmpty
                )
                if !visibleText.isEmpty {
                    Text(visibleText)
                        .font(DSFont.body)
                        .foregroundStyle(IOSColor.text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DSSpacing.m + DSSpacing.xxs)
            .padding(.vertical, DSSpacing.s + DSSpacing.xxs)
            .background(
                IOSColor.bg.code,
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func thumbnail(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: SessionDetailAttachmentLayout.side, height: SessionDetailAttachmentLayout.side)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.attachmentThumbnail, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.attachmentThumbnail, style: .continuous)
                        .strokeBorder(DSColor.border, lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
        #endif
    }
}

/// 56pt の画像を右揃えで折り返す。文字拡大時も画像自体の寸法は変えない。
struct SessionDetailAttachmentLayout: Layout {
    static let side: CGFloat = 56
    private let gap = DSSpacing.chip

    private func columns(width: CGFloat?, count: Int) -> Int {
        guard let width, width.isFinite else { return max(1, count) }
        return max(1, min(count, Int((width + gap) / (Self.side + gap))))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let columns = columns(width: proposal.width, count: subviews.count)
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: CGFloat(columns) * (Self.side + gap) - gap,
                      height: CGFloat(rows) * (Self.side + gap) - gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columns(width: bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let countInRow = min(columns, subviews.count - (index / columns) * columns)
            let x = bounds.maxX - CGFloat(countInRow - column) * (Self.side + gap) + gap
            let y = bounds.minY + CGFloat(index / columns) * (Self.side + gap)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: Self.side, height: Self.side))
        }
    }
}

/// ScrollView の画面幅ではなく、本文へ提案された幅の78%を上限にする。
struct SessionDetailBubbleLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let maximumWidth = proposal.width.map { max(0, $0 * 0.78) }
        let ideal = content.sizeThatFits(.unspecified)
        return content.sizeThatFits(ProposedViewSize(
            width: maximumWidth.map { min(ideal.width, $0) },
            height: nil
        ))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
