import Testing
import Foundation
import DesignSystem
@testable import DashboardFeature
@testable import SessionFeature

/// task-2（バグ1 チャット拡大縮小）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約:
/// - `ChatFontSettings` は全チャット共通のフォントスケール（倍率）を UserDefaults に永続化する
///   単一の真実源（TerminalFontSettings に倣う）。既定 1.0、min/max にクランプ、step 増減。
/// - `ChatTypography` はスケールを掛けたフォントサイズを返す純関数の単一の真実源。
///   基準サイズは現行のチャット固定値（本文15 / コード13.5 / 見出し26/19/16）で、
///   scale に線形追従する。RichMarkdownView と各セルはここを参照する。
@Suite("ChatFontScale acceptance")
struct ChatFontScaleAcceptanceTests {

    // MARK: - ChatFontSettings（永続化・クランプ）

    @Test
    func defaultScaleIsUnityAndWithinBounds() {
        #expect(ChatFontSettings.defaultScale == 1.0)
        #expect(ChatFontSettings.minScale <= 1.0)
        #expect(ChatFontSettings.maxScale >= 1.0)
        #expect(ChatFontSettings.minScale < ChatFontSettings.maxScale)
        #expect(ChatFontSettings.step > 0)
    }

    @Test
    func adjustClampsAtMin() {
        #expect(ChatFontSettings.adjusted(from: ChatFontSettings.minScale, by: -ChatFontSettings.step)
                == ChatFontSettings.minScale)
    }

    @Test
    func adjustClampsAtMax() {
        #expect(ChatFontSettings.adjusted(from: ChatFontSettings.maxScale, by: ChatFontSettings.step)
                == ChatFontSettings.maxScale)
    }

    @Test
    func adjustAppliesStepWithinBounds() {
        let up = ChatFontSettings.adjusted(from: ChatFontSettings.defaultScale, by: ChatFontSettings.step)
        #expect(up == min(ChatFontSettings.maxScale, ChatFontSettings.defaultScale + ChatFontSettings.step))
        #expect(up > ChatFontSettings.defaultScale)

        let down = ChatFontSettings.adjusted(from: ChatFontSettings.defaultScale, by: -ChatFontSettings.step)
        #expect(down == max(ChatFontSettings.minScale, ChatFontSettings.defaultScale - ChatFontSettings.step))
        #expect(down < ChatFontSettings.defaultScale)
    }

    @Test
    func saveAndCurrentScaleRoundTrips() {
        let suite = "phlox.tests.chatfont.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let target = min(ChatFontSettings.maxScale, max(ChatFontSettings.minScale, 1.5))
        ChatFontSettings.save(target, defaults: defaults)
        #expect(ChatFontSettings.currentScale(defaults: defaults) == target)
    }

    @Test
    func currentScaleFallsBackToDefaultWhenUnset() {
        let suite = "phlox.tests.chatfont.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ChatFontSettings.currentScale(defaults: defaults) == ChatFontSettings.defaultScale)
    }

    // MARK: - ChatTypography（線形スケール・基準サイズ）

    @Test
    func typographyBaseSizesAtUnityScale() {
        #expect(ChatTypography.bodyFontSize(scale: 1.0) == 15)
        #expect(ChatTypography.codeFontSize(scale: 1.0) == 13.5)
        #expect(ChatTypography.heading1FontSize(scale: 1.0) == 26)
        #expect(ChatTypography.heading2FontSize(scale: 1.0) == 19)
        #expect(ChatTypography.heading3FontSize(scale: 1.0) == 16)
    }

    @Test
    func typographyScalesLinearly() {
        #expect(ChatTypography.bodyFontSize(scale: 2.0) == 30)
        #expect(ChatTypography.codeFontSize(scale: 2.0) == 27)
        #expect(ChatTypography.bodyFontSize(scale: 1.5) == ChatTypography.bodyFontSize(scale: 1.0) * 1.5)
        #expect(ChatTypography.heading1FontSize(scale: 1.5) == ChatTypography.heading1FontSize(scale: 1.0) * 1.5)
    }
}
