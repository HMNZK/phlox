// task-13（UI-01）の受け入れテスト。
//
// ベースライン（実装前）での red 理由: 10 テーマの補助文字（textSecondary / textTertiary）は
// `AppTheme.fromPalette` が主文字を背景へ 42% / 62% 混ぜて導出しており（Phlox 既定は固定 RGB 0x96 / 0x6C）、
// サイドバーで実際に重なる 4 面（基底・hover・選択・注意）に対して WCAG 1.4.3 の 4.5:1 に届かない
// （`docs/agent-output/ui01-contrast-investigation-20260908.md`: 三次色 30 組すべて 4.5 未満、
// 二次色 23 組が 4.5 未満、Solarized Light は主文字も注意面で 3.08）。本ファイルはアサーション失敗で red になる。
//
// 期待値の出所:
//   - 4 面の合成は製品契約の source-over（`DSColor.fillSubtle`=主文字 5% / `fillSelected`=主文字 10% /
//     `idleHighlight`=attention 22%、サイドバー基底は `DSColor.background`）。2026-09-08 の Dracula 実サイドバー
//     測色（`docs/agent-output/ui01-pixel-method-investigation.md`）で、基底・選択・注意の 3 面が
//     この sRGB 符号値上の source-over に ±1/255 で一致することを確認済み。hover 面・明色テーマの実描画は未実測。
//   - 比率は WCAG 相対輝度式を本ファイルに自前実装し、丸め前の Double で判定する。
//   - 検査対象の役割: サイドバーの見出し（Projects / その他）・経過時間・空文字名の短 ID = tertiary、
//     選択フィルタ等の補助 = secondary、通常名・空白名の短 ID = primary。
//
// 実装側の色補正処理はここにコピーしない。`ThemeStore.all` の実 RGB から都度計算するため、
// テーマの追加・色変更にも追従する。

import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("task-13: sidebar text contrast", .serialized)
struct AcceptanceSidebarTextContrastTests {
    // MARK: - 契約定数（製品の DSColor と一致することを overlayTokensMatchContract で別途検査する）

    private static let hoverAlpha = 0.05
    private static let selectedAlpha = 0.10
    private static let attentionAlpha = 0.22
    private static let minimumRatio = 4.5

    private static let knownThemeIDs = [
        "phlox", "tokyo-night", "dracula", "catppuccin-mocha", "gruvbox-dark", "nord",
        "catppuccin-latte", "solarized-light", "github-light", "phlox-light",
    ]

    // MARK: - 数値モデル

    private struct Face {
        let name: String
        let rgb: (Double, Double, Double)
    }

    /// source-over（sRGB 符号値上・丸めなし）。
    private func over(_ backdrop: RGB, _ overlay: RGB, alpha: Double) -> (Double, Double, Double) {
        func m(_ b: Int, _ f: Int) -> Double { Double(b) * (1 - alpha) + Double(f) * alpha }
        return (m(backdrop.r, overlay.r), m(backdrop.g, overlay.g), m(backdrop.b, overlay.b))
    }

    /// サイドバー行・見出しの背景 4 面。優先順（選択→hover→注意→基底）に従い 2 枚重ねは作らない。
    private func sidebarFaces(_ theme: AppTheme) -> [Face] {
        let bg = theme.background
        return [
            Face(name: "base", rgb: (Double(bg.r), Double(bg.g), Double(bg.b))),
            Face(name: "hover", rgb: over(bg, theme.textPrimary, alpha: Self.hoverAlpha)),
            Face(name: "selected", rgb: over(bg, theme.textPrimary, alpha: Self.selectedAlpha)),
            Face(name: "attention", rgb: over(bg, theme.attention, alpha: Self.attentionAlpha)),
        ]
    }

    private func linear(_ channel: Double) -> Double {
        let c = channel / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ rgb: (Double, Double, Double)) -> Double {
        0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    private func luminance(_ rgb: RGB) -> Double {
        luminance((Double(rgb.r), Double(rgb.g), Double(rgb.b)))
    }

    private func contrast(_ a: Double, _ b: Double) -> Double {
        let (hi, lo) = a > b ? (a, b) : (b, a)
        return (hi + 0.05) / (lo + 0.05)
    }

    private func contrast(_ text: RGB, on face: Face) -> Double {
        contrast(luminance(text), luminance(face.rgb))
    }

    // MARK: - 自己検査

    @Test("自己検査: 白黒 21:1・同色 1:1・透明度 0/1 の合成")
    func selfChecks() {
        let white = RGB(255, 255, 255)
        let black = RGB(0, 0, 0)
        #expect(abs(contrast(luminance(white), luminance(black)) - 21.0) < 1e-9)
        #expect(contrast(luminance(white), luminance(white)) == 1.0)
        let mid = RGB(40, 80, 120)
        #expect(over(mid, white, alpha: 0) == (40, 80, 120))
        #expect(over(mid, white, alpha: 1) == (255, 255, 255))
    }

    // MARK: - テーマ一覧

    @Test("ThemeStore.all は既知の 10 テーマを全部含み、追加テーマも検査対象になる")
    func themeCatalogCoversKnownThemes() {
        let ids = ThemeStore.all.map(\.id)
        #expect(ids.count >= 10)
        #expect(Set(ids).count == ids.count, "id 重複")
        for id in Self.knownThemeIDs {
            #expect(ids.contains(id), "\(id) が ThemeStore.all に無い")
        }
    }

    // MARK: - 読みやすさ（本体）

    @Test("全テーマ × 4 面で primary / secondary / tertiary の比が 4.5 以上（丸め前）")
    func allTextRolesReadableOnEverySidebarFace() {
        for theme in ThemeStore.all {
            for face in sidebarFaces(theme) {
                for (role, rgb) in [("primary", theme.textPrimary), ("secondary", theme.textSecondary), ("tertiary", theme.textTertiary)] {
                    let ratio = contrast(rgb, on: face)
                    #expect(ratio >= Self.minimumRatio, "\(theme.id) \(role) on \(face.name): \(ratio)")
                }
            }
        }
    }

    @Test("全テーマ × 4 面で階層を保つ: contrast(primary) >= contrast(secondary) >= contrast(tertiary)")
    func hierarchyIsPreserved() {
        for theme in ThemeStore.all {
            for face in sidebarFaces(theme) {
                let p = contrast(theme.textPrimary, on: face)
                let s = contrast(theme.textSecondary, on: face)
                let t = contrast(theme.textTertiary, on: face)
                #expect(p >= s, "\(theme.id) \(face.name): primary \(p) < secondary \(s)")
                #expect(s >= t, "\(theme.id) \(face.name): secondary \(s) < tertiary \(t)")
            }
        }
    }

    // MARK: - 製品トークンと契約定数の一致

    private func sample(_ color: Color) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let c = try #require(NSColor(color).usingColorSpace(.sRGB))
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    private func matches(_ s: (r: Double, g: Double, b: Double, a: Double), _ rgb: RGB, alpha: Double) -> Bool {
        abs(s.r * 255 - Double(rgb.r)) <= 1 && abs(s.g * 255 - Double(rgb.g)) <= 1
            && abs(s.b * 255 - Double(rgb.b)) <= 1 && abs(s.a - alpha) < 0.005
    }

    @Test("DSColor の hover / 選択 / 注意面は契約の 5% / 10% / 22% と一致する（実効テーマで検査）")
    func overlayTokensMatchContract() throws {
        let theme = ThemeStore.active
        #expect(matches(try sample(DSColor.fillSubtle), theme.textPrimary, alpha: Self.hoverAlpha))
        #expect(matches(try sample(DSColor.sessionRowHover), theme.textPrimary, alpha: Self.hoverAlpha))
        #expect(matches(try sample(DSColor.fillSelected), theme.textPrimary, alpha: Self.selectedAlpha))
        #expect(matches(try sample(DSColor.sessionRowSelected), theme.textPrimary, alpha: Self.selectedAlpha))
        #expect(matches(try sample(DSColor.idleHighlight), theme.attention, alpha: Self.attentionAlpha))
        #expect(matches(try sample(DSColor.background), theme.background, alpha: 1))
        #expect(matches(try sample(DSColor.textPrimary), theme.textPrimary, alpha: 1))
        #expect(matches(try sample(DSColor.textSecondary), theme.textSecondary, alpha: 1))
        #expect(matches(try sample(DSColor.textTertiary), theme.textTertiary, alpha: 1))
    }

    // MARK: - 不変条件（端末色・ANSI16 は補正対象外）

    private static let terminalFingerprints: [String: String] = [
        "phlox": "0e0e0e|d6d6d6|0d0d0d,ef4444,34d399,fbbf24,60a5fa,d97757,38bdf8,e5e5e5,3f3f46,fb7171,6ee7b7,fde68a,93c5fd,fba88a,7dd3fc,ffffff",
        "tokyo-night": "1a1b26|c0caf5|15161e,f7768e,9ece6a,e0af68,7aa2f7,bb9af7,7dcfff,a9b1d6,414868,f7768e,9ece6a,e0af68,7aa2f7,bb9af7,7dcfff,c0caf5",
        "dracula": "282a36|f8f8f2|21222c,ff5555,50fa7b,f1fa8c,bd93f9,ff79c6,8be9fd,f8f8f2,6272a4,ff6e6e,69ff94,ffffa5,d6acff,ff92df,a4ffff,ffffff",
        "catppuccin-mocha": "1e1e2e|cdd6f4|45475a,f38ba8,a6e3a1,f9e2af,89b4fa,f5c2e7,94e2d5,bac2de,585b70,f38ba8,a6e3a1,f9e2af,89b4fa,f5c2e7,94e2d5,a6adc8",
        "gruvbox-dark": "282828|ebdbb2|282828,cc241d,98971a,d79921,458588,b16286,689d6a,a89984,928374,fb4934,b8bb26,fabd2f,83a598,d3869b,8ec07c,ebdbb2",
        "nord": "2e3440|d8dee9|3b4252,bf616a,a3be8c,ebcb8b,81a1c1,b48ead,88c0d0,e5e9f0,4c566a,bf616a,a3be8c,ebcb8b,81a1c1,b48ead,8fbcbb,eceff4",
        "catppuccin-latte": "eff1f5|4c4f69|5c5f77,d20f39,40a02b,df8e1d,1e66f5,ea76cb,179299,acb0be,6c6f85,d20f39,40a02b,df8e1d,1e66f5,ea76cb,179299,bcc0cc",
        "solarized-light": "fdf6e3|657b83|073642,dc322f,859900,b58900,268bd2,d33682,2aa198,eee8d5,002b36,cb4b16,586e75,657b83,839496,6c71c4,93a1a1,fdf6e3",
        "github-light": "ffffff|24292f|24292f,cf222e,116329,4d2d00,0969da,8250df,1b7c83,6e7781,57606a,a40e26,1a7f37,9a6700,2182e8,a475f9,318e95,8c959f",
        "phlox-light": "f7f7f9|1e1b2e|1e1b2e,dc2626,059669,d97706,7c3aed,db2777,0891b2,6b7280,9ca3af,ef4444,10b981,f59e0b,8b5cf6,ec4899,06b6d4,94a3b8",
    ]

    private func hex(_ rgb: RGB) -> String { String(format: "%02x%02x%02x", rgb.r, rgb.g, rgb.b) }

    @Test("端末背景・前景・ANSI16 は 2026-09-12 時点の定義から変わらない（文字色補正の巻き添え禁止）")
    func terminalPaletteUnchanged() {
        for theme in ThemeStore.all {
            guard let expected = Self.terminalFingerprints[theme.id] else { continue }
            #expect(theme.ansi.count == 16, Comment(rawValue: theme.id))
            let actual = "\(hex(theme.terminalBackground))|\(hex(theme.terminalForeground))|\(theme.ansi.map(hex).joined(separator: ","))"
            #expect(actual == expected, Comment(rawValue: theme.id))
        }
    }

    @Test("アクセント・状態色・明暗判定は補正で変わらない")
    func accentAndSchemeUnchanged() {
        for theme in ThemeStore.all {
            #expect(theme.accent == RGB(0xD9, 0x77, 0x57), "\(theme.id) accent")
            #expect(theme.preferredColorScheme == (theme.terminalBackground.grayscale.relativeLuminance >= 0.5 ? .light : .dark), "\(theme.id) scheme")
        }
    }
}
