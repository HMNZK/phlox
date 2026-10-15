import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

// Exercises real pane allocation and native slide positions in a visible hosting hierarchy.
@Suite("DSPaneProgressIntegration", .serialized)
@MainActor
struct DSPaneProgressIntegrationTests {
    @Test(arguments: [false, true])
    func actualPaneAllocationAndRetarget(leading: Bool) async throws {
        _ = NSApplication.shared
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        print("PaneIntegration leading=\(leading) OS motion=\(motion)")
        let state = IntegrationInputs()
        let log = IntegrationLog()
        defer { log.dump() }
        let host = NSHostingView(rootView: IntegrationFixture(state: state, log: log, leading: leading))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        #expect(window.isVisible)
        try await poll(host, log) { log.samples.last?.centerWidth == 800 }

        var disabled = Transaction(animation: nil)
        disabled.disablesAnimations = true
        log.phase = "disabled-open"
        withTransaction(disabled) { state.open = true }
        try await poll(host, log) { log.samples.last?.centerWidth == 600 }
        let first = try #require(log.samples.first { $0.phase == "disabled-open" })
        #expect(first.centerWidth == 600)
        #expect(log.centerUpdates.first { $0.phase == "disabled-open" }?.width == 600)
        let flags = try #require(log.flags.first { $0.phase == "disabled-open" && $0.role == "pane" })
        #expect(flags.disabled && flags.marker && flags.animation == nil)

        log.phase = "reset"
        withTransaction(disabled) { state.open = false }
        try await poll(host, log) { log.samples.last?.centerWidth == 800 }
        let startX = try #require(log.samples.last?.paneX)
        let endX: CGFloat = leading ? 0 : 601 // 199pt content + 1pt DS separator
        log.phase = "open"
        withTransaction(Transaction()) {
            state.open = true
            state.local.toggle()
        }
        try await poll(host, log) { log.samples.last?.centerWidth == 600 }
        let normal = log.samples.filter { $0.phase == "open" }
        let openCallbacks = log.centerUpdates.filter { $0.phase == "open" }
        #expect(!normal.isEmpty && !openCallbacks.isEmpty)
        #expect(openCallbacks.contains { abs($0.width - 600) < 0.01 })
        let simultaneousLocal = try #require(log.flags.last { $0.phase == "open" && $0.role == "local" && $0.value == state.local })
        #expect(simultaneousLocal.animation == Animation.linear(duration: 0.4))
        #expect(normal.allSatisfy { abs($0.centerWidth - 800) < 0.01 || abs($0.centerWidth - 600) < 0.01 })
        #expect(normal.allSatisfy { abs($0.paneX - endX) < 0.01 || abs($0.centerWidth - 800) < 0.01 })
        #expect(log.centerUpdates.filter { $0.phase == "open" }.allSatisfy { abs($0.width - 800) < 0.01 || abs($0.width - 600) < 0.01 })
        let finalX = try #require(normal.last?.paneX)
        #expect(abs(finalX - endX) < 0.01)
        if !motion {
            #expect(normal.contains { $0.paneX > min(startX, endX) + 0.01 && $0.paneX < max(startX, endX) - 0.01 },
                    "No real native intermediate pane position; slide preflight not demonstrated")
        }

        log.phase = "local"
        state.local.toggle()
        try await poll(host, log) { log.flags.contains { $0.phase == "local" && $0.role == "local" && $0.value == state.local } }
        let local = try #require(log.flags.last { $0.phase == "local" && $0.role == "local" && $0.value == state.local })
        #expect(local.animation == Animation.linear(duration: 0.4))

        // Full open -> ordinary animated close, independent from retarget cancellation.
        log.phase = "close"
        state.open = false
        try await poll(host, log) {
            guard let sample = log.samples.last else { return false }
            return abs(sample.centerWidth - 800) < 0.01 && abs(sample.paneX - startX) < 0.01
        }
        let closing = log.samples.filter { $0.phase == "close" }
        let closeCallbacks = log.centerUpdates.filter { $0.phase == "close" }
        #expect(!closing.isEmpty && !closeCallbacks.isEmpty)
        #expect(closing.first?.centerWidth == 800)
        #expect(closing.allSatisfy { abs($0.centerWidth - 800) < 0.01 })
        #expect(closeCallbacks.allSatisfy { abs($0.width - 800) < 0.01 })
        if !motion {
            #expect(closing.contains { $0.paneX > min(startX, endX) + 0.01 && $0.paneX < max(startX, endX) - 0.01 },
                    "No native intermediate close position; ordinary close not demonstrated")
        }

        if !motion {
            log.phase = "reset-retarget"
            withTransaction(disabled) { state.open = false }
            try await poll(host, log) { log.samples.last?.centerWidth == 800 }
            log.phase = "retarget-open"
            let began = ContinuousClock.now
            state.open = true
            try await poll(host, log) {
                guard let sample = log.samples.last else { return false }
                return sample.paneX > min(startX, endX) + 0.01 && sample.paneX < max(startX, endX) - 0.01
            }
            log.phase = "retarget-closed"
            state.open = false
            try await poll(host, log) { log.samples.last?.centerWidth == 800 }
            #expect(log.samples.filter { $0.phase == "retarget-closed" }.allSatisfy { abs($0.centerWidth - 800) < 0.01 })
            // Center may already be 800: native samples above prove it; zero resize callbacks are valid.
            // This callback check is supplementary and intentionally permits an empty collection.
            #expect(log.centerUpdates.filter { $0.phase == "retarget-closed" }.allSatisfy { abs($0.width - 800) < 0.01 })
            log.phase = "retarget-reopen"
            state.open = true
            #expect(began.duration(to: .now) < .milliseconds(180), "Retarget missed 180ms; not validated")
            try await poll(host, log) { log.samples.last?.centerWidth == 600 }
            let reopened = log.samples.filter { $0.phase == "retarget-reopen" }
            let reopenCallbacks = log.centerUpdates.filter { $0.phase == "retarget-reopen" }
            #expect(!reopened.isEmpty && !reopenCallbacks.isEmpty)
            #expect(reopenCallbacks.contains { abs($0.width - 600) < 0.01 })
            #expect(reopened.allSatisfy { abs($0.centerWidth - 800) < 0.01 || abs($0.centerWidth - 600) < 0.01 })
            #expect(reopened.allSatisfy { abs($0.paneX - endX) < 0.01 || abs($0.centerWidth - 800) < 0.01 })
            #expect(reopenCallbacks.allSatisfy { abs($0.width - 800) < 0.01 || abs($0.width - 600) < 0.01 })
        } else {
            print("OS ON: native animated retarget branch not exercised")
        }
        #expect(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == motion)
        #expect(!log.flags.isEmpty)
        #expect(log.flags.allSatisfy { $0.motion == motion })
    }

    private func poll(_ host: NSView, _ log: IntegrationLog, until ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            log.sample()
            if ready() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "DSPaneProgressIntegration.Timeout", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Real pane observation timeout phase=\(log.phase)"])
    }
}

@MainActor @Observable
private final class IntegrationInputs { var open = false; var local = false }

@MainActor
private final class IntegrationLog {
    struct Sample { let phase: String; let centerWidth: CGFloat; let paneX: CGFloat; let uptime: TimeInterval }
    struct Flags { let phase: String; let role: String; let value: Bool; let motion: Bool; let disabled: Bool; let marker: Bool; let animation: Animation? }
    struct CenterUpdate { let phase: String; let width: CGFloat }
    var phase = "initial"
    weak var center: NSView?
    weak var pane: NSView?
    var samples: [Sample] = []
    var flags: [Flags] = []
    var centerUpdates: [CenterUpdate] = []
    func sample() {
        guard let center, let pane else { return }
        samples.append(.init(phase: phase, centerWidth: center.bounds.width,
                             paneX: pane.convert(NSPoint.zero, to: nil).x, uptime: ProcessInfo.processInfo.systemUptime))
    }
    func dump() {
        for s in samples { print("native phase=\(s.phase) center=\(s.centerWidth) paneX=\(s.paneX) uptime=\(s.uptime)") }
        for c in centerUpdates { print("center-callback phase=\(c.phase) width=\(c.width)") }
        for f in flags { print("flags phase=\(f.phase) role=\(f.role) value=\(f.value) motion=\(f.motion) disabled=\(f.disabled) marker=\(f.marker) animation=\(String(describing:f.animation))") }
    }
}

private struct IntegrationFixture: View {
    @Bindable var state: IntegrationInputs
    let log: IntegrationLog
    let leading: Bool
    var body: some View {
        HStack(spacing: 0) {
            if leading { pane }
            Color.gray.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(IntegrationProbe(role: "center", value: state.open, log: log))
            if !leading { pane }
        }
        .dsPaneLayoutBoundary()
        .dsPaneAnimation(value: state.open)
    }
    private var pane: some View {
        DSSidePane(edge: leading ? .leading : .trailing, isOpen: state.open, width: 199) {
            Color.blue.frame(maxHeight: .infinity)
                .background(IntegrationProbe(role: "pane", value: state.open, log: log))
                .overlay {
                    Color.clear.frame(width: state.local ? 2 : 1)
                        .background(IntegrationProbe(role: "local", value: state.local, log: log))
                        .animation(.linear(duration: 0.4), value: state.local)
                }
        }
    }
}

private struct IntegrationProbe: NSViewRepresentable {
    let role: String
    let value: Bool
    let log: IntegrationLog
    @Environment(\.accessibilityReduceMotion) private var motion
    func makeNSView(context: Context) -> NSView {
        let view = IntegrationNativeView(log: log, role: role)
        if role == "center" { log.center = view }
        if role == "pane" { log.pane = view }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        let t = context.transaction
        log.flags.append(.init(phase: log.phase, role: role, value: value, motion: motion,
                               disabled: t.disablesAnimations, marker: t[DSPaneChangeKey.self], animation: t.animation))
    }
}

@MainActor
private final class IntegrationNativeView: NSView {
    let log: IntegrationLog
    let role: String
    init(log: IntegrationLog, role: String) { self.log = log; self.role = role; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if role == "center" { log.centerUpdates.append(.init(phase: log.phase, width: newSize.width)) }
    }
}
