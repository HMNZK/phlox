import SwiftUI

/// Reasoning（思考過程）の控えめ表示。通常のエージェントバブルと視覚的に区別する。
/// `onToggle` を渡すと折りたたみ可能（既定は折りたたみ）。未指定時は従来どおり常時全文表示。
public struct DSReasoningText: View {
    let text: String
    let isExpanded: Bool
    let onToggle: (() -> Void)?

    public init(text: String, isExpanded: Bool = true, onToggle: (() -> Void)? = nil) {
        self.text = text
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let onToggle {
                Button(action: onToggle) {
                    header(showChevron: true, trailingPreview: isExpanded ? nil : Self.collapsedPreview(text))
                }
                .buttonStyle(.plain)
                if isExpanded {
                    bodyText
                }
            } else {
                header(showChevron: false, trailingPreview: nil)
                bodyText
            }
        }
    }

    private var bodyText: some View {
        Text(text)
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textSecondary)
            .textSelection(.enabled)
    }

    private func header(showChevron: Bool, trailingPreview: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Label("Thinking", systemImage: "brain.head.profile")
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textSecondary)
                .labelStyle(.titleAndIcon)
            if let trailingPreview, !trailingPreview.isEmpty {
                Text(trailingPreview)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showChevron {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    static func collapsedPreview(_ text: String, maxLength: Int = 48) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}

#if DEBUG
#Preview("DSReasoningText") {
    DSReasoningText(text: "ユーザーの意図はチャット UI のパリティ改善。Mac 版の視覚仕様に合わせる。")
        .padding(DSSpacing.l)
}
#endif
