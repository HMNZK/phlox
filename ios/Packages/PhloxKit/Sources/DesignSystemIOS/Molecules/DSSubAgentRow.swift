import SwiftUI

/// サブエージェント実行表示の1行。wire は平文テキスト（例 "Sub-agent explore-map running: 調査"）のみ
/// なので、テキストをそのまま表示する（status のパースはしない）。
public struct DSSubAgentRow: View {
    let text: String
    let isTappable: Bool
    let onTap: (() -> Void)?

    public init(text: String, isTappable: Bool = false, onTap: (() -> Void)? = nil) {
        self.text = text
        self.isTappable = isTappable
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if isTappable, let onTap {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップでサブエージェントの詳細を表示")
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "person.2.circle")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
            Text(text)
                .font(DSFont.caption)
                .foregroundStyle(isTappable ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(2)
            if isTappable {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("DSSubAgentRow") {
    VStack(spacing: DSSpacing.m) {
        DSSubAgentRow(text: "Sub-agent explore-map running: コードベース調査")
        DSSubAgentRow(text: "Sub-agent explore-map completed", isTappable: true, onTap: {})
    }
    .padding(DSSpacing.l)
}
#endif
