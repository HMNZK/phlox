import SwiftUI
import DesignSystemIOS

struct SessionDetailTranscriptBadge: Identifiable {
    let id: String
    let text: String
    let color: Color
    var monospaced = false
}

struct SessionDetailTranscriptCardHeader: View {
    let label: String
    let summary: String?
    let badges: [SessionDetailTranscriptBadge]
    let isExpanded: Bool
    let allowsDisclosure: Bool
    let onToggle: () -> Void

    var body: some View {
        Group {
            if allowsDisclosure {
                Button(action: onToggle) {
                    headerContents
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "展開中" : "折りたたみ中")
            } else {
                headerContents
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var headerContents: some View {
        HStack(spacing: DSSpacing.xs) {
            if allowsDisclosure {
                Text("›")
                    .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                    .foregroundStyle(IOSColor.text.tertiary)
                    .frame(width: DSSpacing.s)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            Text(label)
                .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                .foregroundStyle(IOSColor.text.secondary)
                .lineLimit(1)
                .fixedSize()
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(DSFont.sessionDetailTechnical)
                    .foregroundStyle(IOSColor.text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            ForEach(badges) { badge in
                Text(badge.text)
                    .font(badge.monospaced ? DSFont.sessionDetailTechnical : DSFont.sessionDetailSubtitle.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(badge.color)
                    .fixedSize()
            }
        }
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
