import AppKit
import Foundation
import os
import SwiftUI
import Testing
@testable import DesignSystem

/// opt-inの配置/slide観測用。未実行のpassや記録だけで「中間幅なし」「slide維持」とは判定しない。
@Suite("PaneAllocationPreflight", .serialized)
@MainActor
struct PaneAllocationPreflight {
    @Test(arguments: AllocationEdge.allCases)
    func recordAllocationAndSlide(edge: AllocationEdge) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PANE_ALLOCATION_PREFLIGHT_OUT"], !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path).appendingPathComponent(edge.rawValue)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        let previous = app.activationPolicy()
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { app.setActivationPolicy(previous) }
        let state = AllocationState()
        let log = AllocationLog()
        let refs = AllocationNativeViews()
        let host = NSHostingView(rootView: AllocationFixture(edge: edge, state: state, log: log, refs: refs))
        host.frame = NSRect(x: 0, y: 0, width: 1_000, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ペイン割当と内部slideの観測"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCenter(host: host, refs: refs, width: 1_000)

        for open in [true, false] {
            log.phase(open ? "opening" : "closing")
            state.open = open
            // Layoutの測定は全てlogに残る。native座標系列は描画完了を表さない。
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(10))
                refs.record(in: host, log: log)
            }
            let expected = 1_000 - (open ? 160 + DSLayout.paneSeparatorWidth : 0)
            try await waitForCenter(host: host, refs: refs, width: expected)
            refs.record(in: host, log: log)
            if !open {
                #expect(refs.views["slide"] == nil, "closed content must unload after the existing 300ms delay")
            }
        }

        // closed hit testingやunloadの代替ではなく、境界の子が開始する独自animationだけ検査。
        log.phase("local-animation")
        state.open = true
        try await waitForCenter(host: host, refs: refs, width: 1_000 - 160 - DSLayout.paneSeparatorWidth)
        try await Task.sleep(for: .milliseconds(350))
        state.local.toggle()
        let deadline = ContinuousClock.now + .seconds(3)
        while !log.entries().contains(where: { $0.role == "local" && $0.localAnimation == true && $0.disablesAnimations == false }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log.entries()).write(to: output.appendingPathComponent("allocation-and-slide.json"))
        let metadata: [String: String] = [
            "variant": env["PANE_ALLOCATION_VARIANT"] ?? "unspecified",
            "edge": edge.rawValue,
            "reduceMotion": "\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)",
            "role": "preflight; endpoint/local assertions only; proposal/slide regression not yet established",
            "window": "1000x600; pane160+separator",
        ]
        try encoder.encode(metadata).write(to: output.appendingPathComponent("metadata.json"))
        #expect(log.entries().contains { $0.role == "local" && $0.localAnimation == true && $0.disablesAnimations == false })
    }

    private func waitForCenter(host: NSView, refs: AllocationNativeViews, width: CGFloat) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            host.layoutSubtreeIfNeeded()
            if let actual = refs.views["center"], abs(actual.bounds.width - width) <= 1 { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        throw NSError(domain: "PaneAllocationPreflight.Timeout", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "center model width did not reach the HStack endpoint \(width)"])
    }
}

enum AllocationEdge: String, CaseIterable, Sendable { case leading, trailing }

private final class AllocationLog: Sendable {
    struct Entry: Codable, Sendable {
        let phase: String
        let event: String
        let role: String
        let uptime: TimeInterval
        var proposedWidth: String?
        var measuredWidth: CGFloat?
        var frame: CGRect?
        var visibleRect: CGRect?
        var presentationFrame: CGRect?
        var localAnimation: Bool?
        var disablesAnimations: Bool?
    }
    private struct State: Sendable { var phase = "initial"; var entries: [Entry] = [] }
    // LayoutはSendable。測定中にViewのStateへ戻さず、ログだけをlock内で変更する。
    private let storage = OSAllocatedUnfairLock(initialState: State())
    func phase(_ phase: String) { storage.withLock { $0.phase = phase } }
    func append(event: String, role: String, proposedWidth: CGFloat? = nil, measuredWidth: CGFloat? = nil,
                frame: CGRect? = nil, visibleRect: CGRect? = nil, presentationFrame: CGRect? = nil,
                localAnimation: Bool? = nil, disablesAnimations: Bool? = nil) {
        storage.withLock { state in
            state.entries.append(Entry(phase: state.phase, event: event, role: role,
                                       uptime: ProcessInfo.processInfo.systemUptime,
                                       proposedWidth: proposedWidth.map { String(describing: $0) },
                                       measuredWidth: measuredWidth, frame: frame, visibleRect: visibleRect,
                                       presentationFrame: presentationFrame, localAnimation: localAnimation,
                                       disablesAnimations: disablesAnimations))
        }
    }
    func entries() -> [Entry] { storage.withLock { $0.entries } }
}

private struct AllocationProposalTrace: Layout {
    let role: String
    let log: AllocationLog
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        log.append(event: "measure", role: role, proposedWidth: proposal.width, measuredWidth: size.width)
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log.append(event: "place", role: role, proposedWidth: proposal.width, measuredWidth: bounds.width)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

@MainActor @Observable
private final class AllocationState { var open = false; var local = false }

@MainActor
private final class AllocationNativeViews {
    var views: [String: NSView] = [:]
    func record(in host: NSView, log: AllocationLog) {
        for (name, view) in views {
            log.append(event: "native-frame", role: name, frame: view.convert(view.bounds, to: host),
                       visibleRect: view.visibleRect, presentationFrame: view.layer?.presentation()?.frame)
        }
    }
}

@MainActor
private struct AllocationNativeProbe: NSViewRepresentable {
    let role: String
    let local: Bool
    let log: AllocationLog
    let refs: AllocationNativeViews
    final class Coordinator {
        let role: String
        let log: AllocationLog
        let refs: AllocationNativeViews
        init(role: String, log: AllocationLog, refs: AllocationNativeViews) {
            self.role = role; self.log = log; self.refs = refs
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(role: role, log: log, refs: refs) }
    func makeNSView(context: Context) -> NSView {
        log.append(event: "make-view", role: role)
        return NSView(frame: .zero)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if coordinator.refs.views[coordinator.role] === view {
            coordinator.refs.views.removeValue(forKey: coordinator.role)
        }
        coordinator.log.append(event: "dismantle-view", role: coordinator.role)
    }
    func updateNSView(_ view: NSView, context: Context) {
        refs.views[role] = view
        log.append(event: "transaction", role: role,
                   localAnimation: context.transaction.animation == .linear(duration: 0.4),
                   disablesAnimations: context.transaction.disablesAnimations)
    }
}

@MainActor
private struct AllocationFixture: View {
    let edge: AllocationEdge
    let state: AllocationState
    let log: AllocationLog
    let refs: AllocationNativeViews
    var body: some View {
        HStack(spacing: 0) {
            if edge == .leading { pane }
            GeometryReader { geometry in
                VStack {
                    AllocationProposalTrace(role: "body", log: log) {
                        Text(String(repeating: "本文に似た折返し測定です。", count: 70))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: geometry.size.width * 0.8)
                    Spacer()
                    AllocationProposalTrace(role: "composer", log: log) {
                        Text("入力欄相当").frame(maxWidth: .infinity)
                    }
                    .frame(width: geometry.size.width * 0.8)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(probe("center"))
            // 配置境界は中央だけでなく、下のHStack全体に掛ける。
            if edge == .trailing { pane }
        }
        .dsPaneLayoutBoundary()
        .dsPaneAnimation(value: state.open)
    }
    private var pane: some View {
        DSSidePane(edge: edge == .leading ? .leading : .trailing, isOpen: state.open, width: 160, unloadsWhenClosed: true) {
            VStack {
                probe("slide").frame(height: 40)
                probe("local").opacity(state.local ? 0.5 : 1)
                    .animation(.linear(duration: 0.4), value: state.local)
            }
            .frame(width: 160, height: 600)
            .background(Color.gray)
        }
    }
    private func probe(_ role: String) -> some View {
        AllocationNativeProbe(role: role, local: state.local, log: log, refs: refs)
    }
}
