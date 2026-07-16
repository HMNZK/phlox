import SwiftUI

/// セクション見出し（カンプ①②④ — 12px 太字・大文字・`campTextQuaternary`）。
public struct DSSectionLabel: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    /// カンプ letter-spacing .06–.08em 相当。
    public static let kerning: CGFloat = 0.8

    public var body: some View {
        Text(title)
            .font(DSFont.footnote.weight(.bold))
            .kerning(Self.kerning)
            .textCase(.uppercase)
            .foregroundStyle(DSColor.campTextQuaternary)
    }
}

#if DEBUG
#Preview("DSSectionLabel") {
    DSSectionLabel("実行中・その他")
        .padding()
        .background(DSColor.background)
}
#endif
