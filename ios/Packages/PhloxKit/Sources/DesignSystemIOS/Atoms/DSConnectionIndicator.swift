import SwiftUI

/// 接続済みホスト表示（カンプ⑪）。緑ドット + 「接続済み · {host}」をモノスペースで示す。
public struct DSConnectionIndicator: View {
    let host: String

    public init(host: String) {
        self.host = host
    }

    /// カンプの緑ドット直径（6px）。
    public static let dotDiameter: CGFloat = 6

    /// VoiceOver / テスト用の表示文言。
    public static func labelText(host: String) -> String {
        "接続済み · \(host)"
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs + 1) {
            Circle()
                .fill(DSColor.statusRunning)
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                .accessibilityHidden(true)

            Text(Self.labelText(host: host))
                .font(DSFont.campMonoCaption)
                .foregroundStyle(DSColor.statusRunning)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Self.labelText(host: host)))
    }
}

#if DEBUG
#Preview("DSConnectionIndicator") {
    DSConnectionIndicator(host: "100.64.0.1")
        .padding(DSSpacing.l)
        .background(DSColor.background)
}
#endif
