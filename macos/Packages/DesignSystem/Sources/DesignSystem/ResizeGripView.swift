// このファイル全体は macOS 専用（当たり判定に AppKit の NSView を使う）。
// iOS 向け代替は作らない（YAGNI）。
#if os(macOS)
import AppKit
import SwiftUI

/// 縦の境界リサイズ用の掴みしろ。区切り線を中心に `gripWidth` の透明な当たり判定を持ち、
/// ホバー/ドラッグ中はアクセント色の発光バーを出して掴みしろを視認しやすくする。
/// 各インスタンスが自分の hover/drag state を持つため、複数を並べても相互に干渉しない
/// (view 単位の state を共有すると「片方をホバーすると両方光る」問題が起きるため切り出した)。
/// navigationShell 等の最前面オーバーレイとして区切り線の真上に重ねる前提。
public struct ResizeGripView: View {
    /// 掴みしろの幅(区切り線を中心に左右へ張り出す)。配置側の offset 計算と揃える。01 E6: 見た目 1pt・当たり 8pt。
    public static let gripWidth: CGFloat = 8

    let hitWidth: CGFloat
    let onChanged: (_ translation: CGFloat) -> Void
    let onEnded: () -> Void
    let onDoubleClick: (() -> Void)?

    @State private var isHovered = false
    @State private var isResizing = false

    /// - Parameter hitWidth: 当たり判定の幅。分割表示の区切りは `DSLayout.dividerHitWidth`（8pt）。
    /// - Parameter onChanged: ドラッグ開始点からの横の移動量（右が正）。
    public init(
        hitWidth: CGFloat = gripWidth,
        onChanged: @escaping (_ translation: CGFloat) -> Void,
        onEnded: @escaping () -> Void,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.hitWidth = hitWidth
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onDoubleClick = onDoubleClick
    }

    public var body: some View {
        let highlighted = isHovered || isResizing
        // 当たり判定は AppKit の view が持つ。SwiftUI の DragGesture だと、窓の上端（タイトルバーの帯）では
        // macOS が先に「窓を動かす操作」として受け取り、境界ではなく窓全体が動いた。
        ResizeGripHitArea(
            onHover: { isHovered = $0 },
            onDrag: { translation in
                isResizing = true
                onChanged(translation)
            },
            onDragEnded: {
                isResizing = false
                onEnded()
            },
            onDoubleClick: onDoubleClick
        )
        .frame(width: hitWidth)
        .frame(maxHeight: .infinity)
        .overlay {
            // 区切り線位置の accent 3pt（角丸 2）。ホバー/ドラッグ中のみ表示する。
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DSColor.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .opacity(highlighted ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: highlighted)
                .allowsHitTesting(false)
        }
    }
}

private struct ResizeGripHitArea: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> ResizeGripNSView { ResizeGripNSView() }

    func updateNSView(_ view: ResizeGripNSView, context: Context) {
        view.onHover = onHover
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
    }
}

final class ResizeGripNSView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    var onDoubleClick: (() -> Void)?

    /// 押した位置（窓の座標）。区切り線自身が動いても基準がずれないよう、窓の座標で測る。
    private var dragStartX: CGFloat?
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
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
        dragStartX = nil
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
        // 01 E6: ダブルクリックで既定の幅に戻す。
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        dragStartX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        if !isDragging {
            isDragging = true
            // 区切り線より速く動かして掴みしろから外れても、ドラッグ中は左右矢印のままにする。
            NSCursor.resizeLeftRight.push()
        }
        onDrag(event.locationInWindow.x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()
        onDragEnded()
        // 掴みしろの外で離したときは、ここで窓を動かせる状態に戻す。ドラッグ中は掴みしろが指より遅れて動くので、
        // 「出た」の通知がドラッグ中に届いて離したあとには来ないことがある（実機で窓が動かせないまま残った）。
        let isOverGrip = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if !isPointerInside || !isOverGrip {
            restoreWindowMovable()
        }
    }
}
#endif
