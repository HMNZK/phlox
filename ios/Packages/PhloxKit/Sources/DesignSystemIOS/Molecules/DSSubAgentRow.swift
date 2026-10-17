import SwiftUI

/// サブエージェント実行表示の1行。wire は平文テキスト（例 "Sub-agent explore-map running: 調査"）のみ
/// なので、テキストをそのまま表示する（status のパースはしない）。
public struct DSSubAgentRow: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "person.2.circle")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
            Text(text)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("サブエージェント、\(text)")
    }
}

#if DEBUG
#Preview("DSSubAgentRow") {
    VStack(spacing: DSSpacing.m) {
        DSSubAgentRow(text: "Sub-agent explore-map running: コードベース調査")
        DSSubAgentRow(text: "Sub-agent explore-map completed")
    }
    .padding(DSSpacing.l)
}
#endif
