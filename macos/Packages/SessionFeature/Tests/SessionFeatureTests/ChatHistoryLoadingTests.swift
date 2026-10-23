import AgentDomain
import AppKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("チャット履歴のスクロール読み込み", .serialized)
@MainActor
struct ChatHistoryLoadingTests {
    @Test func scrollInputRequiresTopDirectionAndOwnViewport() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let document = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        scroll.documentView = document
        let window = makeWindow(scroll)
        defer { window.close() }
        var requests = 0
        var releases = 0
        let bridge = ChatAutoFollowScrollEventBridge(controller: ChatAutoFollowController(), onScrollPastTop: { requests += 1 }, onScrollReleased: { releases += 1 })
        bridge.attach(to: scroll)
        defer { bridge.detach() }
        let event = HistoryWheelEvent()
        event.testWindow = window
        event.testLocation = NSPoint(x: 150, y: 100)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        bridge.handleScrollWheel(event)
        #expect(requests == 0)
        scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(requests == 0, "レイアウト・プログラムによる先頭移動では追加しない")
        event.delta = -10
        bridge.handleScrollWheel(event)
        event.delta = 10
        event.testMomentumPhase = .changed
        bridge.handleScrollWheel(event)
        event.testMomentumPhase = []
        event.testLocation = NSPoint(x: 500, y: 100)
        bridge.handleScrollWheel(event)
        #expect(requests == 0)
        event.testLocation = NSPoint(x: 150, y: 100)
        event.testPhase = .changed
        event.delta = 60
        bridge.handleScrollWheel(event)
        #expect(requests == 0, "観測開始前から続くジェスチャーは引き継がない")
        event.testPhase = .began
        event.delta = 10
        bridge.handleScrollWheel(event)
        event.testPhase = .changed
        event.delta = 49
        bridge.handleScrollWheel(event)
        #expect(requests == 0, "上端での追加スクロールが59ptなら表示しない")
        event.delta = 1
        bridge.handleScrollWheel(event)
        #expect(requests == 1, "60ptで初めてローダーを表示する")
        event.delta = 60
        bridge.handleScrollWheel(event)
        #expect(requests == 1, "同じジェスチャーでは1回だけ追加する")
        #expect(releases == 0, "スクロール中は履歴を追加しない")
        event.testPhase = .ended
        bridge.handleScrollWheel(event)
        bridge.handleScrollWheel(event)
        #expect(releases == 1, "指を離したときに1回だけ追加する")
        event.testPhase = .began
        bridge.handleScrollWheel(event)
        #expect(requests == 2)
        bridge.detach()
        bridge.handleScrollWheel(event)
        #expect(requests == 2)
    }

    @Test(arguments: [false, true])
    func loaderPrecedesExpansionAndKeepsAnchor(grid: Bool) async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let context: TranscriptPresentationContext = grid ? .gridTile : .single
        let model = makeModel()
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items, presentationContext: context))
        let window = makeWindow(host)
        defer { window.close() }
        let initial = 130 - TranscriptWindow.defaultLimit(for: context)
        try await wait(host, stage: "initial grid=\(grid)") { hiddenCount(host) == initial }
        #expect(element(host, "ChatTranscript.loadEarlier") == nil)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        host.layoutSubtreeIfNeeded()
        let previousHeight = try #require(scroll.documentView).frame.height
        let wheel = try startHistoryPull(host)
        try await wait(host, stage: "loader grid=\(grid)") { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == initial, "ローダーを表示してから履歴を追加する")
        try await Task.sleep(for: .milliseconds(400))
        #expect(hiddenCount(host) == initial, "押し続けている間は履歴を追加しない")
        #expect(element(host, "ChatTranscript.historyLoading") != nil)
        try snapshot(host, name: grid ? "history-grid-loading" : "history-single-loading")
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        // グリッドの既存描画予算は16件刻みなので、窓を50増やすと64件まで描画する。
        try await wait(host, stage: "expansion grid=\(grid)") { hiddenCount(host) == (grid ? 66 : 30) }
        try await wait(host, stage: "anchor grid=\(grid)") { scroll.contentView.bounds.minY > 0 }
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        let insertedHeight = try #require(scroll.documentView).frame.height - previousHeight
        #expect(abs(scroll.contentView.bounds.minY - insertedHeight) < 3, "追加前の先頭が上端に残る")
        try snapshot(host, name: grid ? "history-grid-expanded" : "history-single-expanded")
    }

    @Test func applicationScrollEventStartsLoader() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == 80)
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test func switchingSessionCancelsPendingLoad() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        host.rootView = ChatTranscriptView(viewModel: makeModel(), transcript: items)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        #expect(hiddenCount(host) == 80)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func scrollingAwayCancelsPendingLoad() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        #expect(hiddenCount(host) == 80)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        #expect(abs(scroll.contentView.bounds.minY - 200) < 3)
    }

    @Test(arguments: [false, true])
    func sessionSwitchResetsAccumulatedPull(armed: Bool) async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) {
            hiddenCount(host) == 80 && scrollViews(host).first.map(ChatAutoFollowGeometry.isAtBottom) == true
        }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = HistoryWheelEvent()
        wheel.testWindow = window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .began
        wheel.delta = 20
        NSApp.sendEvent(wheel)
        wheel.testPhase = .changed
        wheel.delta = armed ? 40 : 30
        NSApp.sendEvent(wheel)
        try await wait(host) { (element(host, "ChatTranscript.historyLoading") != nil) == armed }
        host.rootView = ChatTranscriptView(viewModel: makeModel(), transcript: items)
        try await wait(host) {
            element(host, "ChatTranscript.historyLoading") == nil && scrollViews(host).first.map(ChatAutoFollowGeometry.isAtBottom) == true
        }
        let newScroll = try #require(scrollViews(host).first)
        newScroll.contentView.scroll(to: .zero)
        wheel.testLocation = newScroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .changed
        wheel.delta = 10
        NSApp.sendEvent(wheel)
        host.layoutSubtreeIfNeeded()
        #expect(element(host, "ChatTranscript.historyLoading") == nil, "切替前の距離を持ち越さない")
        wheel.delta = 50
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        #expect(hiddenCount(host) == 80, "切替前のジェスチャーを新しいセッションへ引き継がない")
        let newWheel = try startHistoryPull(host)
        try await wait(host, stage: "切替後の新しい操作でローダーを表示") { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == 80)
        newWheel.testPhase = .ended
        NSApp.sendEvent(newWheel)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test func scrollInputFindsViewportInFlippedContent() {
        let root = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = makeWindow(root)
        defer { window.close() }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        scroll.documentView = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        root.addSubview(scroll)
        scroll.contentView.scroll(to: .zero)
        var requests = 0
        let bridge = ChatAutoFollowScrollEventBridge(controller: ChatAutoFollowController(), onScrollPastTop: { requests += 1 })
        bridge.attach(to: scroll)
        defer { bridge.detach() }
        let event = HistoryWheelEvent()
        event.delta = 60
        event.testPhase = .began
        event.testWindow = window
        event.testLocation = scroll.convert(NSPoint(x: 150, y: 20), to: nil)
        bridge.handleScrollWheel(event)
        #expect(requests == 1)
    }

    @Test func exhaustedHistoryDoesNotLoadAgain() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: Array(items.suffix(5))))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 0 }
        try loadEarlier(host)
        try await Task.sleep(for: .milliseconds(350))
        #expect(hiddenCount(host) == 0)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func wheelWithoutPhasesLoadsOnlyAfterInputStops() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = HistoryWheelEvent()
        wheel.testWindow = window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.delta = 30
        NSApp.sendEvent(wheel)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(80))
            NSApp.sendEvent(wheel)
            #expect(hiddenCount(host) == 80)
        }
        try await wait(host) { hiddenCount(host) == 30 }
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func cancelledPullDoesNotLoadAndAccessibilityActionStillLoads() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        wheel.testPhase = .cancelled
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        #expect(hiddenCount(host) == 80)
        try loadEarlier(host)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test func cometHasProgressSemanticsAndCanRenderWithoutMotion() throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: CometLoader())
        let window = makeWindow(host)
        defer { window.close() }
        let progress = try #require(element(host, "ChatTranscript.historyLoading"))
        #expect(attribute(progress, "accessibilityRole") as? NSAccessibility.Role == .busyIndicator)
        #expect(attribute(progress, "accessibilityLabel") as? String == "以前のメッセージを読み込み中")
        let loader = CometLoader.Ring(reduceMotion: true).frame(width: 22, height: 22)
        let renderer = ImageRenderer(content: loader)
        let image = try #require(renderer.nsImage)
        #expect(image.size == NSSize(width: 22, height: 22))
        if let output = ProcessInfo.processInfo.environment["PHLOX_COMET_SNAPSHOT_OUTPUT"] {
            let url = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for light in [false, true] {
                let sample = loader.padding(24).background(light ? Color(white: 0.94) : Color(white: 0.07))
                let sampleRenderer = ImageRenderer(content: sample)
                sampleRenderer.scale = 3
                let rendered = try #require(sampleRenderer.nsImage)
                let tiff = try #require(rendered.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("comet-\(light ? "light" : "dark").png"))
            }
        }
    }

    private var items: [ChatItem] {
        (0..<130).map { .userMessage(id: "history-\($0)", text: "メッセージ \($0)", timestamp: .distantPast) }
    }

    private func makeModel() -> ChatSessionViewModel {
        ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: DisconnectedHarnessClient(),
                            approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-history-test")
    }

    private func makeWindow(_ content: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        content.layoutSubtreeIfNeeded()
        return window
    }

    private func element(_ root: Any, _ id: String) -> AnyObject? {
        elements(root).first { attribute($0, "accessibilityIdentifier") as? String == id }
    }

    private func elements(_ root: Any) -> [AnyObject] {
        var pending: [AnyObject] = [root as AnyObject]
        var seen = Set<ObjectIdentifier>()
        var result: [AnyObject] = []
        while let object = pending.popLast() {
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            result.append(object)
            if let children = attribute(object, "accessibilityChildren") as? [AnyObject] { pending += children }
            if let view = object as? NSView { pending += view.subviews }
        }
        return result
    }

    private func hiddenCount(_ root: NSView) -> Int? {
        guard let history = element(root, "ChatTranscript.history"),
              let value = attribute(history, "accessibilityLabel") as? String else { return nil }
        return value.split(separator: " ").compactMap { Int($0) }.first
    }

    private func loadEarlier(_ root: NSView) throws {
        let history = try #require(element(root, "ChatTranscript.history"))
        let actions = try #require(attribute(history, "accessibilityCustomActions") as? [NSAccessibilityCustomAction])
        let action = try #require(actions.first { $0.name == "以前のメッセージを読み込む" })
        try #require(action.handler?() == true)
    }

    private func startHistoryPull(_ host: NSView) throws -> HistoryWheelEvent {
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        host.layoutSubtreeIfNeeded()
        let wheel = HistoryWheelEvent()
        wheel.testWindow = scroll.window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .began
        wheel.delta = 20
        NSApp.sendEvent(wheel)
        wheel.testPhase = .changed
        wheel.delta = 40
        NSApp.sendEvent(wheel)
        return wheel
    }

    private func wait(_ host: NSView, stage: String = "", sourceLine: Int = #line, until ready: () -> Bool) async throws {
        // 描画だけでなく、次のrun loopで取り付くAppKitのイベント購読も待つ。
        await Task.yield()
        let deadline = ContinuousClock.now + .seconds(3)
        repeat {
            host.layoutSubtreeIfNeeded()
            // 画面外のホストでは、遅延した入力監視の取り付けも明示的に完了させる。
            for resolver in elements(host).compactMap({ $0 as? ChatAutoFollowScrollObserver.ResolverView }) {
                resolver.onResolve?(resolver)
            }
            if ready() {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                if ready() { return }
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        if let scroll = scrollViews(host).first {
            print("履歴状態: line=\(sourceLine) \(stage) clip=\(scroll.contentView.bounds) document=\(String(describing: scroll.documentView?.frame))")
        }
        for object in elements(host) {
            if let id = attribute(object, "accessibilityIdentifier") as? String, id.hasPrefix("ChatTranscript") {
                print("履歴AX: \(id) role=\(String(describing: attribute(object, "accessibilityRole"))) label=\(String(describing: attribute(object, "accessibilityLabel"))) value=\(String(describing: attribute(object, "accessibilityValue")))")
            }
        }
        try #require(ready(), "UI が期待する状態へ遷移しなかった: line=\(sourceLine) \(stage)")
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    private func attribute(_ root: AnyObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard root.responds(to: selector) else { return nil }
        return root.perform(selector)?.takeUnretainedValue()
    }

    private func enableAccessibility() -> () -> Void {
        _ = NSApplication.shared
        let key = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(key)
        NSApp.accessibilitySetValue(true, forAttribute: key)
        return { NSApp.accessibilitySetValue(previous ?? false, forAttribute: key) }
    }

    private func snapshot(_ host: NSView, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["PHLOX_COMET_SNAPSHOT_OUTPUT"] else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private final class FlippedHistoryDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class HistoryWheelEvent: NSEvent {
    var testWindow: NSWindow?
    private let eventTimestamp = ProcessInfo.processInfo.systemUptime
    var testLocation = NSPoint.zero
    var delta: CGFloat = 10
    var testPhase: NSEvent.Phase = []
    var testMomentumPhase: NSEvent.Phase = []
    override var type: NSEvent.EventType { .scrollWheel }
    override var scrollingDeltaX: CGFloat { 0 }
    override var deltaY: CGFloat { delta }
    override var deltaX: CGFloat { 0 }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var window: NSWindow? { testWindow }
    override var windowNumber: Int { testWindow?.windowNumber ?? 0 }
    override var timestamp: TimeInterval { eventTimestamp }
    override var locationInWindow: NSPoint { testLocation }
    override var scrollingDeltaY: CGFloat { delta }
    override var phase: NSEvent.Phase { testPhase }
    override var momentumPhase: NSEvent.Phase { testMomentumPhase }
}
