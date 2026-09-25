import Testing
@testable import DashboardFeature

// 06: グリッドのタイルの端末は単体より一段小さい（11.5 → 11）。
@MainActor
@Test func terminalDisplaySize_isSmallerOnlyInTheGrid() {
    let saved = TerminalFontSettings.isGridLayout
    defer { TerminalFontSettings.isGridLayout = saved }
    TerminalFontSettings.isGridLayout = false
    #expect(TerminalFontSettings.displaySize(13) == 13)
    TerminalFontSettings.isGridLayout = true
    #expect(TerminalFontSettings.displaySize(11.5) == 11)
    #expect(TerminalFontSettings.displaySize(13) == 12.5)
    #expect(TerminalFontSettings.displaySize(8) == 8)
}
