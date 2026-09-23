// 01 Main Window の D（最小構成と狭い幅での縮退）の契約。
// 中央が 480pt を割るときは、まずインスペクタを重ね表示にし、それでも足りなければサイドバーを自動で隠す。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("3 ペインの幅と縮退")
struct PaneLayoutPolicyTests {
    @Test("全領域を開いても中央が 480pt 以上残るなら横に並べる")
    func wideWindowDocksBothPanes() {
        let layout = PaneWidthPolicy.resolve(
            windowWidth: 1680, sidebarVisible: true, inspectorVisible: true,
            sidebarWidth: 260, inspectorWidth: 280
        )
        #expect(layout == PaneLayout(sidebar: 260, inspector: 280, showsSidebar: true, inspectorIsOverlay: false))
    }

    @Test("中央が 480pt を割るときは、サイドバーを残してインスペクタだけを重ね表示にする")
    func narrowWindowOverlaysInspectorFirst() {
        let layout = PaneWidthPolicy.resolve(
            windowWidth: 900, sidebarVisible: true, inspectorVisible: true,
            sidebarWidth: 260, inspectorWidth: 280
        )
        #expect(layout.showsSidebar)
        #expect(layout.inspectorIsOverlay)
    }

    @Test("サイドバーだけでも中央が 480pt を割るならサイドバーを自動で隠す")
    func tooNarrowWindowAutoHidesSidebar() {
        let layout = PaneWidthPolicy.resolve(
            windowWidth: 720, sidebarVisible: true, inspectorVisible: false,
            sidebarWidth: 260, inspectorWidth: 280
        )
        #expect(!layout.showsSidebar)
        #expect(!layout.inspectorIsOverlay)
    }

    @Test("幅はサイドバー 220–360pt、インスペクタ 260–340pt に収める")
    func widthsAreClampedToDesignRanges() {
        let narrow = PaneWidthPolicy.resolve(
            windowWidth: 1680, sidebarVisible: true, inspectorVisible: true,
            sidebarWidth: 100, inspectorWidth: 100
        )
        let wide = PaneWidthPolicy.resolve(
            windowWidth: 1680, sidebarVisible: true, inspectorVisible: true,
            sidebarWidth: 500, inspectorWidth: 500
        )
        #expect((narrow.sidebar, narrow.inspector) == (220, 260))
        #expect((wide.sidebar, wide.inspector) == (360, 340))
    }

    @Test("境界ドラッグでは中央 480pt を割り込む幅まで広げない")
    func dragStopsBeforeCenterMinimum() {
        // 1000 − インスペクタ 281 − 中央 480 − 境界 1 = 238
        let sidebar = PaneWidthPolicy.draggedSidebarWidth(
            start: 260, translation: 60, windowWidth: 1000, inspectorSpan: 281
        )
        let inspector = PaneWidthPolicy.draggedInspectorWidth(
            start: 280, translation: -200, windowWidth: 1400, sidebarSpan: 261
        )
        #expect(sidebar == 238)
        #expect(inspector == 340)
    }
}

@Suite("サイドバーの開閉（⌃⌘S）")
@MainActor
struct SidebarToggleTests {
    @Test("幅が無いときは開閉の設定を変えずに一時表示を切り替える")
    func toggleWhileLackingRoomPeeks() {
        let router = AppRouter(sidebarVisible: true)
        router.sidebarLacksRoom = true

        router.toggleSidebar()

        #expect(router.sidebarVisible)
        #expect(router.sidebarPeeking)
    }

    @Test("狭い窓で手動で隠したサイドバーも 1 回の操作で一時表示する")
    func toggleHiddenSidebarInNarrowWindowPeeksAtOnce() {
        let router = AppRouter(sidebarVisible: false)
        router.sidebarLacksRoom = true

        router.toggleSidebar()

        #expect(router.sidebarVisible)
        #expect(router.sidebarPeeking)
    }

    @Test("幅が足りているときは開閉の設定を切り替え、一時表示を解く")
    func toggleWhenRoomyFlipsVisibility() {
        let router = AppRouter(sidebarVisible: true)
        router.sidebarPeeking = true

        router.toggleSidebar()

        #expect(!router.sidebarVisible)
        #expect(!router.sidebarPeeking)
    }
}
