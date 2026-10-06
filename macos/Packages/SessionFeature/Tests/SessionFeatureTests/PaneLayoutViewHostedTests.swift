import AppKit
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
import TerminalUI
@testable import SessionFeature

/// PaneLayoutView を（画面外の）ウィンドウに載せ、合成したマウスイベントとビュー階層で挙動を検査する。
/// 守る不具合:
/// - 分割線のドラッグ中にレイアウトを確定してメインスレッドが固まる（ADR 0116 の設計）
/// - ヘッダーの `.draggable` がゼロ距離の DragGesture にマウスダウンを取られ、タイルを動かせない
/// - レイアウトが変わるとタイルのビューが作り直され、端末が空白になる
@MainActor
@Suite("PaneLayoutView: ウィンドウに載せた実際の挙動")
struct PaneLayoutViewHostedTests {
    final class Recorder { var actions: [PaneLayoutAction] = [] }

    @MainActor
    struct Harness {
        let window: NSWindow
        let hosting: NSHostingView<PaneLayoutView>
        let recorder: Recorder
        let sessions: [SessionViewModel]
        let size = CGSize(width: 1000, height: 600)

        /// 木を差し替える（呼び出し側のモデルが変わったときと同じ）。
        func show(_ root: PaneNode, sessions: [SessionViewModel]? = nil) throws {
            hosting.rootView = PaneLayoutViewHostedTests.paneView(
                sessions: sessions ?? self.sessions, tree: try PaneTree(root: root), recorder: recorder
            )
            hosting.layoutSubtreeIfNeeded()
        }

        /// SwiftUI 座標（左上原点）の点からウィンドウ座標のイベントを作る。
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: NSPoint(x: point.x, y: size.height - point.y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }
    }

    static func paneView(sessions: [SessionViewModel], tree: PaneTree, recorder: Recorder) -> PaneLayoutView {
        PaneLayoutView(
            sessions: sessions.map { .pty($0) }, tree: tree, focusedID: .constant(nil),
            onRemove: { _ in }, onRename: { _ in }, onChangeWorkspace: { _ in },
            onLayoutAction: { recorder.actions.append($0) }
        )
    }

    static func makeSession() -> SessionViewModel {
        let (hooks, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        return SessionViewModel(
            id: SessionID(), ptyManager: TestMockPTYManager(), hookEvents: hooks,
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: .init(command: "/bin/sh", args: [], env: [:], workingDirectory: "/tmp", kind: .claudeCode, statusBootstrap: .viaHook)
        )
    }

    func host(sessions: [SessionViewModel], root: PaneNode) throws -> Harness {
        let recorder = Recorder()
        let hosting = NSHostingView(rootView: Self.paneView(
            sessions: sessions, tree: try PaneTree(root: root), recorder: recorder
        ))
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        hosting.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.alphaValue = 0
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        return Harness(window: window, hosting: hosting, recorder: recorder, sessions: sessions)
    }

    private func twoPanes(_ a: SessionViewModel, _ b: SessionViewModel) -> PaneNode {
        .split(PaneSplit(id: PaneID("S"), axis: .horizontal,
            children: [.leaf(id: PaneID("A"), session: a.id), .leaf(id: PaneID("B"), session: b.id)], weights: [0.5, 0.5]))
    }

    // MARK: - 分割線のドラッグ（ADR 0116）

    @Test func 分割線のドラッグ中はレイアウトを確定せず離したときに1回だけ確定する() throws {
        let a = Self.makeSession(), b = Self.makeSession()
        let root = twoPanes(a, b)
        let h = try host(sessions: [a, b], root: root)
        defer { h.window.close() }
        let divider = try #require(try PaneTree(root: root).frames(in: h.size, spacing: DSSpacing.s).dividers.first)
        let start = CGPoint(x: divider.rect.midX, y: divider.rect.midY)

        h.window.sendEvent(h.event(.leftMouseDown, at: start))
        for dx in [10.0, 30.0, 60.0] {
            h.window.sendEvent(h.event(.leftMouseDragged, at: CGPoint(x: start.x + dx, y: start.y)))
            h.hosting.layoutSubtreeIfNeeded()
            #expect(h.recorder.actions.isEmpty, "ドラッグ中（dx=\(dx)）にレイアウトを確定した（メインスレッドが固まる ADR 0116 の回帰）")
        }
        h.window.sendEvent(h.event(.leftMouseUp, at: CGPoint(x: start.x + 60, y: start.y)))

        #expect(h.recorder.actions.count == 1)
        guard case .setDivider(let id, let fraction)? = h.recorder.actions.first else {
            Issue.record("離したときに .setDivider が流れない: \(h.recorder.actions)"); return
        }
        #expect(id == divider.id)
        #expect(fraction > 0.5, "右へ動かしたのに左側の取り分が増えていない: \(fraction)")
    }

    // MARK: - タイルのドラッグ開始

    @Test func ヘッダーを掴んで動かすとタイルのドラッグが始まる() throws {
        let a = Self.makeSession(), b = Self.makeSession()
        let h = try host(sessions: [a, b], root: twoPanes(a, b))
        defer { h.window.close() }
        // ドラッグが始まると、つかんだタイルの荷物（public.json）がドラッグ用のペーストボードに載る。
        let dragBoard = NSPasteboard(name: .drag)
        dragBoard.clearContents()

        let start = CGPoint(x: 150, y: 14) // 左のタイルのヘッダー
        h.window.sendEvent(h.event(.leftMouseDown, at: start))
        for step in [4.0, 12.0, 30.0] {
            h.window.sendEvent(h.event(.leftMouseDragged, at: CGPoint(x: start.x + step, y: start.y + step / 2)))
        }
        let types = dragBoard.types ?? []
        h.window.sendEvent(h.event(.leftMouseUp, at: CGPoint(x: start.x + 30, y: start.y + 15)))

        #expect(types.contains(.init("public.json")), "ヘッダーを動かしてもドラッグが始まらない（`.draggable` をゼロ距離 DragGesture より先に適用していない疑い）")
    }

    // MARK: - タイルのビューの同一性

    @Test func レイアウトを変えてもタイルの端末ビューは作り直されず新しい位置へ移る() throws {
        let a = Self.makeSession(), b = Self.makeSession(), c = Self.makeSession()
        let h = try host(sessions: [a, b, c], root: twoPanes(a, b))
        defer { h.window.close() }

        func mount(_ session: SessionViewModel) throws -> NSView {
            try #require(session.terminalCoordinator.hostingView.superview, "端末ビューがどこにも載っていない")
        }
        let mountA = try mount(a), mountB = try mount(b)

        // 左右を入れ替え、さらに3枚目を縦に差し込む（どちらもレイアウトの変更）。
        try h.show(twoPanes(b, a))
        #expect(try mount(a) === mountA, "A のタイルのビューが作り直された（端末が空白になる）")
        #expect(try mount(b) === mountB, "B のタイルのビューが作り直された（端末が空白になる）")
        let framesSwapped = try PaneTree(root: twoPanes(b, a)).frames(in: h.size, spacing: DSSpacing.s).tiles
        for (session, tile) in [(a, framesSwapped[1]), (b, framesSwapped[0])] {
            let frame = session.terminalCoordinator.hostingView.convert(session.terminalCoordinator.hostingView.bounds, to: h.hosting)
            #expect(tile.rect.contains(CGPoint(x: frame.midX, y: h.size.height - frame.midY)), "端末ビューが新しいタイルの位置にない")
        }

        let three = PaneNode.split(PaneSplit(id: PaneID("S"), axis: .horizontal,
            children: [.leaf(id: PaneID("B"), session: b.id),
                       .split(PaneSplit(id: PaneID("T"), axis: .vertical,
                                        children: [.leaf(id: PaneID("A"), session: a.id), .leaf(id: PaneID("C"), session: c.id)],
                                        weights: [0.5, 0.5]))],
            weights: [0.5, 0.5]))
        try h.show(three)
        #expect(try mount(a) === mountA, "A のタイルのビューが作り直された（端末が空白になる）")
        #expect(try mount(b) === mountB, "B のタイルのビューが作り直された（端末が空白になる）")
    }
}
