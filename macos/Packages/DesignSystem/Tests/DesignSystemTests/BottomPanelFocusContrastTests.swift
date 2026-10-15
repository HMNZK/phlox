import Testing
import AppKit
import SwiftUI
@testable import DesignSystem

@Suite("下部パネルの終了案内のコントラスト")
struct BottomPanelFocusContrastTests {
    @Test("暗い端末面の終了案内と再起動ボタンの文字は4.5:1以上", arguments: [AppTheme.phloxLight, AppTheme.phlox])
    @MainActor func exitedTextContrast(theme: AppTheme) throws {
        #expect(DesignPalette.contrast(try rgb(DSColor.terminalStatusText), theme.palette.terminal) >= 4.5)
        #expect(DesignPalette.contrast(try rgb(DSColor.terminalControlForeground), try rgb(DSColor.terminalControlBackground)) >= 4.5)
    }

    @MainActor private func rgb(_ color: Color) throws -> RGB {
        let value = try #require(NSColor(color).usingColorSpace(.sRGB))
        return RGB(Int((value.redComponent * 255).rounded()), Int((value.greenComponent * 255).rounded()), Int((value.blueComponent * 255).rounded()))
    }
}
