import AppKit
import Testing
@testable import TerminalUI

/// init(palette:) およびパレット適用の検証。
/// 既定ではグローバルな `TerminalCoordinator.activePalette` には触れない（テスト間共有状態のため）。
/// ただし `applyActivePalette` の検証テストのみ、defer 復元を前提に `activePalette` を一時差し替えする。
@MainActor
@Suite struct TerminalCoordinatorPaletteTests {
    @Test func initWithPalette_appliesBackgroundAndForegroundColors() throws {
        let palette = TerminalPalette(
            background: .init(10, 20, 30),
            foreground: .init(200, 210, 220),
            ansi: TerminalPalette.phloxDefault.ansi
        )

        let coordinator = TerminalCoordinator(palette: palette)

        let background = try #require(coordinator.terminalView.nativeBackgroundColor.usingColorSpace(.sRGB))
        let foreground = try #require(coordinator.terminalView.nativeForegroundColor.usingColorSpace(.sRGB))
        #expect(abs(background.redComponent - 10.0 / 255.0) < 0.005)
        #expect(abs(background.greenComponent - 20.0 / 255.0) < 0.005)
        #expect(abs(background.blueComponent - 30.0 / 255.0) < 0.005)
        #expect(abs(foreground.redComponent - 200.0 / 255.0) < 0.005)
        #expect(abs(foreground.greenComponent - 210.0 / 255.0) < 0.005)
        #expect(abs(foreground.blueComponent - 220.0 / 255.0) < 0.005)
    }

    @Test func initWithPalette_appliesHostingViewBackgroundColor() throws {
        let palette = TerminalPalette(
            background: .init(40, 50, 60),
            foreground: .init(200, 210, 220),
            ansi: TerminalPalette.phloxDefault.ansi
        )

        let coordinator = TerminalCoordinator(palette: palette)

        let layerColor = try #require(coordinator.hostingView.layer?.backgroundColor)
        let background = try #require(NSColor(cgColor: layerColor)?.usingColorSpace(.sRGB))
        #expect(abs(background.redComponent - 40.0 / 255.0) < 0.005)
        #expect(abs(background.greenComponent - 50.0 / 255.0) < 0.005)
        #expect(abs(background.blueComponent - 60.0 / 255.0) < 0.005)
    }

    @Test func applyActivePalette_updatesHostingViewBackgroundColor() throws {
        let originalPalette = TerminalCoordinator.activePalette
        defer { TerminalCoordinator.activePalette = originalPalette }

        let coordinator = TerminalCoordinator(palette: TerminalPalette.phloxDefault)
        TerminalCoordinator.activePalette = TerminalPalette(
            background: .init(80, 90, 100),
            foreground: .init(200, 210, 220),
            ansi: TerminalPalette.phloxDefault.ansi
        )

        coordinator.applyActivePalette()

        let layerColor = try #require(coordinator.hostingView.layer?.backgroundColor)
        let background = try #require(NSColor(cgColor: layerColor)?.usingColorSpace(.sRGB))
        #expect(abs(background.redComponent - 80.0 / 255.0) < 0.005)
        #expect(abs(background.greenComponent - 90.0 / 255.0) < 0.005)
        #expect(abs(background.blueComponent - 100.0 / 255.0) < 0.005)
    }
}
