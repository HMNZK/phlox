// task-27（UI-07）の受け入れテスト。2026-09-24 に契約を置き換えた。
//
// 旧契約: ライト系 4 テーマで枠とパネル面が 3:1 以上、ダーク系は white 6% 固定。
// 新契約（ユーザー決定「モックの値に合わせる」）: 全テーマで枠は 12 Design System の `--line`
// ＝ textPrimary の 14%。旧契約ではライトで枠がほぼ黒になり、モックと食い違っていた。
// 期待値の出所: `design_handoff_phlox_ui/designs/12*.html` の `--line`、監査 `docs/agent-output/ui-fidelity-audit/05-reply.md`。

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

    // 2026-09-24 ユーザー決定「モックの値に合わせる」: 入力欄の枠は 12 Design System の `--line`
    // （textPrimary 14%）に統一した。旧契約（ライト 3:1 以上・ダーク white 6%）はライトで枠がほぼ黒に
    // なりモックと食い違うため置き換える。
    @Test("全テーマで枠色は textPrimary の 14%（モックの --line）") @MainActor
    func borderIsTextPrimaryAtLineOpacity() throws {
        for theme in Self.lightThemes + Self.darkThemes {
            try withStandardTheme(theme.id) {
                let s = try sample(DSColor.composerBorder)
                let tp = theme.textPrimary
                #expect(abs(s.r * 255 - Double(tp.r)) <= 1.0, "\(theme.name): 枠色 R が textPrimary と一致しない")
                #expect(abs(s.g * 255 - Double(tp.g)) <= 1.0, "\(theme.name): 枠色 G が textPrimary と一致しない")
                #expect(abs(s.b * 255 - Double(tp.b)) <= 1.0, "\(theme.name): 枠色 B が textPrimary と一致しない")
                #expect(abs(s.a - 0.14) < 0.005, "\(theme.name): 枠色の不透明度が 14% でない（\(s.a)）")
            }
        }
    }
}
