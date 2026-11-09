import AgentDomain
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

/// 実データの長い履歴で「遡る 1 回」と「遡った後の 1 回の更新」のメインスレッド時間を測る。
/// `PHLOX_TRANSCRIPT_BENCH=<[ChatItem] の JSON>` のときだけ走る。結果は標準出力の `BENCH` 行。
/// 遡りは利用者と同じスクロール入力（上端で引いて離す）で起こし、読み上げの経路は使わない。
@Suite("履歴遡りの計測", .serialized)
@MainActor
struct TranscriptHistoryScrollBenchmark {
    nonisolated static let environment = ProcessInfo.processInfo.environment
    nonisolated static let fixturePath = environment["PHLOX_TRANSCRIPT_BENCH"]
    nonisolated static let stages = Int(environment["PHLOX_TRANSCRIPT_BENCH_STAGES"] ?? "") ?? 12

    @Test(.enabled(if: fixturePath != nil))
    func expandStages() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: try #require(Self.fixturePath)))
        let items = try JSONDecoder().decode([ChatItem].self, from: data)
        if let pidFile = Self.environment["PHLOX_TRANSCRIPT_BENCH_PIDFILE"] {
            try "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)
        }
        let model = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.claudeCode), client: DisconnectedHarnessClient(),
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-bench"
        )
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
        defer { window.close() }

        let initial = await measure { host.layoutSubtreeIfNeeded(); await drainMain() }
        let scroll = try #require(scrollView(host))
        try await attachScrollObserver(host)
        print("BENCH items=\(items.count) blocks=\(ChatTranscriptGrouping.blockCount(of: items)) initial_ms=\(initial) doc_h=\(documentHeight(scroll))")

        var width: CGFloat = 900
        for stage in 1...Self.stages {
            let before = documentHeight(scroll)
            let wheel = startPull(scroll)
            try await Task.sleep(for: .milliseconds(30))
            let expand = await measure {
                wheel.testPhase = .ended
                NSApp.sendEvent(wheel)
                host.layoutSubtreeIfNeeded()
                await drainMain()
                host.layoutSubtreeIfNeeded()
            }
            width = width == 900 ? 899 : 900
            let resize = await measure {
                window.setContentSize(NSSize(width: width, height: 800))
                host.layoutSubtreeIfNeeded()
            }
            let append = await measure {
                host.rootView = ChatTranscriptView(viewModel: model, transcript: items + [
                    .agentMessage(id: "bench-tail-\(stage)", text: "streaming \(stage)", timestamp: .distantPast)
                ])
                host.layoutSubtreeIfNeeded()
                await drainMain()
            }
            let after = documentHeight(scroll)
            print("BENCH stage=\(stage) doc_h=\(before)->\(after) expand_ms=\(expand) resize_ms=\(resize) append_ms=\(append)")
        }
    }

    @Test(.enabled(if: fixturePath != nil))
    func jumpToEarliestInput() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: try #require(Self.fixturePath)))
        let items = try JSONDecoder().decode([ChatItem].self, from: data)
        let earliestInput = try #require(items.first { if case .userMessage = $0 { true } else { false } }).id
        let model = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.claudeCode), client: DisconnectedHarnessClient(),
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-bench"
        )
        _ = NSApplication.shared
        let target = TargetBox()
        let binding = Binding(get: { target.id }, set: { target.id = $0 })
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items, requestedScrollTarget: binding))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await drainMain()
        let scroll = try #require(scrollView(host))
        let before = documentHeight(scroll)
        let jump = await measure {
            target.id = earliestInput
            host.rootView = ChatTranscriptView(viewModel: model, transcript: items, requestedScrollTarget: binding)
            host.layoutSubtreeIfNeeded()
            await drainMain()
            host.layoutSubtreeIfNeeded()
        }
        let append = await measure {
            host.rootView = ChatTranscriptView(viewModel: model, transcript: items + [
                .agentMessage(id: "bench-tail-jump", text: "streaming", timestamp: .distantPast)
            ], requestedScrollTarget: binding)
            host.layoutSubtreeIfNeeded()
            await drainMain()
        }
        print("BENCH jump doc_h=\(before)->\(documentHeight(scroll)) jump_ms=\(jump) append_ms=\(append)")
    }

    private func startPull(_ scroll: NSScrollView) -> BenchWheelEvent {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        let wheel = BenchWheelEvent()
        wheel.testWindow = scroll.window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .began
        wheel.delta = 20
        NSApp.sendEvent(wheel)
        wheel.testPhase = .changed
        wheel.delta = 60
        NSApp.sendEvent(wheel)
        return wheel
    }

    private func attachScrollObserver(_ host: NSView) async throws {
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            let resolvers = views(host).compactMap { $0 as? ChatAutoFollowScrollObserver.ResolverView }
            if !resolvers.isEmpty {
                resolvers.forEach { $0.onResolve?($0) }
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("スクロール入力の監視が取り付かなかった")
    }

    private func measure(_ body: () async -> Void) async -> Int {
        let start = ContinuousClock.now
        await body()
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func drainMain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func documentHeight(_ scroll: NSScrollView) -> Int {
        Int(scroll.documentView?.frame.height ?? -1)
    }

    private func views(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(views)
    }

    private func scrollView(_ root: NSView) -> NSScrollView? {
        views(root).lazy.compactMap { $0 as? NSScrollView }.first
    }
}

private final class BenchWheelEvent: NSEvent {
    var testWindow: NSWindow?
    private let eventTimestamp = ProcessInfo.processInfo.systemUptime
    var testLocation = NSPoint.zero
    var delta: CGFloat = 10
    var testPhase: NSEvent.Phase = []
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
    override var momentumPhase: NSEvent.Phase { [] }
}

private final class TargetBox {
    var id: String?
}
