/// 設定のテーマ候補見本。渡された AppTheme の既存 RGB と既存不透明度だけを写す。
/// 選択状態・保存・プロセスは参照しない。
public struct ThemePreviewModel: Equatable, Sendable {
    public struct Layer: Equatable, Sendable {
        public let rgb: RGB
        public let opacity: Double

        public init(rgb: RGB, opacity: Double) {
            self.rgb = rgb
            self.opacity = opacity
        }
    }

    public let themeID: String
    public let themeName: String
    public let appLabel: String
    public let terminalLabel: String
    public let bodyText: String
    public let selectedRowText: String
    public let inputText: String
    public let background: RGB
    public let textPrimary: RGB
    public let currentMarker: RGB
    public let selectedRow: Layer
    public let inputFill: Layer
    public let inputBorder: Layer
    public let terminalSwatches: [RGB]

    public static func make(theme: AppTheme) -> ThemePreviewModel {
        // 実画面と同じ値（DSColor.composerBorder = textPrimary 14%、fillSelected = --sel）。
        let isDark = theme.background.relativeLuminance < 0.5
        let inputBorder = Layer(rgb: theme.textPrimary, opacity: 0.14)

        return ThemePreviewModel(
            themeID: theme.id,
            themeName: theme.name,
            appLabel: "アプリ外観",
            terminalLabel: "ターミナル配色",
            bodyText: "本文の見本",
            selectedRowText: "現在の会話",
            inputText: "メッセージを入力",
            background: theme.background,
            textPrimary: theme.textPrimary,
            currentMarker: theme.accent,
            selectedRow: Layer(rgb: theme.textPrimary, opacity: AppTheme.sidebarSelectedOpacity(isDark: isDark)),
            inputFill: Layer(rgb: RGB(255, 255, 255), opacity: 0.04),
            inputBorder: inputBorder,
            terminalSwatches: [theme.terminalBackground] + Array(theme.ansi[1...6]) + [theme.terminalForeground]
        )
    }
}
