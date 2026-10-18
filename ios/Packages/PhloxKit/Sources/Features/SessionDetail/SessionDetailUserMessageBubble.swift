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
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                if !attachmentPreviews.isEmpty {
                    HStack(spacing: DSSpacing.xs) {
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
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                IOSColor.bg.code,
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
            .containerRelativeFrame(.horizontal, count: 100, span: 78, spacing: 0, alignment: .trailing)
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
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .accessibilityHidden(true)
        }
        #endif
    }
}
