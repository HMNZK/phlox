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
    func lightened(_ amount: Int) -> RGB {
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

    public var preferredColorScheme: ColorScheme? {
        background.relativeLuminance >= 0.5 ? .light : .dark
    }
}

extension AppTheme {
    private static let claudeCoral = RGB(0xD9, 0x77, 0x57)

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
        let textPrimary = fg.grayscale
        let isLight = background.relativeLuminance >= 0.5
        let surface = isLight ? background.darkened(7) : background.lightened(7)
        let surfaceElevated = isLight ? background.darkened(14) : background.lightened(14)
        // Palette 固有の accent はターミナル由来テーマの互換入力として受け取り、UI accent は共有色に統一する。
        return AppTheme(
            id: id,
            name: name,
            background: background,
            surface: surface,
            surfaceElevated: surfaceElevated,
            textPrimary: textPrimary,
            textSecondary: textPrimary.mixed(background, 0.42),
            textTertiary: textPrimary.mixed(background, 0.62),
            accent: Self.claudeCoral,
            statusRunning: ansi[2],
            statusAwaiting: ansi[3],
            statusError: ansi[1],
            statusCompleted: ansi[10],
            statusStarting: textPrimary.mixed(background, 0.38),
            statusIdle: textPrimary.mixed(background, 0.52),
            attention: ansi[9],
            agentColors: [
                .claudeCode: ansi[3],
                .codex: ansi[4],
                .cursor: textPrimary.mixed(background, 0.35),
            ],
            terminalBackground: bg,
            terminalForeground: fg,
            ansi: ansi
        )
    }
}

// MARK: - テーマ定義

extension AppTheme {
    /// 既定テーマ。UI chrome はニュートラルグレー、アクセントは Claude コーラルに統一する。
    public static let phlox = AppTheme(
        id: "phlox",
        name: "Phlox",
        background: RGB(0x11, 0x11, 0x11),
        surface: RGB(0x18, 0x18, 0x18),
        surfaceElevated: RGB(0x20, 0x20, 0x20),
        textPrimary: RGB(0xE6, 0xE6, 0xE6),
        textSecondary: RGB(0x96, 0x96, 0x96),
        textTertiary: RGB(0x6C, 0x6C, 0x6C),
        accent: claudeCoral,
        statusRunning: RGB(0x34, 0xD3, 0x99),
        statusAwaiting: RGB(0xFB, 0xBF, 0x24),
        statusError: RGB(0xEF, 0x44, 0x44),
        statusCompleted: RGB(0x6E, 0xE7, 0xB7),
        statusStarting: RGB(0xA3, 0xA3, 0xA3),
        statusIdle: RGB(0x86, 0x86, 0x86),
        attention: claudeCoral,
        agentColors: [
            .claudeCode: RGB(0xE0, 0xAF, 0x68),
            .codex: RGB(0x7C, 0x8C, 0xFF),
            .cursor: RGB(0xB8, 0xB8, 0xB8),
        ],
        terminalBackground: RGB(0x0E, 0x0E, 0x0E),
        terminalForeground: RGB(0xD6, 0xD6, 0xD6),
        ansi: [
            RGB(0x0D, 0x0D, 0x0D), RGB(0xEF, 0x44, 0x44), RGB(0x34, 0xD3, 0x99), RGB(0xFB, 0xBF, 0x24),
            RGB(0x60, 0xA5, 0xFA), RGB(0xD9, 0x77, 0x57), RGB(0x38, 0xBD, 0xF8), RGB(0xE5, 0xE5, 0xE5),
            RGB(0x3F, 0x3F, 0x46), RGB(0xFB, 0x71, 0x71), RGB(0x6E, 0xE7, 0xB7), RGB(0xFD, 0xE6, 0x8A),
            RGB(0x93, 0xC5, 0xFD), RGB(0xFB, 0xA8, 0x8A), RGB(0x7D, 0xD3, 0xFC), RGB(0xFF, 0xFF, 0xFF),
        ]
    )

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

    /// Phlox Light — iOS カンプのブランド紫・ピンクに調和する明色テーマ。task-5 がライト外観に割り当てる。
    public static let phloxLight = AppTheme.fromPalette(
        id: "phlox-light",
        name: "Phlox Light",
        bg: RGB(0xF7, 0xF7, 0xF9),
        fg: RGB(0x1E, 0x1B, 0x2E),
        ansi: [
            RGB(0x1E, 0x1B, 0x2E), RGB(0xDC, 0x26, 0x26), RGB(0x05, 0x96, 0x69), RGB(0xD9, 0x77, 0x06),
            RGB(0x7C, 0x3A, 0xED), RGB(0xDB, 0x27, 0x77), RGB(0x08, 0x91, 0xB2), RGB(0x6B, 0x72, 0x80),
            RGB(0x9C, 0xA3, 0xAF), RGB(0xEF, 0x44, 0x44), RGB(0x10, 0xB9, 0x81), RGB(0xF5, 0x9E, 0x0B),
            RGB(0x8B, 0x5C, 0xF6), RGB(0xEC, 0x48, 0x99), RGB(0x06, 0xB6, 0xD4), RGB(0x94, 0xA3, 0xB8),
        ],
        accent: claudeCoral
    )
}

/// 起動時にアクティブテーマを解決して保持するストア。
/// 変更は再起動で反映する（DSColor / ターミナルが起動時にこの値を読む）。
public enum ThemeStore {
    public static let themeKey = "phlox.theme"

    /// 選択肢として提示する全テーマ。先頭が既定の Phlox。
    public static let all: [AppTheme] = [
        .phlox, .tokyoNight, .dracula, .catppuccinMocha, .gruvboxDark, .nord,
        .catppuccinLatte, .solarizedLight, .githubLight, .phloxLight,
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
