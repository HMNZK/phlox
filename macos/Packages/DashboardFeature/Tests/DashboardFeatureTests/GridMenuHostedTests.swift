import AppKit
import SwiftUI
import XCTest
import AgentDomain
import SessionFeature
@testable import DashboardFeature

final class GridMenuHostedTests: XCTestCase {
    @MainActor final class TrackedMenu: NSObject {
        var menu: NSMenu?
        var ended = false

        @objc func beganTracking(_ notification: Notification) { menu = notification.object as? NSMenu }
        @objc func endedTracking(_ notification: Notification) {
            if let ended = notification.object as? NSMenu, ended === menu { self.ended = true }
        }
    }

    @MainActor final class Harness {
        let dashboard: DashboardViewModel
        let originalCustom: GridLayoutState
        let host: NSView
        let window: NSWindow
        let previousAX: AnyObject?
        let axSetter = NSSelectorFromString("accessibilitySetValue:forAttribute:")

        init() throws {
            _ = NSApplication.shared
            dashboard = try DashboardViewModel(projection: GridAutoLayoutTests().snapshot(3)) { _ in .none }
            let viewport = GridViewport()
            viewport.update(CGSize(width: 1643, height: 903))
            dashboard.handlePaneLayoutAction(.applyPreset(.mainLeftStackRight), in: viewport.size)
            originalCustom = dashboard.gridLayoutState
            let router = AppRouter()
            router.viewMode = .grid
            host = NSHostingView(rootView: GridModeBar(viewModel: dashboard, router: router,
                gridViewport: viewport, sessionPickerPresented: .constant(false))
                .environment(\.locale, Locale(identifier: "ja"))
                .frame(width: 900, height: 36))
            window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 36), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            previousAX = NSApp.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: "AXEnhancedUserInterface")?.takeUnretainedValue()
            NSApp.perform(axSetter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        }

        func close() {
            window.contentView = nil
            window.close()
            NSApp.perform(axSetter, with: previousAX, with: "AXEnhancedUserInterface")
        }

        func select(_ title: String) async throws {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            _ = try XCTUnwrap(window.isVisible && host.window === window ? window : nil)
            let trigger = try XCTUnwrap(IntegrationFixAccessibility.find("grid-layout-menu", in: host))
            let tracked = TrackedMenu()
            NotificationCenter.default.addObserver(tracked, selector: #selector(TrackedMenu.beganTracking(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.addObserver(tracked, selector: #selector(TrackedMenu.endedTracking(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
            defer { NotificationCenter.default.removeObserver(tracked) }
            var selected = false
            var expired = false
            let deadline = Date().addingTimeInterval(3)
            let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
                let finished = MainActor.assumeIsolated { () -> Bool in
                    if let menu = tracked.menu, let item = menu.items.first(where: { $0.title == title }) {
                        selected = item.isEnabled
                        if selected { menu.performActionForItem(at: menu.index(of: item)) }
                        menu.cancelTracking()
                        return true
                    }
                    if Date() >= deadline {
                        expired = true
                        tracked.menu?.cancelTracking()
                        return true
                    }
                    return false
                }
                if finished { timer.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate(); if !tracked.ended { tracked.menu?.cancelTracking() } }
            XCTAssertTrue((trigger as AnyObject).accessibilityPerformShowMenu())
            while (!selected || !tracked.ended) && !expired && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            _ = try XCTUnwrap(selected && tracked.ended ? tracked.menu : nil, "実際のメニュー操作を確認できません。\(title)。\(tracked.menu?.items.map(\.title) ?? [])")
        }
    }

    @MainActor func testAutomaticMenuSwitchesFromCustom() async throws {
        let harness = try Harness()
        defer { harness.close() }
        try await harness.select("自動整列に戻す")
        XCTAssertTrue(harness.dashboard.gridLayoutState.isAutomatic)
        XCTAssertTrue(harness.dashboard.canUndoAutomaticGridLayout)
        XCTAssertEqual(harness.dashboard.gridLayoutState.customLayout, harness.originalCustom.customLayout)
    }

    @MainActor func testRestorePreviousCustomMenuRestoresTreeAndCanvas() async throws {
        let harness = try Harness()
        defer { harness.close() }
        harness.dashboard.restoreAutomaticGridLayout()
        try await harness.select("直前のカスタムに戻す")
        XCTAssertEqual(harness.dashboard.gridLayoutState, harness.originalCustom)
        XCTAssertFalse(harness.dashboard.canUndoAutomaticGridLayout)
    }
}
