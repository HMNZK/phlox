// このファイル全体は macOS 専用（当たり判定に AppKit の NSView を使う）。
// iOS 向け代替は作らない（YAGNI）。
#if os(macOS)
import AppKit
import SwiftUI

/// 左右・上下の境界リサイズ用の掴みしろ。区切り線を中心に `gripWidth` の透明な当たり判定を持ち、
/// ホバー/ドラッグ中は中立色のバーを出して掴みしろを視認しやすくする。
/// 各インスタンスが自分の hover/drag state を持つため、複数を並べても相互に干渉しない
/// (view 単位の state を共有すると「片方をホバーすると両方光る」問題が起きるため切り出した)。
/// navigationShell 等の最前面オーバーレイとして区切り線の真上に重ねる前提。
public struct ResizeGripView: View {
    /// 掴みしろの幅(区切り線を中心に左右へ張り出す)。配置側の offset 計算と揃える。01 E6: 見た目 1pt・当たり 8pt。
    public static let gripWidth: CGFloat = DSLayout.dividerHitWidth

    let axis: Axis
    let hitWidth: CGFloat
    let onChanged: (_ translation: CGFloat) -> Void
    let onEnded: () -> Void
    let onDoubleClick: (() -> Void)?
    let onKeyboardAdjust: ((CGFloat) -> Void)?

    @State private var isHovered = false
    @State private var isResizing = false

    /// - Parameter axis: 移動方向。上下の境界は `.vertical`。
    /// - Parameter hitWidth: 移動方向の当たり判定の厚さ。分割表示の区切りは `DSLayout.dividerHitWidth`（8pt）。
    /// - Parameter onChanged: ドラッグ開始点からの移動量（右・下が正）。
    /// - Parameter onKeyboardAdjust: 矢印キーによる1段階の移動（右・下が正）。指定時だけキー入力を受け取る。
    public init(
        axis: Axis = .horizontal,
        hitWidth: CGFloat = gripWidth,
        onChanged: @escaping (_ translation: CGFloat) -> Void,
        onEnded: @escaping () -> Void,
        onDoubleClick: (() -> Void)? = nil,
        onKeyboardAdjust: ((CGFloat) -> Void)? = nil
    ) {
        self.axis = axis
        self.hitWidth = hitWidth
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onDoubleClick = onDoubleClick
        self.onKeyboardAdjust = onKeyboardAdjust
    }

    public var body: some View {
        let highlighted = isHovered || isResizing
        // 当たり判定は AppKit の view が持つ。SwiftUI の DragGesture だと、窓の上端（タイトルバーの帯）では
        // macOS が先に「窓を動かす操作」として受け取り、境界ではなく窓全体が動いた。
        ResizeGripHitArea(
            axis: axis,
            onHover: { isHovered = $0 },
            onDrag: { translation in
                isResizing = true
                onChanged(translation)
            },
            onDragEnded: {
                isResizing = false
                onEnded()
            },
            onDoubleClick: onDoubleClick,
            onKeyboardAdjust: onKeyboardAdjust
        )
        .frame(width: axis == .horizontal ? hitWidth : nil, height: axis == .vertical ? hitWidth : nil)
        .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
        .overlay {
            // 区切り線位置の 3pt バー（角丸 2）。ホバー/ドラッグ中のみ表示する。
            RoundedRectangle(cornerRadius: DSLayout.resizeGripRadius, style: .continuous)
                .fill(DSColor.separator)
                .frame(width: axis == .horizontal ? DSLayout.resizeGripHighlightWidth : nil,
                       height: axis == .vertical ? DSLayout.resizeGripHighlightWidth : nil)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
                .opacity(highlighted ? 1 : 0)
                .animation(DSAnimation.resizeGrip, value: highlighted)
                .allowsHitTesting(false)
        }
    }
}

private struct ResizeGripHitArea: NSViewRepresentable {
    let axis: Axis
    let onHover: (Bool) -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClick: (() -> Void)?
    let onKeyboardAdjust: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> ResizeGripNSView { ResizeGripNSView() }

    func updateNSView(_ view: ResizeGripNSView, context: Context) {
        view.axis = axis
        view.onHover = onHover
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.onKeyboardAdjust = onKeyboardAdjust
    }
}

final class ResizeGripNSView: NSView {
    var axis: Axis = .horizontal {
        didSet { if axis != oldValue { window?.invalidateCursorRects(for: self) } }
    }
    var resizeCursor: NSCursor { axis == .horizontal ? .resizeLeftRight : .resizeUpDown }
    var onHover: (Bool) -> Void = { _ in }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    var onDoubleClick: (() -> Void)?
    var onKeyboardAdjust: ((CGFloat) -> Void)?

    /// 押した位置（窓の座標）。区切り線自身が動いても基準がずれないよう、窓の座標で測る。
    private var dragStart: NSPoint?
    private var isDragging = false

    /// この掴みしろが窓を動かせなくしている間だけ true。
    private var holdsWindow = false
    /// 窓ごとの「動かせなくしている掴みしろの数」と元の値。掴みしろが重なっても、最後の 1 つが離れたときに元へ戻す。
    private static var windowHolds: [ObjectIdentifier: (count: Int, wasMovable: Bool)] = [:]
    private var resignObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    /// AppKit から見て、マウスが掴みしろの上にあるか（入った・出たの通知で更新）。
    private var isPointerInside = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { onKeyboardAdjust != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let onKeyboardAdjust, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch (axis, event.keyCode) {
        case (.horizontal, 123), (.vertical, 126): onKeyboardAdjust(-1)
        case (.horizontal, 124), (.vertical, 125): onKeyboardAdjust(1)
        default: super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // 作り直さない。.inVisibleRect で範囲は view に追従する。ドラッグで掴みしろが動くたびに作り直すと、
        // 新しい範囲は「中にいる」ことを知らず、離れても出たの通知が来ずに窓が動かせないまま残った（実機で確認）。
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // .activeAlways の追跡範囲では cursorUpdate が来ないので、カーソルは cursor rect で出す。
    override func resetCursorRects() { addCursorRect(bounds, cursor: resizeCursor) }
    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        onHover(true)
        // タイトルバーの帯（窓の上端 52pt）では、mouseDownCanMoveWindow を false にしても
        // macOS が押した時点で窓のドラッグを始め、境界ではなく窓全体が動いた（実機で確認）。
        // 乗っている間だけ窓を動かせなくして、ドラッグを掴みしろへ届ける。
        holdWindowMovable()
    }

    private func holdWindowMovable() {
        guard !holdsWindow, let window else { return }
        holdsWindow = true
        let key = ObjectIdentifier(window)
        let hold = Self.windowHolds[key] ?? (count: 0, wasMovable: window.isMovable)
        Self.windowHolds[key] = (count: hold.count + 1, wasMovable: hold.wasMovable)
        window.isMovable = false
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        onHover(false)
        if !isDragging { restoreWindowMovable() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // ドラッグ中に消えた（サイドバーを閉じた等）ときも、カーソルとドラッグ終了を後始末する。
        endDragIfNeeded()
        restoreWindowMovable()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in [resignObserver, activeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        resignObserver = nil
        activeObserver = nil
        guard window != nil else { return }
        // 掴みしろに乗ったまま戻ってきたときは、ふたたび窓を動かせなくする（入ったの通知は来ないため）。
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                // 座標だけでなく、その位置で一番手前にあるのがこの窓かも確かめる（隠れた窓を固定しない）。
                let frontmost = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                if frontmost == window.windowNumber,
                   self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                    self.isPointerInside = true
                    self.holdWindowMovable()
                }
            }
        }
        // 乗ったまま・ドラッグ中に別のアプリへ移ったときも（mouseUp が届かないことがある）、
        // ドラッグを終えて窓を動かせない状態を残さない。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.endDragIfNeeded()
                self.restoreWindowMovable()
            }
        }
    }

    private func endDragIfNeeded() {
        dragStart = nil
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()
        onDragEnded()
    }

    private func restoreWindowMovable() {
        guard holdsWindow, let window else { return }
        holdsWindow = false
        let key = ObjectIdentifier(window)
        guard let hold = Self.windowHolds[key] else { return }
        if hold.count <= 1 {
            Self.windowHolds[key] = nil
            window.isMovable = hold.wasMovable
        } else {
            Self.windowHolds[key] = (count: hold.count - 1, wasMovable: hold.wasMovable)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if acceptsFirstResponder { window?.makeFirstResponder(self) }
        // ダブルクリックで既定の幅・高さに戻す。
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        holdWindowMovable()
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        if !isDragging {
            isDragging = true
            // 掴みしろから外れても、ドラッグ中は方向に合う矢印のままにする。
            resizeCursor.push()
        }
        onDrag(axis == .horizontal ? event.locationInWindow.x - dragStart.x : dragStart.y - event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        endDragIfNeeded()
        // 掴みしろの外で離したときは、ここで窓を動かせる状態に戻す。ドラッグ中は掴みしろが指より遅れて動くので、
        // 「出た」の通知がドラッグ中に届いて離したあとには来ないことがある（実機で窓が動かせないまま残った）。
        let isOverGrip = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if !isPointerInside || !isOverGrip {
            restoreWindowMovable()
        }
    }
}
#endif
