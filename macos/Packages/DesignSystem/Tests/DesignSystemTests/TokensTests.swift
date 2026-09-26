import SwiftUI
import AgentDomain
import Testing
@testable import DesignSystem

@Suite struct DSShadowGridTileTests {
    /// gridTile は再設計の値（`0 1px 2px rgba(0,0,0,.06)`）と一致する。CSS の blur 2px は SwiftUI の radius 1 に当たる。
    @Test func gridTileEqualsSpecifiedValue() {
        #expect(DSShadow.gridTile == DSShadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1))
    }
}

@Suite struct DSIconSizeTests {
    @Test func smallIs10() {
        #expect(DSIconSize.s == 10)
    }

    @Test func mediumIs12() {
        #expect(DSIconSize.m == 12)
    }

    @Test func largeIs15() {
        #expect(DSIconSize.l == 15)
    }
}

@Suite(.serialized) struct DSColorThemeTokenTests {
    @Test @MainActor
    func accentAndChatAccentUseClaudeCoral() {
        withStandardTheme(AppTheme.phlox.id) {
            let coral = RGB(0xD9, 0x77, 0x57).color
            // 再設計: UI の accent はダークで #E08865（12 Design System）。会話の accent も同じ値に揃える（2026-09-24 監査）。
            #expect(DSColor.accent == RGB(0xE0, 0x88, 0x65).color)
            #expect(DSColor.chatAccent == DSColor.accent)
            #expect(DSColor.accent != coral)
        }
        withStandardTheme(AppTheme.phloxLight.id) {
            #expect(DSColor.accent == RGB(0xD9, 0x77, 0x57).color)
            #expect(DSColor.diffAdded == RGB(0x1F, 0x7A, 0x3A).color)
        }
    }

    @Test @MainActor
    func hairlinesAndFillsDeriveFromThemeForeground() {
        withStandardTheme(AppTheme.phlox.id) {
            #expect(DSColor.border == AppTheme.phlox.textPrimary.color.opacity(0.14))
            #expect(DSColor.separator == AppTheme.phlox.textPrimary.color.opacity(0.10))
            // 12 Design System の --hov / --sel（ダーク 0.06 / 0.09）
            #expect(DSColor.fillSubtle == AppTheme.phlox.textPrimary.color.opacity(0.06))
            #expect(DSColor.fillSelected == AppTheme.phlox.textPrimary.color.opacity(0.09))
        }

        withStandardTheme(AppTheme.githubLight.id) {
            #expect(DSColor.border == AppTheme.githubLight.textPrimary.color.opacity(0.14))
            #expect(DSColor.separator == AppTheme.githubLight.textPrimary.color.opacity(0.10))
            // ライト 0.05 / 0.075
            #expect(DSColor.fillSubtle == AppTheme.githubLight.textPrimary.color.opacity(0.05))
            #expect(DSColor.fillSelected == AppTheme.githubLight.textPrimary.color.opacity(0.075))
        }
    }

    @Test @MainActor
    func sessionSelectionAndUserBubbleAreNeutralSurfaces() {
        withStandardTheme(AppTheme.phlox.id) {
            #expect(DSColor.sessionRowSelected == DSColor.fillSelected)
            #expect(DSColor.sessionRowSelectedBorder == Color.clear)
            #expect(DSColor.userBubble == AppTheme.phlox.textPrimary.color.opacity(0.08))
        }
    }

    // 2026-09-26 ユーザー依頼で PhloxChat.dc.html の --str（ダーク #FC6A5D・ライト #C41A16）へ。
    @Test @MainActor
    func codeSyntaxColorsBranchForLightThemes() {
        withStandardTheme(AppTheme.phlox.id) {
            #expect(DSColor.codeSyntaxString == RGB(0xFC, 0x6A, 0x5D).color)
        }

        withStandardTheme(AppTheme.githubLight.id) {
            #expect(DSColor.codeSyntaxString == RGB(0xC4, 0x1A, 0x16).color)
        }
    }

    @Test @MainActor
    func agentSessionIconDoesNotShowRunningIndicator() {
        let descriptor = AgentRegistry.descriptor(for: .claudeCode)
        #expect(!AgentSessionIcon(descriptor: descriptor, status: .running, size: 24).showsRunningIndicator)
        #expect(!AgentSessionIcon(descriptor: descriptor, status: .idle, size: 24).showsRunningIndicator)
        #expect(!AgentSessionIcon(descriptor: descriptor, status: .completed(exitCode: 0), size: 24).showsRunningIndicator)
    }

    private func withStandardTheme(_ id: String, perform body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defaults.set(id, forKey: ThemeStore.themeKey)
        body()
        if let previous {
            defaults.set(previous, forKey: ThemeStore.themeKey)
        } else {
            defaults.removeObject(forKey: ThemeStore.themeKey)
        }
    }
}
