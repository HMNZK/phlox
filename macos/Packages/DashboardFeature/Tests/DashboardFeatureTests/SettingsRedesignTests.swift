import Foundation
import Testing
@testable import DashboardFeature

// 10 Settings: ターミナルの文字サイズの入力（T6b）。範囲外・整数でない値は保存しない。

@Suite("Settings redesign (10)")
struct SettingsRedesignTests {
    @Test func terminalFontInput_acceptsOnlyIntegersInRange() {
        let min = Int(TerminalFontSettings.minSize), max = Int(TerminalFontSettings.maxSize)
        #expect(TerminalFontSettings.parse("\(min)") == CGFloat(min))
        #expect(TerminalFontSettings.parse(" \(max) ") == CGFloat(max))
        #expect(TerminalFontSettings.parse("\(min - 1)") == nil)
        #expect(TerminalFontSettings.parse("\(max + 1)") == nil)
        #expect(TerminalFontSettings.parse("12.5") == nil)
        #expect(TerminalFontSettings.parse("") == nil)
        #expect(TerminalFontSettings.parse("abc") == nil)
    }
}
