import AppKit
import Foundation
import Testing
@testable import DashboardFeature

@Suite("TerminalFontSettings")
struct TerminalFontSettingsTests {

    // MARK: - clamped (adjusted で間接テスト)

    @Test("adjusted: minSize を下回らない")
    func adjusted_doesNotGoBelowMinSize() {
        // minSize そのものから -step すると minSize のまま
        let result = TerminalFontSettings.adjusted(
            from: TerminalFontSettings.minSize,
            by: -TerminalFontSettings.step
        )
        #expect(result == TerminalFontSettings.minSize)
    }

    @Test("adjusted: maxSize を超えない")
    func adjusted_doesNotExceedMaxSize() {
        // maxSize そのものから +step すると maxSize のまま
        let result = TerminalFontSettings.adjusted(
            from: TerminalFontSettings.maxSize,
            by: TerminalFontSettings.step
        )
        #expect(result == TerminalFontSettings.maxSize)
    }

    @Test("adjusted: 中間値で +step が正しく動く")
    func adjusted_incrementsByStep() {
        let base: CGFloat = 14
        let result = TerminalFontSettings.adjusted(from: base, by: TerminalFontSettings.step)
        #expect(result == base + TerminalFontSettings.step)
    }

    @Test("adjusted: 中間値で -step が正しく動く")
    func adjusted_decrementsByStep() {
        let base: CGFloat = 14
        let result = TerminalFontSettings.adjusted(from: base, by: -TerminalFontSettings.step)
        #expect(result == base - TerminalFontSettings.step)
    }

    @Test("adjusted: 上限境界で増加が頭打ちになる")
    func adjusted_clipsAtMaxSize() {
        // maxSize - step + 2*step で maxSize にクリップされる
        let nearMax = TerminalFontSettings.maxSize - TerminalFontSettings.step + 0.5
        let result = TerminalFontSettings.adjusted(from: nearMax, by: TerminalFontSettings.step)
        #expect(result == TerminalFontSettings.maxSize)
    }

    @Test("adjusted: 下限境界で減少が頭打ちになる")
    func adjusted_clipsAtMinSize() {
        // minSize + step - 2*step で minSize にクリップされる
        let nearMin = TerminalFontSettings.minSize + TerminalFontSettings.step - 0.5
        let result = TerminalFontSettings.adjusted(from: nearMin, by: -TerminalFontSettings.step)
        #expect(result == TerminalFontSettings.minSize)
    }

    // MARK: - currentSize

    @Test("currentSize: register 未適用(0 返却)の場合 NSFont.systemFontSize をクランプして返す")
    func currentSize_fallsBackToSystemFontSizeWhenZero() {
        let suiteName = "phlox.tests.TerminalFontSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // キー未登録 → double(forKey:) は 0 を返す
        let result = TerminalFontSettings.currentSize(defaults: defaults)

        let expected = min(
            TerminalFontSettings.maxSize,
            max(TerminalFontSettings.minSize, NSFont.systemFontSize)
        )
        #expect(result == expected)
    }

    @Test("currentSize: 保存済みの値を読み返す")
    func currentSize_returnsStoredValue() {
        let suiteName = "phlox.tests.TerminalFontSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stored: CGFloat = 18
        defaults.set(Double(stored), forKey: TerminalFontSettings.fontSizeKey)

        #expect(TerminalFontSettings.currentSize(defaults: defaults) == stored)
    }

    // MARK: - save / currentSize 往復

    @Test("save した値を currentSize で読み返せる")
    func save_roundTrip() {
        let suiteName = "phlox.tests.TerminalFontSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let size: CGFloat = 16
        TerminalFontSettings.save(size, defaults: defaults)

        #expect(TerminalFontSettings.currentSize(defaults: defaults) == size)
    }
}
