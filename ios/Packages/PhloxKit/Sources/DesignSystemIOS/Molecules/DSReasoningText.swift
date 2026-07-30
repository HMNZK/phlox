import SwiftUI
import ChatRenderKit

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

    /// Reasoning の見出し・本文・開閉判定は共有の表示データへ委譲する。
    public static func presentation(for text: String) -> ChatReasoningPresentation {
        ChatReasoningPresentation(text: text)
    }

    /// 呼び出し元がトグルを渡し、かつ本文が見出しより長い場合だけ開閉表示にする。
    public static func showsDisclosure(text: String, hasToggle: Bool) -> Bool {
        hasToggle && presentation(for: text).usesDisclosure
    }

    public var body: some View {
        let presentation = Self.presentation(for: text)

        if let onToggle, Self.showsDisclosure(text: text, hasToggle: true) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Button(action: onToggle) {
                    header(
                        title: presentation.headline,
                        showChevron: true,
                        trailingPreview: isExpanded ? nil : Self.collapsedPreview(presentation.trimmedText)
                    )
                }
                .buttonStyle(.plain)
                if isExpanded {
                    bodyText(presentation.trimmedText)
                }
            }
        } else if onToggle != nil {
            Text(presentation.trimmedText)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.chatToolCallText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                legacyHeader
                bodyText(text)
            }
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textSecondary)
            .textSelection(.enabled)
    }

    private var legacyHeader: some View {
        Label("Thinking", systemImage: "brain.head.profile")
            .font(DSFont.captionStrong)
            .foregroundStyle(DSColor.textSecondary)
            .labelStyle(.titleAndIcon)
    }

    private func header(title: String, showChevron: Bool, trailingPreview: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textSecondary)
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
