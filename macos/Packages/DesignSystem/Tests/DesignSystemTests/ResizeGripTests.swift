import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("共通の境界リサイズ", .serialized) @MainActor
struct ResizeGripTests {
    @Test("キーボード操作は指定した境界だけ有効で、方向に合う矢印を移動量へ変換する", arguments: [Axis.horizontal, .vertical])
    func keyboard(axis: Axis) throws {
        let view = ResizeGripNSView()
        view.axis = axis
        #expect(!view.acceptsFirstResponder)
        var moves: [CGFloat] = []
        view.onKeyboardAdjust = { moves.append($0) }
        #expect(view.acceptsFirstResponder)
        for (code, character) in axis == .vertical ? [(UInt16(126), "\u{F700}"), (125, "\u{F701}")] : [(123, "\u{F702}"), (124, "\u{F703}")] {
            let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            view.keyDown(with: key)
        }
        #expect(moves == [-1, 1])
    }

    @Test("左右は右が正、上下は下が正で、窓の座標から移動量を測る", arguments: [Axis.horizontal, .vertical])
    func translation(axis: Axis) throws {
        let view = ResizeGripNSView()
        view.axis = axis
        var values: [CGFloat] = []
        var ended = 0
        view.onDrag = { values.append($0) }
        view.onDragEnded = { ended += 1 }
        view.mouseDown(with: try event(.leftMouseDown, point: NSPoint(x: 100, y: 200)))
        view.mouseDragged(with: try event(.leftMouseDragged, point: NSPoint(x: 130, y: 160)))
        // 境界自身が移動しても、ドラッグ開始点は窓の座標のまま。
        view.frame.origin = NSPoint(x: 10, y: 10)
        view.mouseDragged(with: try event(.leftMouseDragged, point: NSPoint(x: 80, y: 260)))
        view.mouseUp(with: try event(.leftMouseUp, point: NSPoint(x: 80, y: 260)))
        #expect(values == (axis == .horizontal ? [30, -20] : [40, -60]))
        #expect(ended == 1)
    }

    @Test("上下カーソルをドラッグ中・領域外でも保ち、終了後に戻す")
    func verticalCursor() throws {
        let view = ResizeGripNSView()
        view.axis = .vertical
        #expect(view.resizeCursor === NSCursor.resizeUpDown)
        let original = NSCursor.current
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged, point: NSPoint(x: 900, y: -900)))
        #expect(NSCursor.current === NSCursor.resizeUpDown)
        view.mouseExited(with: try event(.mouseExited))
        #expect(NSCursor.current === NSCursor.resizeUpDown)
        view.mouseUp(with: try event(.leftMouseUp))
        #expect(NSCursor.current === original)
    }

    @Test("ダブルクリックは既定値への操作だけを呼ぶ")
    func doubleClick() throws {
        let view = ResizeGripNSView()
        view.axis = .vertical
        var height: CGFloat = 400
        var ended = 0
        view.onDoubleClick = { height = DSLayout.bottomPanelDefaultHeight }
        view.onDrag = { _ in Issue.record("ダブルクリックをドラッグとして扱った") }
        view.onDragEnded = { ended += 1 }
        view.mouseDown(with: try event(.leftMouseDown, clicks: 2))
        view.mouseDragged(with: try event(.leftMouseDragged))
        view.mouseUp(with: try event(.leftMouseUp))
        #expect(height == 280)
        #expect(ended == 0)
    }

    @Test("ホバー中とドラッグ中は窓を固定し、領域外の終了・取り外しで復元する", arguments: [false, true])
    func windowMovement(detach: Bool) throws {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovable = true
        defer { window.contentView = nil; window.close() }
        let view = ResizeGripNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 8))
        view.axis = .vertical
        window.contentView = view
        #expect(!view.mouseDownCanMoveWindow)
        var ended = 0
        view.onDragEnded = { ended += 1 }
        view.mouseEntered(with: try event(.mouseEntered))
        #expect(!window.isMovable)
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged))
        view.mouseExited(with: try event(.mouseExited))
        #expect(!window.isMovable)
        if detach { window.contentView = nil }
        else { view.mouseUp(with: try event(.leftMouseUp)) }
        #expect(window.isMovable)
        #expect(ended == 1)
    }

    private func event(_ type: NSEvent.EventType, point: NSPoint = .zero, clicks: Int = 1) throws -> NSEvent {
        if type == .mouseEntered || type == .mouseExited {
            return try #require(NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                      windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0))
    }
}
