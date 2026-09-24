import SwiftUI
import AgentDomain
import os

/// 0–255 の RGB 値。SwiftUI Color とターミナル用の生値の双方に変換でき、簡単な導出計算もできる。
public struct RGB: Sendable, Equatable {
    public let r: Int
    public let g: Int
    public let b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ rgb: AgentRGB) {
        self.init(rgb.r, rgb.g, rgb.b)
    }

    public var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// 各チャンネルを一律に持ち上げる（暗い面のレイヤー段差づくり用）。
    public func lightened(_ amount: Int) -> RGB {
        RGB(min(255, r + amount), min(255, g + amount), min(255, b + amount))
    }

    /// 各チャンネルを一律に沈める（明るい面のレイヤー段差づくり用）。
    func darkened(_ amount: Int) -> RGB {
        RGB(max(0, r - amount), max(0, g - amount), max(0, b - amount))
    }

    /// other 方向へ t(0..1) だけ線形補間する（テキストを背景へ沈める等）。
    func mixed(_ other: RGB, _ t: Double) -> RGB {
        func m(_ a: Int, _ b: Int) -> Int { Int((Double(a) * (1 - t) + Double(b) * t).rounded()) }
        return RGB(m(r, other.r), m(g, other.g), m(b, other.b))
    }

    var grayscale: RGB {
        let gray = Int((Double(r) * 0.2126 + Double(g) * 0.7152 + Double(b) * 0.0722).rounded())
        return RGB(gray, gray, gray)
    }

    var relativeLuminance: Double {
        func linear(_ value: Int) -> Double {
            let channel = Double(value) / 255
            if channel <= 0.03928 {
                return channel / 12.92
            }
            return pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// アプリ全体（UI chrome ＋ ターミナル）のカラースキーマ。
public struct AppTheme: Sendable, Identifiable {
    public let id: String
    public let name: String

    // 背景ランプ
    public let background: RGB
    public let surface: RGB
    public let surfaceElevated: RGB
    // テキスト
    public let textPrimary: RGB
    public let textSecondary: RGB
    public let textTertiary: RGB
    // アクセント / ステータス
    public let accent: RGB
    public let statusRunning: RGB
    public let statusAwaiting: RGB
    public let statusError: RGB
    public let statusCompleted: RGB
    public let statusStarting: RGB
    public let statusIdle: RGB
    public let attention: RGB
    // CLI バッジ
    public let agentColors: [AgentKind: RGB]
    // ターミナル
    public let terminalBackground: RGB
    public let terminalForeground: RGB
    public let ansi: [RGB] // 16
    /// 再設計で増えた面・文字・対応待ち 4 状態の色（12 Design System）。
    public let palette: DesignPalette

    public var preferredColorScheme: ColorScheme? {
        background.relativeLuminance >= 0.5 ? .light : .dark
    }
}

extension AppTheme {
    private static let claudeCoral = RGB(0xD9, 0x77, 0x57)

    // MARK: - サイドバー4面の不透明度（Tokens.swift の fillSubtle/fillSelected/idleHighlight と共有する唯一の定義）

    /// hover 面（`DSColor.fillSubtle`。12 Design System `--hov`: ダーク 0.06 / ライト 0.05）。
    static func sidebarHoverOpacity(isDark: Bool) -> Double { isDark ? 0.06 : 0.05 }
    /// 選択面（`DSColor.fillSelected`。`--sel`: ダーク 0.09 / ライト 0.075）。
    static func sidebarSelectedOpacity(isDark: Bool) -> Double { isDark ? 0.09 : 0.075 }
    /// attention 面（`DSColor.idleHighlight`）。
    static let sidebarAttentionOpacity = 0.22

    /// 補助文字コントラストの実装目標（WCAG 4.5 に丸め・実測残差の余裕を足した値）。
    private static let minimumAuxiliaryContrast = 4.56
    private static let secondaryIdealMix = 0.42
    private static let tertiaryIdealMix = 0.62

    /// サイドバーで実際に重なる4面（基底／hover／選択／attention）。優先順の2枚重ねは作らない。
    private static func sidebarFaces(background: RGB, hoverOverlay: RGB, attention: RGB) -> [RGB] {
        let isDark = background.relativeLuminance < 0.5
        return [
            background,
            background.mixed(hoverOverlay, sidebarHoverOpacity(isDark: isDark)),
            background.mixed(hoverOverlay, sidebarSelectedOpacity(isDark: isDark)),
            background.mixed(attention, sidebarAttentionOpacity),
        ]
    }

    private static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = a.relativeLuminance > b.relativeLuminance
            ? (a.relativeLuminance, b.relativeLuminance)
            : (b.relativeLuminance, a.relativeLuminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func worstContrast(_ text: RGB, faces: [RGB]) -> Double {
        faces.map { contrastRatio(text, $0) }.min() ?? 0
    }

    /// 主文字を background へ混ぜる比率を、4 面の最悪コントラストが `minimumAuxiliaryContrast` を
    /// 下回らない範囲でクランプする（理想上限は `idealMix`）。
    private static func clampedMixRatio(primary: RGB, background: RGB, attention: RGB, idealMix: Double) -> Double {
        func satisfies(_ t: Double) -> Bool {
            let candidate = primary.mixed(background, t)
            let faces = sidebarFaces(background: background, hoverOverlay: primary, attention: attention)
            return worstContrast(candidate, faces: faces) >= minimumAuxiliaryContrast
        }
        guard !satisfies(idealMix) else { return idealMix }
        var lo = 0.0
        var hi = idealMix
        for _ in 0 ..< 40 {
            let mid = (lo + hi) / 2
            if satisfies(mid) { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// 主文字自体が最悪面で `minimumAuxiliaryContrast` を割るとき（Solarized Light）だけ最小補正を行う。
    /// 補正先（黒/白）は輝度しきい値で決めず、黒・白それぞれへ寄せた場合の最悪面比を実際に比較し、
    /// 大きい方を採る（2026-09-12 独立レビュー L-1）。
    private static func correctedPrimary(_ primary: RGB, background: RGB, attention: RGB) -> RGB {
        let faces = sidebarFaces(background: background, hoverOverlay: primary, attention: attention)
        guard worstContrast(primary, faces: faces) < minimumAuxiliaryContrast else { return primary }
        let black = RGB(0, 0, 0)
        let white = RGB(255, 255, 255)
        let blackWorst = worstContrast(black, faces: sidebarFaces(background: background, hoverOverlay: black, attention: attention))
        let whiteWorst = worstContrast(white, faces: sidebarFaces(background: background, hoverOverlay: white, attention: attention))
        let target = blackWorst >= whiteWorst ? black : white
        func satisfies(_ t: Double) -> Bool {
            let candidate = primary.mixed(target, t)
            let faces = sidebarFaces(background: background, hoverOverlay: candidate, attention: attention)
            return worstContrast(candidate, faces: faces) >= minimumAuxiliaryContrast
        }
        // t=1（target 自体）でも満たせない場合（現行10テーマでは発生しない）は、
        // 到達可能な最善として target をそのまま返す。
        guard satisfies(1.0) else { return target }
        var lo = 0.0
        var hi = 1.0
        for _ in 0 ..< 40 {
            let mid = (lo + hi) / 2
            if satisfies(mid) { hi = mid } else { lo = mid }
        }
        return primary.mixed(target, hi)
    }

    /// 補助文字（secondary/tertiary）を主文字から導出する唯一の入口。
    /// クランプは tertiary にだけ適用し、secondary は tertiary の比率を理想比（42/62）で按分する
    /// （2026-09-12 独立レビュー H-1: 両役を同じ上限へクランプすると、暗色テーマでも上限が 0.42 に届かず
    /// secondary == tertiary に縮退する）。
    private static func derivedAuxiliaryText(
        primary: RGB,
        background: RGB,
        attention: RGB
    ) -> (secondary: RGB, tertiary: RGB) {
        let tertiaryRatio = clampedMixRatio(primary: primary, background: background, attention: attention, idealMix: tertiaryIdealMix)
        let secondaryRatio = min(secondaryIdealMix, tertiaryRatio * (secondaryIdealMix / tertiaryIdealMix))
        return (primary.mixed(background, secondaryRatio), primary.mixed(background, tertiaryRatio))
    }

    /// 標準的なターミナルパレット(bg/fg/ANSI16)から UI トークンを導出してテーマを作る。
    /// 人気テーマを少ない記述で取り込むためのファクトリ。
    static func fromPalette(
        id: String,
        name: String,
        bg: RGB,
        fg: RGB,
        ansi: [RGB],
        accent _: RGB
    ) -> AppTheme {
        let background = bg.grayscale
        let rawTextPrimary = fg.grayscale
        let attentionColor = ansi[9]
        let textPrimary = correctedPrimary(rawTextPrimary, background: background, attention: attentionColor)
        let isLight = background.relativeLuminance >= 0.5
        let surface = isLight ? background.darkened(7) : background.lightened(7)
        let surfaceElevated = isLight ? background.darkened(14) : background.lightened(14)
        let auxiliaryText = derivedAuxiliaryText(primary: textPrimary, background: background, attention: attentionColor)
        // Palette 固有の accent はターミナル由来テーマの互換入力として受け取り、UI accent は共有色に統一する。
        return AppTheme(
            id: id,
            name: name,
            background: background,
            surface: surface,
            surfaceElevated: surfaceElevated,
            textPrimary: textPrimary,
            textSecondary: auxiliaryText.secondary,
            textTertiary: auxiliaryText.tertiary,
            accent: Self.claudeCoral,
            statusRunning: ansi[2],
            statusAwaiting: ansi[3],
            statusError: ansi[1],
            statusCompleted: ansi[10],
            statusStarting: rawTextPrimary.mixed(background, 0.38),
            statusIdle: rawTextPrimary.mixed(background, 0.52),
            attention: ansi[9],
            agentColors: [
                .claudeCode: ansi[3],
                .codex: ansi[4],
                .cursor: rawTextPrimary.mixed(background, 0.35),
            ],
            terminalBackground: bg,
            terminalForeground: fg,
            ansi: ansi,
            palette: .derived(background: background, textPrimary: textPrimary, ansi: ansi)
        )
    }

    /// Phlox / Phlox Light を palette の確定値から組み立てる。状態色（旧トークン）は
    /// 対応待ちの記号色に揃え、実行中・完了などの旧色は現行値を保つ（各画面の置換で順次使わなくなる）。
    static func designTheme(
        id: String, name: String, palette: DesignPalette,
        primary: RGB, secondary: RGB, tertiary: RGB,
        statusRunning: RGB, statusCompleted: RGB, statusStarting: RGB, statusIdle: RGB,
        agentColors: [AgentKind: RGB],
        terminalBackground: RGB, terminalForeground: RGB, ansi: [RGB]
    ) -> AppTheme {
        let attention = claudeCoral
        return AppTheme(
            id: id,
            name: name,
            background: palette.window,
            surface: palette.panel,
            surfaceElevated: palette.popover,
            textPrimary: primary,
            // 既定の 2 テーマは文字もデザインの確定値をそのまま使う（コントラスト補正をしない。2026-09-24 決定）。
            textSecondary: secondary,
            textTertiary: tertiary,
            accent: palette.accent,
            statusRunning: statusRunning,
            statusAwaiting: palette.approval.mark,
            statusError: palette.error.mark,
            statusCompleted: statusCompleted,
            statusStarting: statusStarting,
            statusIdle: statusIdle,
            attention: attention,
            agentColors: agentColors,
            terminalBackground: terminalBackground,
            terminalForeground: terminalForeground,
            ansi: ansi,
            palette: palette
        )
    }
}

// MARK: - テーマ定義

extension AppTheme {
    /// 既定テーマ。UI chrome はニュートラルグレー、アクセントは Claude コーラルに統一する。
    /// textSecondary/textTertiary は固定 RGB 直書きをやめ、fromPalette と共有する導出関数の呼び出しへ
    /// 置き換える（主文字 0xE6 は最悪面でも十分読めるため、そのまま変えない）。
    public static let phlox: AppTheme = designTheme(
        id: "phlox",
        name: "Phlox",
        palette: .phloxDark,
        primary: RGB(0xF2, 0xF2, 0xF4),
        secondary: RGB(0xAB, 0xAB, 0xB1),
        tertiary: RGB(0x8E, 0x8E, 0x94),
        statusRunning: RGB(0x34, 0xD3, 0x99),
        statusCompleted: RGB(0x6E, 0xE7, 0xB7),
        statusStarting: RGB(0xA3, 0xA3, 0xA3),
        statusIdle: RGB(0x86, 0x86, 0x86),
        agentColors: [
            .claudeCode: RGB(0xE0, 0xAF, 0x68),
            .codex: RGB(0x7C, 0x8C, 0xFF),
            .cursor: RGB(0xB8, 0xB8, 0xB8),
        ],
        terminalBackground: RGB(0x14, 0x14, 0x16),
        terminalForeground: RGB(0xD6, 0xD6, 0xD6),
        ansi: phloxTerminalANSI
    )

    /// Phlox / Phlox Light の端末 16 色。端末はテーマの明暗によらず暗い面（12 Design System）。
    static let phloxTerminalANSI: [RGB] = [
            RGB(0x0D, 0x0D, 0x0D), RGB(0xEF, 0x44, 0x44), RGB(0x34, 0xD3, 0x99), RGB(0xFB, 0xBF, 0x24),
            RGB(0x60, 0xA5, 0xFA), RGB(0xD9, 0x77, 0x57), RGB(0x38, 0xBD, 0xF8), RGB(0xE5, 0xE5, 0xE5),
            RGB(0x3F, 0x3F, 0x46), RGB(0xFB, 0x71, 0x71), RGB(0x6E, 0xE7, 0xB7), RGB(0xFD, 0xE6, 0x8A),
            RGB(0x93, 0xC5, 0xFD), RGB(0xFB, 0xA8, 0x8A), RGB(0x7D, 0xD3, 0xFC), RGB(0xFF, 0xFF, 0xFF),
    ]

    /// Tokyo Night（enkia）
    public static let tokyoNight = AppTheme.fromPalette(
        id: "tokyo-night",
        name: "Tokyo Night",
        bg: RGB(0x1A, 0x1B, 0x26),
        fg: RGB(0xC0, 0xCA, 0xF5),
        ansi: [
            RGB(0x15, 0x16, 0x1E), RGB(0xF7, 0x76, 0x8E), RGB(0x9E, 0xCE, 0x6A), RGB(0xE0, 0xAF, 0x68),
            RGB(0x7A, 0xA2, 0xF7), RGB(0xBB, 0x9A, 0xF7), RGB(0x7D, 0xCF, 0xFF), RGB(0xA9, 0xB1, 0xD6),
            RGB(0x41, 0x48, 0x68), RGB(0xF7, 0x76, 0x8E), RGB(0x9E, 0xCE, 0x6A), RGB(0xE0, 0xAF, 0x68),
            RGB(0x7A, 0xA2, 0xF7), RGB(0xBB, 0x9A, 0xF7), RGB(0x7D, 0xCF, 0xFF), RGB(0xC0, 0xCA, 0xF5),
        ],
        accent: RGB(0xBB, 0x9A, 0xF7)
    )

    /// Dracula
    public static let dracula = AppTheme.fromPalette(
        id: "dracula",
        name: "Dracula",
        bg: RGB(0x28, 0x2A, 0x36),
        fg: RGB(0xF8, 0xF8, 0xF2),
        ansi: [
            RGB(0x21, 0x22, 0x2C), RGB(0xFF, 0x55, 0x55), RGB(0x50, 0xFA, 0x7B), RGB(0xF1, 0xFA, 0x8C),
            RGB(0xBD, 0x93, 0xF9), RGB(0xFF, 0x79, 0xC6), RGB(0x8B, 0xE9, 0xFD), RGB(0xF8, 0xF8, 0xF2),
            RGB(0x62, 0x72, 0xA4), RGB(0xFF, 0x6E, 0x6E), RGB(0x69, 0xFF, 0x94), RGB(0xFF, 0xFF, 0xA5),
            RGB(0xD6, 0xAC, 0xFF), RGB(0xFF, 0x92, 0xDF), RGB(0xA4, 0xFF, 0xFF), RGB(0xFF, 0xFF, 0xFF),
        ],
        accent: RGB(0xBD, 0x93, 0xF9)
    )

    /// Catppuccin Mocha
    public static let catppuccinMocha = AppTheme.fromPalette(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        bg: RGB(0x1E, 0x1E, 0x2E),
        fg: RGB(0xCD, 0xD6, 0xF4),
        ansi: [
            RGB(0x45, 0x47, 0x5A), RGB(0xF3, 0x8B, 0xA8), RGB(0xA6, 0xE3, 0xA1), RGB(0xF9, 0xE2, 0xAF),
            RGB(0x89, 0xB4, 0xFA), RGB(0xF5, 0xC2, 0xE7), RGB(0x94, 0xE2, 0xD5), RGB(0xBA, 0xC2, 0xDE),
            RGB(0x58, 0x5B, 0x70), RGB(0xF3, 0x8B, 0xA8), RGB(0xA6, 0xE3, 0xA1), RGB(0xF9, 0xE2, 0xAF),
            RGB(0x89, 0xB4, 0xFA), RGB(0xF5, 0xC2, 0xE7), RGB(0x94, 0xE2, 0xD5), RGB(0xA6, 0xAD, 0xC8),
        ],
        accent: RGB(0xCB, 0xA6, 0xF7)
    )

    /// Gruvbox Dark
    public static let gruvboxDark = AppTheme.fromPalette(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        bg: RGB(0x28, 0x28, 0x28),
        fg: RGB(0xEB, 0xDB, 0xB2),
        ansi: [
            RGB(0x28, 0x28, 0x28), RGB(0xCC, 0x24, 0x1D), RGB(0x98, 0x97, 0x1A), RGB(0xD7, 0x99, 0x21),
            RGB(0x45, 0x85, 0x88), RGB(0xB1, 0x62, 0x86), RGB(0x68, 0x9D, 0x6A), RGB(0xA8, 0x99, 0x84),
            RGB(0x92, 0x83, 0x74), RGB(0xFB, 0x49, 0x34), RGB(0xB8, 0xBB, 0x26), RGB(0xFA, 0xBD, 0x2F),
            RGB(0x83, 0xA5, 0x98), RGB(0xD3, 0x86, 0x9B), RGB(0x8E, 0xC0, 0x7C), RGB(0xEB, 0xDB, 0xB2),
        ],
        accent: RGB(0xD3, 0x86, 0x9B)
    )

    /// Nord
    public static let nord = AppTheme.fromPalette(
        id: "nord",
        name: "Nord",
        bg: RGB(0x2E, 0x34, 0x40),
        fg: RGB(0xD8, 0xDE, 0xE9),
        ansi: [
            RGB(0x3B, 0x42, 0x52), RGB(0xBF, 0x61, 0x6A), RGB(0xA3, 0xBE, 0x8C), RGB(0xEB, 0xCB, 0x8B),
            RGB(0x81, 0xA1, 0xC1), RGB(0xB4, 0x8E, 0xAD), RGB(0x88, 0xC0, 0xD0), RGB(0xE5, 0xE9, 0xF0),
            RGB(0x4C, 0x56, 0x6A), RGB(0xBF, 0x61, 0x6A), RGB(0xA3, 0xBE, 0x8C), RGB(0xEB, 0xCB, 0x8B),
            RGB(0x81, 0xA1, 0xC1), RGB(0xB4, 0x8E, 0xAD), RGB(0x8F, 0xBC, 0xBB), RGB(0xEC, 0xEF, 0xF4),
        ],
        accent: RGB(0x88, 0xC0, 0xD0)
    )

    /// Catppuccin Latte
    public static let catppuccinLatte = AppTheme.fromPalette(
        id: "catppuccin-latte",
        name: "Catppuccin Latte",
        bg: RGB(0xEF, 0xF1, 0xF5),
        fg: RGB(0x4C, 0x4F, 0x69),
        ansi: [
            RGB(0x5C, 0x5F, 0x77), RGB(0xD2, 0x0F, 0x39), RGB(0x40, 0xA0, 0x2B), RGB(0xDF, 0x8E, 0x1D),
            RGB(0x1E, 0x66, 0xF5), RGB(0xEA, 0x76, 0xCB), RGB(0x17, 0x92, 0x99), RGB(0xAC, 0xB0, 0xBE),
            RGB(0x6C, 0x6F, 0x85), RGB(0xD2, 0x0F, 0x39), RGB(0x40, 0xA0, 0x2B), RGB(0xDF, 0x8E, 0x1D),
            RGB(0x1E, 0x66, 0xF5), RGB(0xEA, 0x76, 0xCB), RGB(0x17, 0x92, 0x99), RGB(0xBC, 0xC0, 0xCC),
        ],
        accent: claudeCoral
    )

    /// Solarized Light
    public static let solarizedLight = AppTheme.fromPalette(
        id: "solarized-light",
        name: "Solarized Light",
        bg: RGB(0xFD, 0xF6, 0xE3),
        fg: RGB(0x65, 0x7B, 0x83),
        ansi: [
            RGB(0x07, 0x36, 0x42), RGB(0xDC, 0x32, 0x2F), RGB(0x85, 0x99, 0x00), RGB(0xB5, 0x89, 0x00),
            RGB(0x26, 0x8B, 0xD2), RGB(0xD3, 0x36, 0x82), RGB(0x2A, 0xA1, 0x98), RGB(0xEE, 0xE8, 0xD5),
            RGB(0x00, 0x2B, 0x36), RGB(0xCB, 0x4B, 0x16), RGB(0x58, 0x6E, 0x75), RGB(0x65, 0x7B, 0x83),
            RGB(0x83, 0x94, 0x96), RGB(0x6C, 0x71, 0xC4), RGB(0x93, 0xA1, 0xA1), RGB(0xFD, 0xF6, 0xE3),
        ],
        accent: claudeCoral
    )

    /// GitHub Light
    public static let githubLight = AppTheme.fromPalette(
        id: "github-light",
        name: "GitHub Light",
        bg: RGB(0xFF, 0xFF, 0xFF),
        fg: RGB(0x24, 0x29, 0x2F),
        ansi: [
            RGB(0x24, 0x29, 0x2F), RGB(0xCF, 0x22, 0x2E), RGB(0x11, 0x63, 0x29), RGB(0x4D, 0x2D, 0x00),
            RGB(0x09, 0x69, 0xDA), RGB(0x82, 0x50, 0xDF), RGB(0x1B, 0x7C, 0x83), RGB(0x6E, 0x77, 0x81),
            RGB(0x57, 0x60, 0x6A), RGB(0xA4, 0x0E, 0x26), RGB(0x1A, 0x7F, 0x37), RGB(0x9A, 0x67, 0x00),
            RGB(0x21, 0x82, 0xE8), RGB(0xA4, 0x75, 0xF9), RGB(0x31, 0x8E, 0x95), RGB(0x8C, 0x95, 0x9F),
        ],
        accent: claudeCoral
    )

    /// Phlox Light — 再設計の明色の既定テーマ（12 Design System の確定値）。
    /// 端末はライトでも暗い面 #1B1B1D（Phlox と同じ 16 色）。
    public static let phloxLight: AppTheme = {
        let palette = DesignPalette.phloxLight
        let primary = RGB(0x1D, 0x1D, 0x1F)
        let ansi: [RGB] = [
            RGB(0x1E, 0x1B, 0x2E), RGB(0xDC, 0x26, 0x26), RGB(0x05, 0x96, 0x69), RGB(0xD9, 0x77, 0x06),
            RGB(0x7C, 0x3A, 0xED), RGB(0xDB, 0x27, 0x77), RGB(0x08, 0x91, 0xB2), RGB(0x6B, 0x72, 0x80),
            RGB(0x9C, 0xA3, 0xAF), RGB(0xEF, 0x44, 0x44), RGB(0x10, 0xB9, 0x81), RGB(0xF5, 0x9E, 0x0B),
            RGB(0x8B, 0x5C, 0xF6), RGB(0xEC, 0x48, 0x99), RGB(0x06, 0xB6, 0xD4), RGB(0x94, 0xA3, 0xB8),
        ]
        return designTheme(
            id: "phlox-light",
            name: "Phlox Light",
            palette: palette,
            primary: primary,
            secondary: RGB(0x5B, 0x5B, 0x60),
            tertiary: RGB(0x75, 0x75, 0x7B),
            statusRunning: ansi[2],
            statusCompleted: ansi[10],
            statusStarting: primary.mixed(palette.window, 0.38),
            statusIdle: primary.mixed(palette.window, 0.52),
            agentColors: [
                .claudeCode: ansi[3],
                .codex: ansi[4],
                .cursor: primary.mixed(palette.window, 0.35),
            ],
            terminalBackground: RGB(0x1B, 0x1B, 0x1D),
            terminalForeground: RGB(0xD6, 0xD6, 0xD6),
            ansi: phloxTerminalANSI
        )
    }()
}

/// アクティブテーマを解決するストア。変更は `ThemeChangeSignal` 経由で描画中の View へ即時に反映する。
public enum ThemeStore {
    public static let themeKey = "phlox.theme"

    /// 選択肢として提示する全テーマ。先頭が既定の Phlox。
    public static let all: [AppTheme] = [
        .phlox, .phloxLight, .tokyoNight, .dracula, .catppuccinMocha, .gruvboxDark, .nord,
        .catppuccinLatte, .solarizedLight, .githubLight,
    ]

    /// 起動時 register(defaults:) 用。
    public static var defaultsDictionary: [String: Any] { [themeKey: AppTheme.phlox.id] }

    /// 現在アクティブなテーマ。選択値（UserDefaults）を都度解決するため、設定変更が即時に反映できる。
    public static var active: AppTheme {
        active(in: .standard)
    }

    /// `active` の UserDefaults 注入版。未知の id・未設定はいずれも既定の Phlox へフォールバックする。
    public static func active(in defaults: UserDefaults) -> AppTheme {
        resolved(in: defaults).theme
    }

    // MARK: - 解決結果のキャッシュ

    /// 選択 id に対する解決結果。id が変わらない限り使い回し、テーマ構造体の線形探索を
    /// 描画パスの都度実行から外す（P7）。
    private struct Resolved: Sendable {
        let selectedID: String?
        let theme: AppTheme
    }

    /// 直近の解決結果。選択 id（UserDefaults の生値）が一致する間だけ有効で、
    /// id の変化＝テーマ変更で作り直す。解決は id に対して決定的なので、
    /// 注入された UserDefaults が異なっても同じ id なら同じ結果を共有できる。
    private static let cache = OSAllocatedUnfairLock<Resolved?>(initialState: nil)

    private static func resolved(in defaults: UserDefaults) -> Resolved {
        // 描画中（メインスレッド）の読み出しを Observation の追跡対象にする。これで DSColor を
        // 読んだ View はテーマ変更で必ず描き直される（View ごとの @AppStorage 購読に頼らない）。
        if Thread.isMainThread { ThemeChangeSignal.shared.track() }
        let selectedID = defaults.string(forKey: themeKey)
        if let cached = cache.withLock({ $0 }), cached.selectedID == selectedID {
            return cached
        }
        let theme = all.first { $0.id == selectedID } ?? .phlox
        let resolved = Resolved(
            selectedID: selectedID,
            theme: theme
        )
        cache.withLock { $0 = resolved }
        return resolved
    }
}

/// テーマの選択値が変わったことを SwiftUI へ知らせる信号。`ThemeStore` の読み出しが
/// `revision` を読むので、色を使った View の body が Observation に登録される。
@Observable
final class ThemeChangeSignal: @unchecked Sendable {
    static let shared = ThemeChangeSignal(defaults: .standard)

    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastID: String?
    @ObservationIgnored private var token: NSObjectProtocol?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        lastID = defaults.string(forKey: ThemeStore.themeKey)
        token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // queue: .main だと投稿側のスレッドがメインでの実行完了まで待つ。書き込み元を止めないよう非同期で渡す。
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func track() {
        _ = revision
    }

    private func refresh() {
        let id = defaults.string(forKey: ThemeStore.themeKey)
        guard id != lastID else { return }
        lastID = id
        revision += 1
    }
}
