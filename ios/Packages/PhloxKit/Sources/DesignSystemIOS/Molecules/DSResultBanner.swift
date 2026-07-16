import SwiftUI

/// spawn / send / delete 等の結果を表示するインラインバナー（カンプ④⑨）。
public struct DSResultBanner: View {
    let message: String
    let isError: Bool

    public init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }

    /// アイコン名と tint を解決する純粋ヘルパー（テスト可能な決定点）。
    static func iconName(isError: Bool) -> String {
        isError ? DSIcon.errorBadge : "checkmark.circle.fill"
    }

    private var tint: Color {
        isError ? DSColor.statusError : DSColor.statusCompleted
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: Self.iconName(isError: isError))
                .foregroundStyle(tint)
            Text(message)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.m)
        .frame(minHeight: DSTouch.minSize)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isError ? "エラー: \(message)" : message))
    }
}

#if DEBUG
#Preview("DSResultBanner") {
    VStack(spacing: DSSpacing.m) {
        DSResultBanner(message: "セッションを開始しました", isError: false)
        DSResultBanner(message: "接続に失敗しました", isError: true)
    }
    .padding(DSSpacing.l)
}
#endif
