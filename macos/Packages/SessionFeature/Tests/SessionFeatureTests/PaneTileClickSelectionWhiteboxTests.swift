import AppKit
import CoreGraphics
import Testing
@testable import SessionFeature

@Suite("PaneTile click selection whitebox")
@MainActor
struct PaneTileClickSelectionWhiteboxTests {
    @Test("イベントのウィンドウは同じインスタンスのときだけ一致する")
    func eventWindowMustMatchTileWindowIdentity() {
        let tileWindow = NSObject()

        #expect(PaneTileClickObservationPolicy.isEventFromTileWindow(
            eventWindow: tileWindow,
            tileWindow: tileWindow
        ))
        #expect(!PaneTileClickObservationPolicy.isEventFromTileWindow(
            eventWindow: NSObject(),
            tileWindow: tileWindow
        ))
    }

    @Test("frame source はレイアウト通知なしの原点移動でも現在の backing view 座標を読む")
    func frameSourcePullsCurrentFrameAfterOriginOnlyMove() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let tileView = NSView(frame: CGRect(x: 10, y: 20, width: 100, height: 80))
        try #require(window.contentView).addSubview(tileView)
        let frameSource = PaneTileWindowFrameSource()
        frameSource.update(view: tileView)
        let originalFrame = try #require(frameSource.frameInWindow)

        tileView.setFrameOrigin(NSPoint(x: 200, y: 300))
        let movedFrame = try #require(frameSource.frameInWindow)

        #expect(movedFrame.minX == originalFrame.minX + 190)
        #expect(movedFrame.minY == originalFrame.minY + 280)
    }

    @Test("selector は原点移動後に以前の矩形を使わない")
    func selectorDoesNotUseFrameBeforeOriginMove() {
        var tileFrame: CGRect? = CGRect(x: 10, y: 20, width: 100, height: 80)
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { tileFrame },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        tileFrame = CGRect(x: 200, y: 300, width: 100, height: 80)
        selector.handleMouseDown(pointInWindow: CGPoint(x: 20, y: 30))

        #expect(selections == 0)
    }

    @Test("selector は原点移動後の現在の矩形で選択する")
    func selectorUsesFrameAfterOriginMove() {
        var tileFrame: CGRect? = CGRect(x: 10, y: 20, width: 100, height: 80)
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { tileFrame },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        tileFrame = CGRect(x: 200, y: 300, width: 100, height: 80)
        selector.handleMouseDown(pointInWindow: CGPoint(x: 220, y: 320))

        #expect(selections == 1)
    }

    @Test("selector はクリック時点で選択済みなら選択しない")
    func selectorUsesCurrentFocusState() {
        var isFocused = false
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { CGRect(x: 10, y: 20, width: 100, height: 80) },
            isFocused: { isFocused },
            onSelect: { selections += 1 }
        )

        isFocused = true
        selector.handleMouseDown(pointInWindow: CGPoint(x: 20, y: 30))

        #expect(selections == 0)
    }

    @Test("別ウィンドウのマウスダウンでは選択しない")
    func observerIgnoresMouseDownFromDifferentWindow() {
        var selections = 0
        let observer = PaneTileClickObserver(
            tileFrameInWindow: { CGRect(x: 10, y: 20, width: 100, height: 80) },
            tileWindow: { nil },
            isFocused: false,
            onSelect: { selections += 1 },
            addLocalMonitor: { _ in NSObject() }
        )

        observer.start()
        observer.handleMouseDown(
            eventWindowMatchesTileWindow: false,
            pointInWindow: CGPoint(x: 20, y: 30)
        )

        #expect(selections == 0)
    }

    @Test("同じ observer を二重に開始してもモニタは一つだけ登録する")
    func observerRegistersMonitorOnlyOnce() {
        var registrations = 0
        let observer = PaneTileClickObserver(
            tileFrameInWindow: { nil },
            tileWindow: { nil },
            isFocused: false,
            onSelect: {},
            addLocalMonitor: { _ in
                registrations += 1
                return NSObject()
            }
        )

        observer.start()
        observer.start()

        #expect(registrations == 1)
    }

    @Test("停止後の遅延したマウスダウンは選択しない")
    func observerIgnoresMouseDownAfterStopping() {
        var removals = 0
        var selections = 0
        let observer = PaneTileClickObserver(
            tileFrameInWindow: { CGRect(x: 10, y: 20, width: 100, height: 80) },
            tileWindow: { nil },
            isFocused: false,
            onSelect: { selections += 1 },
            addLocalMonitor: { _ in NSObject() },
            removeMonitor: { _ in removals += 1 }
        )

        observer.start()
        observer.stop()
        observer.stop()
        observer.handleMouseDown(
            eventWindowMatchesTileWindow: true,
            pointInWindow: CGPoint(x: 20, y: 30)
        )

        #expect(removals == 1)
        #expect(selections == 0)
    }
}
