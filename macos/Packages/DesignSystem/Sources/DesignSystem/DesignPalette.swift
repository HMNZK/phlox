import SwiftUI

/// 対応待ち 1 状態ぶんの色（記号・縁 / 文字 / 淡い面）。
/// 色が付くのは対応待ちの 4 状態（承認待ち・質問待ち・エラー・無応答）だけ（12 Design System）。
public struct AttentionColors: Sendable, Equatable {
    /// 記号・縁。背景に対して 3:1 以上を目標にする。
    public let mark: RGB
    /// 状態の文言。背景に対して 4.5:1 以上。
    public let ink: RGB
    /// 淡い面の不透明度（`mark` をこの不透明度で敷く）。
    public let tintOpacity: Double
}

/// 再設計（design_handoff_phlox_ui / 12 Design System）で増えた面・文字・状態色。
/// 既定の 2 テーマ（Phlox / Phlox Light）はデザインの確定値、それ以外は `derived` で導出する。
public struct DesignPalette: Sendable, Equatable {
    // 背景の階層
    public let window: RGB
    public let sidebar: RGB
    public let toolbar: RGB
    public let panel: RGB
    public let card: RGB
    public let code: RGB
    public let field: RGB
    public let popover: RGB
    public let tabBar: RGB
    // accent
    public let accent: RGB
    /// 白文字を載せる accent の面（主ボタン）。
    public let accentFill: RGB
    /// accent の文字（リンク・選択中タブ）。
    public let accentInk: RGB
    public let selectionOpacity: Double
    // 対応待ちの 4 状態
    public let approval: AttentionColors
    public let question: AttentionColors
    public let error: AttentionColors
    public let stalled: AttentionColors
    // 差分・端末
    public let diffAdded: RGB
    public let diffRemoved: RGB
    public let terminal: RGB

    public var isLight: Bool { window.relativeLuminance >= 0.5 }
}

extension DesignPalette {
    static let accentFillColor = RGB(0xB4, 0x55, 0x2F)

    /// Phlox Light の確定値。
    static let phloxLight = DesignPalette(
        window: RGB(0xFF, 0xFF, 0xFF), sidebar: RGB(0xF2, 0xF2, 0xF4), toolbar: RGB(0xF6, 0xF6, 0xF7),
        panel: RGB(0xF8, 0xF8, 0xF9), card: RGB(0xFF, 0xFF, 0xFF), code: RGB(0xF3, 0xF3, 0xF5),
        field: RGB(0xFF, 0xFF, 0xFF), popover: RGB(0xFF, 0xFF, 0xFF), tabBar: RGB(0xEC, 0xEC, 0xEF),
        accent: RGB(0xD9, 0x77, 0x57), accentFill: accentFillColor, accentInk: RGB(0xA9, 0x4A, 0x28),
        selectionOpacity: 0.17,
        approval: AttentionColors(mark: RGB(0xE3, 0x9A, 0x2D), ink: RGB(0x8A, 0x53, 0x00), tintOpacity: 0.12),
        question: AttentionColors(mark: RGB(0x3A, 0x7B, 0xDF), ink: RGB(0x1E, 0x5B, 0xB8), tintOpacity: 0.10),
        error: AttentionColors(mark: RGB(0xE0, 0x48, 0x4E), ink: RGB(0xB4, 0x23, 0x2A), tintOpacity: 0.08),
        stalled: AttentionColors(mark: RGB(0x94, 0x57, 0xDB), ink: RGB(0x74, 0x38, 0xBD), tintOpacity: 0.10),
        diffAdded: RGB(0x1F, 0x7A, 0x3A), diffRemoved: RGB(0xB4, 0x23, 0x2A), terminal: RGB(0x1B, 0x1B, 0x1D)
    )

    /// Phlox（ダーク）の確定値。
    static let phloxDark = DesignPalette(
        window: RGB(0x1E, 0x1E, 0x20), sidebar: RGB(0x26, 0x26, 0x29), toolbar: RGB(0x2A, 0x2A, 0x2D),
        panel: RGB(0x24, 0x24, 0x27), card: RGB(0x27, 0x27, 0x2A), code: RGB(0x2B, 0x2B, 0x2F),
        field: RGB(0x1A, 0x1A, 0x1C), popover: RGB(0x2F, 0x2F, 0x33), tabBar: RGB(0x23, 0x23, 0x26),
        accent: RGB(0xE0, 0x88, 0x65), accentFill: accentFillColor, accentInk: RGB(0xF0, 0xA3, 0x83),
        selectionOpacity: 0.24,
        approval: AttentionColors(mark: RGB(0xF0, 0xAE, 0x4A), ink: RGB(0xF4, 0xBD, 0x68), tintOpacity: 0.14),
        question: AttentionColors(mark: RGB(0x5D, 0x98, 0xF0), ink: RGB(0x8D, 0xB6, 0xF7), tintOpacity: 0.13),
        error: AttentionColors(mark: RGB(0xEE, 0x5A, 0x5F), ink: RGB(0xFF, 0x8A, 0x8D), tintOpacity: 0.12),
        stalled: AttentionColors(mark: RGB(0xA8, 0x76, 0xEB), ink: RGB(0xC4, 0xA2, 0xF4), tintOpacity: 0.14),
        diffAdded: RGB(0x6F, 0xD0, 0x8C), diffRemoved: RGB(0xFF, 0x8A, 0x8D), terminal: RGB(0x14, 0x14, 0x16)
    )

    static let minimumTextContrast = 4.5
    static let minimumMarkContrast = 3.0

    /// ターミナル配色由来のテーマ用。面の段差は既定テーマの差分をそのまま使い、
    /// 状態色は ANSI（黄・青・赤・紫）を起点に、文字は 4.5:1・記号は 3:1 に届くまで本文色へ寄せる。
    static func derived(background: RGB, textPrimary: RGB, ansi: [RGB]) -> DesignPalette {
        let reference = background.relativeLuminance >= 0.5 ? phloxLight : phloxDark
        // 明度の段差だけを移す（確定値のわずかな青みは移さず、導出テーマの面は無彩色のまま）。
        func shifted(_ face: RGB) -> RGB {
            let d = face.g - reference.window.g
            return RGB(clamp(background.r + d), clamp(background.g + d), clamp(background.b + d))
        }
        let faces = [reference.sidebar, reference.card, reference.panel, reference.toolbar].map(shifted) + [background]
        func attention(_ base: RGB, like ref: AttentionColors) -> AttentionColors {
            AttentionColors(
                mark: reaching(minimumMarkContrast, from: base, toward: textPrimary, on: faces),
                ink: reaching(minimumTextContrast, from: base, toward: textPrimary, on: faces),
                tintOpacity: ref.tintOpacity
            )
        }
        return DesignPalette(
            window: background, sidebar: shifted(reference.sidebar), toolbar: shifted(reference.toolbar),
            panel: shifted(reference.panel), card: shifted(reference.card), code: shifted(reference.code),
            field: shifted(reference.field), popover: shifted(reference.popover), tabBar: shifted(reference.tabBar),
            accent: reference.accent, accentFill: accentFillColor,
            accentInk: reaching(minimumTextContrast, from: reference.accent, toward: textPrimary, on: faces),
            selectionOpacity: reference.selectionOpacity,
            approval: attention(ansi[3], like: reference.approval),
            question: attention(ansi[4], like: reference.question),
            error: attention(ansi[1], like: reference.error),
            stalled: attention(ansi[5], like: reference.stalled),
            diffAdded: reaching(minimumTextContrast, from: ansi[2], toward: textPrimary, on: faces),
            diffRemoved: reaching(minimumTextContrast, from: ansi[1], toward: textPrimary, on: faces),
            terminal: reference.terminal
        )
    }

    private static func clamp(_ v: Int) -> Int { min(255, max(0, v)) }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = a.relativeLuminance > b.relativeLuminance
            ? (a.relativeLuminance, b.relativeLuminance)
            : (b.relativeLuminance, a.relativeLuminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// `base` を `target` へ最小限だけ寄せ、全 `faces` に対して `ratio` 以上にする。
    static func reaching(_ ratio: Double, from base: RGB, toward target: RGB, on faces: [RGB]) -> RGB {
        func ok(_ c: RGB) -> Bool { faces.allSatisfy { contrast(c, $0) >= ratio } }
        if ok(base) { return base }
        var lo = 0.0, hi = 1.0
        for _ in 0 ..< 30 {
            let mid = (lo + hi) / 2
            if ok(base.mixed(target, mid)) { hi = mid } else { lo = mid }
        }
        return base.mixed(target, hi)
    }
}
