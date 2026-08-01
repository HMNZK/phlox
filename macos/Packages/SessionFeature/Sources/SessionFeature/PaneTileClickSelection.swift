import AppKit
import SwiftUI

/// タイル内のクリックで選択を発火する条件。右端・下端は隣のタイルに属する半開区間として扱う。
enum PaneTileClickSelectionPolicy {
    static func shouldSelect(
        pointInWindow: CGPoint,
        tileFrameInWindow: CGRect,
        isFocused: Bool
    ) -> Bool {
        guard !isFocused else { return false }
        return pointInWindow.x >= tileFrameInWindow.minX
            && pointInWindow.x < tileFrameInWindow.maxX
            && pointInWindow.y >= tileFrameInWindow.minY
            && pointInWindow.y < tileFrameInWindow.maxY
    }
}

/// AppKit のイベントを受け取らず、座標と選択状態だけから選択通知の要否を決める。
@MainActor
final class PaneTileClickSelector {
    private let tileFrameInWindow: () -> CGRect?
    private let isFocused: () -> Bool
    private let onSelect: () -> Void

    init(
        tileFrameInWindow: @escaping () -> CGRect?,
        isFocused: @escaping () -> Bool,
        onSelect: @escaping () -> Void
    ) {
        self.tileFrameInWindow = tileFrameInWindow
        self.isFocused = isFocused
        self.onSelect = onSelect
    }

    func handleMouseDown(pointInWindow: CGPoint) {
        guard let tileFrameInWindow = tileFrameInWindow() else { return }
        guard PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: pointInWindow,
            tileFrameInWindow: tileFrameInWindow,
            isFocused: isFocused()
        ) else {
            return
        }
        onSelect()
    }
}

/// ローカルモニタが受けたイベントを、このタイルのクリックとして扱う条件。
enum PaneTileClickObservationPolicy {
    static func isEventFromTileWindow(
        eventWindow: AnyObject?,
        tileWindow: AnyObject?
    ) -> Bool {
        guard let eventWindow, let tileWindow else { return false }
        return eventWindow === tileWindow
    }
}

/// タイルの backing view から、クリック時点のウィンドウ座標を取り出す。
/// SwiftUI の `.position` による原点だけの移動は AppKit の `layout()` を呼ばないため、
/// 矩形の push 通知をキャッシュしてはならない。
@MainActor
final class PaneTileWindowFrameSource {
    private weak var view: NSView?

    func update(view: NSView?) {
        self.view = view
    }

    var frameInWindow: CGRect? {
        guard let view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    var window: NSWindow? {
        view?.window
    }
}

/// タイルごとのローカルイベント監視を所有する。監視したイベントは必ずそのまま返すため、
/// ターミナルや NSTextView の既存 mouseDown 処理を横取りしない。
@MainActor
final class PaneTileClickObserver {
    typealias LocalMonitorRegistrar = (@escaping (NSEvent) -> NSEvent?) -> Any?

    private let tileFrameInWindow: () -> CGRect?
    private let tileWindow: () -> NSWindow?
    private var isFocused: Bool
    private let onSelect: () -> Void
    private let addLocalMonitor: LocalMonitorRegistrar
    private let removeMonitor: (Any) -> Void
    private var monitor: Any?

    private lazy var selector = PaneTileClickSelector(
        tileFrameInWindow: { [weak self] in self?.tileFrameInWindow() },
        isFocused: { [weak self] in self?.isFocused ?? true },
        onSelect: { [weak self] in self?.onSelect() }
    )

    init(
        tileFrameInWindow: @escaping () -> CGRect?,
        tileWindow: @escaping () -> NSWindow?,
        isFocused: Bool,
        onSelect: @escaping () -> Void,
        addLocalMonitor: @escaping LocalMonitorRegistrar = { handler in
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: handler)
        },
        removeMonitor: @escaping (Any) -> Void = { monitor in
            NSEvent.removeMonitor(monitor)
        }
    ) {
        self.tileFrameInWindow = tileFrameInWindow
        self.tileWindow = tileWindow
        self.isFocused = isFocused
        self.onSelect = onSelect
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
    }

    func update(isFocused: Bool) {
        self.isFocused = isFocused
    }

    func start() {
        guard monitor == nil else { return }
        monitor = addLocalMonitor { [weak self] event in
            self?.handleMouseDown(
                eventWindowMatchesTileWindow: PaneTileClickObservationPolicy.isEventFromTileWindow(
                    eventWindow: event.window,
                    tileWindow: self?.tileWindow()
                ),
                pointInWindow: event.locationInWindow
            )
            return event
        }
    }

    func stop() {
        guard let monitor else { return }
        removeMonitor(monitor)
        self.monitor = nil
    }

    /// モニタのブロックから切り出した入口。登録解除済みの遅延イベントも無視する。
    func handleMouseDown(
        eventWindowMatchesTileWindow: Bool,
        pointInWindow: CGPoint
    ) {
        guard monitor != nil, eventWindowMatchesTileWindow else { return }
        selector.handleMouseDown(pointInWindow: pointInWindow)
    }
}

/// SwiftUI タイルの backing view を公開する、非ヒットテストのアンカー。
struct PaneTileWindowFrameReader: NSViewRepresentable {
    let onViewChange: (FrameReaderView?) -> Void

    func makeNSView(context: Context) -> FrameReaderView {
        let view = FrameReaderView()
        view.onViewChange = onViewChange
        onViewChange(view)
        return view
    }

    func updateNSView(_ nsView: FrameReaderView, context: Context) {
        nsView.onViewChange = onViewChange
        onViewChange(nsView)
    }

    static func dismantleNSView(_ nsView: FrameReaderView, coordinator: ()) {
        nsView.onViewChange?(nil)
        nsView.onViewChange = nil
    }

    @MainActor
    final class FrameReaderView: NSView {
        var onViewChange: ((FrameReaderView?) -> Void)?

        // 背景に置いたこのビューが terminal / NSTextView のヒットテスト対象にならないようにする。
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
