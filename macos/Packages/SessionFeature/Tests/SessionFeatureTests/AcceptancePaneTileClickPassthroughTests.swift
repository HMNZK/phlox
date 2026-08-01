import Testing
import AppKit
@testable import SessionFeature

/// task-2 の不変条件「左マウスダウンを消費せず素通しする」の凍結 — PM 著・不変（実装役は編集禁止）。
///
/// タイル選択のためのローカルモニタがイベントを飲み込むと、ターミナル・テキストビューの
/// テキスト選択やドラッグが全滅する（アプリ全体に及ぶ退行）。モニタへ渡されるハンドラが
/// 受け取ったイベントをそのまま返すことを、ハンドラ自体を捕まえて検証する。
@Suite("PaneTile click passthrough acceptance")
@MainActor
struct PaneTileClickPassthroughAcceptanceTests {

    private func leftMouseDownEvent() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 30),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test
    func monitorHandlerReturnsTheEventUnmodified() throws {
        var captured: ((NSEvent) -> NSEvent?)?
        let observer = PaneTileClickObserver(
            tileFrameInWindow: { CGRect(x: 0, y: 0, width: 100, height: 100) },
            tileWindow: { nil },
            isFocused: false,
            onSelect: {},
            addLocalMonitor: { handler in
                captured = handler
                return NSObject()
            },
            removeMonitor: { _ in }
        )
        observer.start()

        let event = try leftMouseDownEvent()
        let handler = try #require(captured)

        #expect(handler(event) === event, "left mouse down must be passed through untouched")
    }

    /// 選択が発火するクリック（矩形内・未選択・同一ウィンドウ）でも、イベントは消費しない。
    @Test
    func monitorHandlerReturnsTheEventEvenWhenItSelects() throws {
        let window = NSWindow()
        var captured: ((NSEvent) -> NSEvent?)?
        var selections = 0
        let observer = PaneTileClickObserver(
            tileFrameInWindow: { CGRect(x: 0, y: 0, width: 100, height: 100) },
            tileWindow: { window },
            isFocused: false,
            onSelect: { selections += 1 },
            addLocalMonitor: { handler in
                captured = handler
                return NSObject()
            },
            removeMonitor: { _ in }
        )
        observer.start()

        let event = try leftMouseDownEvent()
        let handler = try #require(captured)

        #expect(handler(event) === event, "left mouse down must be passed through untouched")
        #expect(selections == 0, "an event from another window must not select this tile")
    }
}
