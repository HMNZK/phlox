import AppKit
import Testing
import Foundation
import CoreGraphics
@testable import SessionFeature

/// タイル内クリックで即選択。
///
/// AppKit の実イベントは単体テストで作れないため、判定と発火を純粋な型へ切り出して検査する。
/// 「タイルの矩形内の左マウスダウンで、未選択なら選択する。選択済みなら何もしない」が契約。
/// 矩形・選択状態はクリック時点の値を引く（レイアウト通知なしの原点移動や、後からの選択でも古い値を使わない）。
@Suite("PaneTile click selection")
@MainActor
struct PaneTileClickSelectionTests {

    private let tile = CGRect(x: 100, y: 200, width: 400, height: 300)

    @Test
    func pointInsideUnfocusedTileSelects() {
        #expect(PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 350),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    @Test
    func pointInsideAlreadyFocusedTileDoesNotSelectAgain() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 350),
            tileFrameInWindow: tile,
            isFocused: true
        ))
    }

    @Test
    func pointOutsideTileDoesNotSelect() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 99, y: 350),
            tileFrameInWindow: tile,
            isFocused: false
        ))
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 501),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    @Test
    func pointOnLeadingEdgeBelongsToTheTile() {
        #expect(PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 100, y: 200),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    /// 隣接するタイルの共有辺で二重に選択が走らないこと（右端・下端は自分のものではない）。
    @Test
    func pointOnTrailingEdgeBelongsToTheNeighbour() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 500, y: 500),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    /// 矩形がまだ確定していない（レイアウト前）タイルは選択しない。
    @Test
    func selectorIgnoresClicksBeforeTheFrameIsKnown() {
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { nil },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        selector.handleMouseDown(pointInWindow: CGPoint(x: 120, y: 220))

        #expect(selections == 0)
    }

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
