import AppKit
import ObjectiveC
import Testing
@testable import DashboardFeature

/// 選択用 NSTextView の追跡は実走し、待つ入力だけを専用ウィンドウから供給する。
/// AppKit の nested runloop が SwiftPM の async main を終了させることを避ける。
@MainActor
func sendMarkdownMouseEvents(_ events: [NSEvent], in window: NSWindow) throws {
    let first = try #require(events.first)
    try #require(events.allSatisfy { $0.windowNumber == window.windowNumber })
    let originalClass: AnyClass = try #require(object_getClass(NSApp))
    try #require(class_getInstanceSize(originalClass) == class_getInstanceSize(MarkdownTrackingApplication.self))
    MarkdownTrackingApplication.events = Array(events.dropFirst())
    MarkdownTrackingApplication.windowNumber = window.windowNumber
    MarkdownTrackingApplication.suppliedEvent = first
    object_setClass(NSApp, MarkdownTrackingApplication.self)
    defer {
        object_setClass(NSApp, originalClass)
        MarkdownTrackingApplication.events = []
        MarkdownTrackingApplication.windowNumber = nil
        MarkdownTrackingApplication.suppliedEvent = nil
    }
    NSApp.sendEvent(first)
    while !MarkdownTrackingApplication.events.isEmpty {
        NSApp.sendEvent(MarkdownTrackingApplication.events.removeFirst())
    }
}

/// instance の格納領域を増やさず、イベント供給の公開 API だけを同期処理中に置き換える。
@MainActor
private final class MarkdownTrackingApplication: NSApplication {
    static var events: [NSEvent] = []
    static var windowNumber: Int?
    static var suppliedEvent: NSEvent?

    override var currentEvent: NSEvent? { Self.suppliedEvent ?? super.currentEvent }

    override func sendEvent(_ event: NSEvent) {
        precondition(event.windowNumber == Self.windowNumber, "専用ウィンドウ以外の入力は供給しません")
        func deliver(to view: NSView) {
            (view as? MarkdownBlockSelectionObserver.SelectionView)?.handleEvent(event)
            view.subviews.forEach(deliver)
        }
        if let content = event.window?.contentView { deliver(to: content) }
        Self.suppliedEvent = event
        super.sendEvent(event)
    }

    override func postEvent(_ event: NSEvent, atStart flag: Bool) {
        precondition(event.windowNumber == Self.windowNumber, "専用ウィンドウ以外の入力は供給しません")
        // NSTextView は初期判定で取り出した入力を、本体の追跡用に再投入する。
        if flag { Self.events.insert(event, at: 0) } else { Self.events.append(event) }
    }

    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue flag: Bool) -> NSEvent? {
        guard let index = Self.events.firstIndex(where: { mask.rawValue & (1 << $0.type.rawValue) != 0 }) else {
            Issue.record("追跡処理が用意した入力以外のイベントを要求しました")
            preconditionFailure("追跡入力不足 mask=\(mask.rawValue) queue=\(Self.events.map { $0.type.rawValue })")
        }
        let event = flag ? Self.events.remove(at: index) : Self.events[index]
        precondition(event.windowNumber == Self.windowNumber, "専用ウィンドウ以外の入力は供給しません")
        if flag { sendEvent(event) }
        return event
    }
}
