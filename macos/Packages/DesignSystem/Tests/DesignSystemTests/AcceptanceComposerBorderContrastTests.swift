// task-27（UI-07）の受け入れテスト。
//
// ベースライン（実装前）での red 理由: `DSColor.composerBorder` は本タスクの契約が新設を要求する
// トークンであり、baseline_commit の時点ではまだ `Tokens.swift` に存在しない。したがってこのファイルは
// テストターゲットへ配置した時点で **コンパイル不能**（`type 'DSColor' has no member 'composerBorder'`）で
// red になる。これはアサーション失敗ではなく参照未解決によるビルド失敗であり、
// `~/.claude/skills/task-decomposition` の「red-for-the-right-reason」が許容する理由の1つ
// （新トークン不在でコンパイル不能）に該当する。
//
// 実装後は、次の2点を実測 RGB から動的に検証する（固定の期待値と比較するのではなく、
// `AppTheme` の実際の色から都度コントラスト比を計算する。将来テーマの色を変更してもテストが追従する）:
//   1. ライト系4テーマで、`DSColor.composerBorder` と「パネル面（背景+白4%）」のコントラスト比 >= 3.0
//   2. 同4テーマで、`DSColor.composerBorder` と「周囲背景（オーバーレイなしの背景）」のコントラスト比 >= 3.0
// ダーク系6テーマでは、`DSColor.composerBorder` が既存の `Color.white.opacity(0.06)` と完全一致すること
// （現状維持の回帰ガード）。
//
// 期待値の出所: `docs/agent-output/investigation-ui-07.md` の実測（`AppTheme.swift` の RGB 定義値を
// Python で相対輝度計算した結果、ライト4テーマとも枠のコントラストが 1.00〜1.02:1 に留まることを確認済み）。
// 測り方は WCAG の相対輝度式（`(L1+0.05)/(L2+0.05)`）をこのファイル内に自前実装し、調査と同じ式を使う。

import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("task-27: composer border contrast", .serialized)
struct AcceptanceComposerBorderContrastTests {
    private struct SampledColor {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
    }

    /// SwiftUI Color から sRGB 空間の実測成分を取り出す。既存 `ChatToolCallTokenTests` と同じ手法。
    private func sample(_ color: Color) throws -> SampledColor {
        let nsColor = try #require(NSColor(color).usingColorSpace(.sRGB))
        return SampledColor(
            r: Double(nsColor.redComponent),
            g: Double(nsColor.greenComponent),
            b: Double(nsColor.blueComponent),
            a: Double(nsColor.alphaComponent)
        )
    }

    /// `overlay` を `backdrop` の上に通常のアルファ合成で重ねた結果の RGB（0-255）。
    /// `overlay.a == 1.0`（不透明）なら backdrop に関係なく overlay 自身の色になる。
    private func composited(_ overlay: SampledColor, over backdrop: RGB) -> RGB {
        func mix(_ bg: Int, _ fg: Double) -> Int {
            Int((Double(bg) * (1 - overlay.a) + fg * 255 * overlay.a).rounded())
        }
        return RGB(mix(backdrop.r, overlay.r), mix(backdrop.g, overlay.g), mix(backdrop.b, overlay.b))
    }

    /// WCAG 相対輝度。`AppTheme.swift` の `RGB.relativeLuminance` と同一式（自前実装、調査と同じ式）。
    private func relativeLuminance(_ rgb: RGB) -> Double {
        func linear(_ value: Int) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    private func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// `theme.background` に白 `alpha` を通常合成で重ねた RGB。ChatComposer.swift のパネル面
    /// （`Color.white.opacity(0.04)` 重ね）と同じ合成。
    private func overlaidWithWhite(_ base: RGB, alpha: Double) -> RGB {
        func mix(_ bg: Int) -> Int { Int((Double(bg) * (1 - alpha) + 255 * alpha).rounded()) }
        return RGB(mix(base.r), mix(base.g), mix(base.b))
    }

    private func withStandardTheme<T>(_ id: String, perform body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }
        defaults.set(id, forKey: ThemeStore.themeKey)
        return try body()
    }

    private static let lightThemes: [AppTheme] = [.catppuccinLatte, .solarizedLight, .githubLight, .phloxLight]
    private static let darkThemes: [AppTheme] = [.phlox, .tokyoNight, .dracula, .catppuccinMocha, .gruvboxDark, .nord]

    @Test("ライト系4テーマで枠とパネル面のコントラストが3:1以上") @MainActor
    func borderMeetsContrastAgainstPanelFace() throws {
        for theme in Self.lightThemes {
            try withStandardTheme(theme.id) {
                let borderSample = try sample(DSColor.composerBorder)
                let panelFace = overlaidWithWhite(theme.background, alpha: 0.04)
                let borderComposited = composited(borderSample, over: panelFace)
                let ratio = contrastRatio(borderComposited, panelFace)
                #expect(ratio >= 3.0, "\(theme.name): パネル面とのコントラストが \(ratio) しかない（3.0以上が必要）")
            }
        }
    }

    @Test("ライト系4テーマで枠と周囲背景のコントラストが3:1以上") @MainActor
    func borderMeetsContrastAgainstSurroundingBackground() throws {
        // strokeBorder は形状の内側エッジに描かれるため、枠の直下のピクセルは「周囲背景」ではなく
        // 「パネル面（背景+白4%）」の上に重なる（調査 investigation-ui-07.md §3 のコメントと同じ前提）。
        // 合成はパネル面に対して行い、コントラストだけを周囲背景と比較する。
        for theme in Self.lightThemes {
            try withStandardTheme(theme.id) {
                let borderSample = try sample(DSColor.composerBorder)
                let panelFace = overlaidWithWhite(theme.background, alpha: 0.04)
                let surrounding = theme.background
                let borderComposited = composited(borderSample, over: panelFace)
                let ratio = contrastRatio(borderComposited, surrounding)
                #expect(ratio >= 3.0, "\(theme.name): 周囲背景とのコントラストが \(ratio) しかない（3.0以上が必要）")
            }
        }
    }

    @Test("ライト系4テーマの枠色はテーマの textPrimary 由来の半透明で、固定色や不透明色ではない") @MainActor
    func borderFollowsThemeTextPrimaryWithPartialAlpha() throws {
        // 固定 Color.black や不透明 100% でも 3:1 は満たせてしまうため、テーマ追随を直接検査する。
        // 期待: RGB 成分が theme.textPrimary と一致（許容 ±1/255）、alpha は 0 < a < 1。
        // 上限: パネル面とのコントラスト比 12 以下（純黒級の強い枠を排除。調査 §3 の候補値 0.82〜0.95 は 3.0〜7 程度）。
        for theme in Self.lightThemes {
            try withStandardTheme(theme.id) {
                let s = try sample(DSColor.composerBorder)
                let tp = theme.textPrimary
                #expect(abs(s.r * 255 - Double(tp.r)) <= 1.0, "\(theme.name): 枠色 R が textPrimary と一致しない")
                #expect(abs(s.g * 255 - Double(tp.g)) <= 1.0, "\(theme.name): 枠色 G が textPrimary と一致しない")
                #expect(abs(s.b * 255 - Double(tp.b)) <= 1.0, "\(theme.name): 枠色 B が textPrimary と一致しない")
                #expect(s.a > 0.0 && s.a < 1.0, "\(theme.name): 枠色は半透明であること（alpha=\(s.a)）")
                let panelFace = overlaidWithWhite(theme.background, alpha: 0.04)
                let ratio = contrastRatio(composited(s, over: panelFace), panelFace)
                #expect(ratio <= 12.0, "\(theme.name): 枠が強すぎる（比 \(ratio)、12 以下）")
            }
        }
    }

    @Test("ダーク系6テーマは既存の white 6% 固定値のまま変化しない") @MainActor
    func borderUnchangedForDarkThemes() throws {
        for theme in Self.darkThemes {
            try withStandardTheme(theme.id) {
                #expect(
                    DSColor.composerBorder == Color.white.opacity(0.06),
                    "\(theme.name): ダークテーマの枠色は変更前と完全一致であること"
                )
            }
        }
    }
}
