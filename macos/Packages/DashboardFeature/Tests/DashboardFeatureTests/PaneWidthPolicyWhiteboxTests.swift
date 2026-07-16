// task-1 白箱テスト（実装役著）
import Foundation
import Testing
@testable import DashboardFeature

@Test func paneWidthPolicy_shrinkOnly_neverExceedsInput() {
    let inputs: [(CGFloat, CGFloat, CGFloat)] = [
        (900, 280, 300),
        (800, 280, 300),
        (620, 280, 300),
        (2000, 250, 260),
    ]
    for (window, sidebar, inspector) in inputs {
        let r = PaneWidthPolicy.clamped(
            windowWidth: window,
            sidebarVisible: true,
            inspectorVisible: true,
            sidebarWidth: sidebar,
            inspectorWidth: inspector
        )
        #expect(r.sidebar <= sidebar)
        #expect(r.inspector <= inspector)
    }
}

@Test func paneWidthPolicy_nonPositiveWindowWidth_floorsVisibleAtMin() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 0,
        sidebarVisible: true,
        inspectorVisible: true,
        sidebarWidth: 280,
        inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 240, inspector: 240))
}

@Test func paneWidthPolicy_singleVisibleSidebar_respectsBudget() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 700,
        sidebarVisible: true,
        inspectorVisible: false,
        sidebarWidth: 280,
        inspectorWidth: 300
    )
    let budget = CGFloat(700) - PaneWidthPolicy.detailMinWidth
    #expect(r.sidebar <= budget)
    #expect(r.sidebar >= PaneWidthPolicy.sidebarMinWidth)
    #expect(r.inspector == 300)
}
