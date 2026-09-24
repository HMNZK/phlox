import Testing
@testable import DesignSystem

// 10 Settings: 目盛りを出さないスライダーでも 10% 刻みを守る。ドラッグで往復しないよう丸めは位置だけで決まる。
@Test func chatFontSnap_roundsToStepWithinRange() {
    #expect(abs(ChatFontSettings.snapped(1.26) - 1.3) < 0.0001)
    #expect(abs(ChatFontSettings.snapped(1.02) - 1.0) < 0.0001)
    #expect(abs(ChatFontSettings.snapped(1.02) - ChatFontSettings.snapped(1.03)) < 0.0001)
    #expect(abs(ChatFontSettings.snapped(2.3) - 2.0) < 0.0001)
    #expect(abs(ChatFontSettings.snapped(0.5) - 0.8) < 0.0001)
}
