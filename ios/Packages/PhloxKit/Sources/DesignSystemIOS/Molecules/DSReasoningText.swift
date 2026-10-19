import SwiftUI
import ChatRenderKit

/// 思考過程を、既定で閉じた共通カードとして表示する。
public struct DSReasoningText: View {
    let text: String
    let isExpanded: Bool
    let onToggle: (() -> Void)?
    @ScaledMetric(relativeTo: .subheadline) private var lineSpacing = DSSpacing.chip
    @ScaledMetric(relativeTo: .footnote) private var disclosureWidth = DSSpacing.s

    public init(text: String, isExpanded: Bool = false, onToggle: (() -> Void)? = nil) {
        self.text = text
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public static func presentation(for text: String) -> ChatReasoningPresentation {
        ChatReasoningPresentation(text: text)
    }

    public static func showsDisclosure(text: String, hasToggle: Bool) -> Bool {
        _ = text
        return hasToggle
    }

    public var body: some View {
        let bodyText = Self.presentation(for: text).trimmedText
        if let onToggle {
            DSChatCodeCard(showsDivider: isExpanded) {
                Button(action: onToggle) {
                    HStack(spacing: DSSpacing.xs) {
                        Text("›")
                            .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                            .foregroundStyle(IOSColor.text.tertiary)
                            .frame(width: disclosureWidth)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("思考")
                            .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                            .foregroundStyle(IOSColor.text.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressFeedbackStyle())
            } content: {
                DSDisclosureContent(isExpanded: isExpanded) {
                    Text(bodyText)
                        .font(DSFont.sessionDetailReasoning)
                        .foregroundStyle(IOSColor.text.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, DSSpacing.xxl)
                        .padding(.trailing, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                }
            }
            .accessibilityIdentifier("SessionDetailThinkingCard")
        } else {
            Text(bodyText)
                .font(DSFont.iosCaption2)
                .foregroundStyle(IOSColor.text.secondary)
                .textSelection(.enabled)
        }
    }
}
