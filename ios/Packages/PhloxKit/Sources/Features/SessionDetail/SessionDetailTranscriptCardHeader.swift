import SwiftUI
import DesignSystemIOS

struct SessionDetailTranscriptBadge: Identifiable {
    let id: String
    let text: String
    let color: Color
    var monospaced = false
    var weight: Font.Weight = .medium
}

struct SessionDetailTranscriptCardHeader: View {
    let label: String
    let summary: String?
    let badges: [SessionDetailTranscriptBadge]
    let isExpanded: Bool
    let allowsDisclosure: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var disclosureWidth = DSSpacing.s

    var body: some View {
        Group {
            if allowsDisclosure {
                Button(action: onToggle) {
                    headerContents
                }
                .buttonStyle(DSPressFeedbackStyle())
                .accessibilityValue(isExpanded ? "展開中" : "折りたたみ中")
            } else {
                headerContents
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var headerContents: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: DSSpacing.xs))
        return layout {
            HStack(spacing: DSSpacing.xs) {
                if allowsDisclosure {
                    Text("›")
                        .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                        .foregroundStyle(IOSColor.text.tertiary)
                        .frame(width: disclosureWidth)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                Text(label)
                    .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                    .lineLimit(isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: !isAccessibilitySize, vertical: true)
            }
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(DSFont.sessionDetailTechnical)
                    .foregroundStyle(IOSColor.text.primary)
                    .lineLimit(isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !isAccessibilitySize {
                Spacer(minLength: 0)
            }
            ForEach(badges) { badge in
                Text(badge.text)
                    .font((badge.monospaced ? DSFont.sessionDetailTechnical : DSFont.sessionDetailSubtitle).weight(badge.weight))
                    .monospacedDigit()
                    .foregroundStyle(badge.color)
                    .fixedSize(horizontal: !isAccessibilitySize, vertical: true)
            }
        }
        .padding(.vertical, isAccessibilitySize ? DSSpacing.chip : 0)
        .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let summaryPart = summary.map { "、\($0)" } ?? ""
        let badgePart = badges.map(\.text).joined(separator: "、")
        return [label + summaryPart, badgePart].filter { !$0.isEmpty }.joined(separator: "、")
    }
}
