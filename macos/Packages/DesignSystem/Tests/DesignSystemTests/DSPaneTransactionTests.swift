import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

/// SwiftUI自身にtransactionを伝播させる。判定ロジックをテストへ複写しない。
@Suite("DSPaneTransaction", .serialized)
@MainActor
struct DSPaneTransactionTests {
    @Test(arguments: PaneRoute.allCases)
    func layoutBoundaryPreservesPaneOriginAndLocalAnimations(route: PaneRoute) async throws {
        _ = NSApplication.shared
        let expectedReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        print("ReduceMotion test=\(#function) os=\(expectedReduceMotion)")
        let state = PaneTestState()
        let observations = PaneTransactionObservations()
        let host = NSHostingView(rootView: PaneTransactionFixture(state: state, observations: observations))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 0)

        // 開閉値が変化し、同時に本文も更新されたtransaction。
        withTransaction(Transaction()) {
            state.toggle(route)
            state.revision = 1
        }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 1)
        let parent = try #require(observations.last("parent", revision: 1))
        let boundary = try #require(observations.last("boundary", revision: 1))
        #expect(parent.paneChange)
        #expect(parent.animation == (expectedReduceMotion ? nil : DSAnimation.pane))
        #expect(boundary.paneChange) // 子ペインがslideを再設定できるよう印を保持する。
        #expect(boundary.animation == nil)
        #expect(!boundary.disablesAnimations)
        if route == .overlay {
            let overlay = try #require(observations.last("overlay", revision: 1))
            #expect(overlay.paneChange)
            #expect(overlay.animation == (expectedReduceMotion ? nil : DSAnimation.pane))
        }

        // 開閉値が同じ通常の新着。親の明示animationを無条件には止めない。
        withAnimation(.linear(duration: 0.7)) { state.revision = 2 }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 2)
        let normal = try #require(observations.last("boundary", revision: 2))
        #expect(!normal.paneChange)
        #expect(normal.animation == .linear(duration: 0.7))

        // 境界の子が自分で開始するホバー/展開相当の動き。
        withTransaction(Transaction()) {
            state.local.toggle()
            state.revision = 3
        }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 3)
        let local = try #require(observations.last("local", revision: 3))
        #expect(local.animation == .linear(duration: 0.4))
        #expect(!local.disablesAnimations)

        // 同じ更新にローカルの状態変化が混ざっても、子の.animationは再設定できる。
        withTransaction(Transaction()) {
            state.toggle(route)
            state.local.toggle()
            state.revision = 4
        }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 4)
        #expect(observations.last("parent", revision: 4)?.paneChange == true)
        #expect(observations.last("boundary", revision: 4)?.animation == nil)
        #expect(observations.last("local", revision: 4)?.animation == .linear(duration: 0.4))
    }

    @Test(arguments: [PaneRoute.leading, .trailing])
    func paneContentRestoresOnlyChangedSide(route: PaneRoute) async throws {
        _ = NSApplication.shared
        let expectedReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        print("ReduceMotion test=\(#function) os=\(expectedReduceMotion)")
        let state = PaneTestState()
        // 両方を実体化したまま、一方だけを閉じて再び開く。unloadはこの検査に混ぜない。
        state.leading = true
        state.trailing = true
        let observations = PaneTransactionObservations()
        let host = NSHostingView(rootView: PaneTransactionFixture(state: state, observations: observations))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let paneNames = ["leading-pane", "leading-local", "trailing-pane", "trailing-local"]
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 0, additionalNames: paneNames)
        let changedName = route == .leading ? "leading-pane" : "trailing-pane"
        let unchangedName = route == .leading ? "trailing-pane" : "leading-pane"
        for revision in 1...2 {
            withTransaction(Transaction()) {
                state.toggle(route)
                state.revision = revision
            }
            try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: revision, additionalNames: paneNames)
            let changed = try #require(observations.last(changedName, revision: revision))
            let unchanged = try #require(observations.last(unchangedName, revision: revision))
            #expect(changed.animation == (expectedReduceMotion ? nil : DSAnimation.pane))
            #expect(!changed.paneChange)
            #expect(!changed.disablesAnimations)
            #expect(unchanged.animation == nil)
            #expect(unchanged.paneChange)
            #expect(!unchanged.disablesAnimations)
        }

        // 開閉しない通常更新。実ペイン内の子が始めるanimationが両側とも残る。
        withTransaction(Transaction()) {
            state.local.toggle()
            state.revision = 3
        }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 3, additionalNames: paneNames)
        for name in ["leading-local", "trailing-local"] {
            let local = try #require(observations.last(name, revision: 3))
            #expect(local.animation == .linear(duration: 0.4))
            #expect(!local.paneChange)
            #expect(!local.disablesAnimations)
        }

        // ReduceMotionの代わりではない。呼出し元が動きを禁止した場合の契約を別に検査。
        var disabled = Transaction()
        disabled.disablesAnimations = true
        withTransaction(disabled) {
            state.toggle(route)
            state.revision = 4
        }
        try await awaitObservation(host: host, observations: observations, expectedReduceMotion: expectedReduceMotion, revision: 4, additionalNames: paneNames)
        for name in [changedName, unchangedName] {
            let content = try #require(observations.last(name, revision: 4))
            #expect(content.animation == nil)
            #expect(content.disablesAnimations)
            #expect(content.paneChange) // 内側guardが再設定/印消費を行わない。
        }
    }

    private func awaitObservation(host: NSView, observations: PaneTransactionObservations, expectedReduceMotion: Bool, revision: Int,
                                  additionalNames: [String] = []) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        repeat {
            host.layoutSubtreeIfNeeded()
            let names = ["parent", "boundary", "local", "overlay"] + additionalNames
            if names.allSatisfy({ observations.last($0, revision: revision) != nil }) {
                #expect(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == expectedReduceMotion,
                        "OS Reduce Motion changed during this test")
                var observedValues: [String] = []
                for name in names {
                    let observation = try #require(observations.last(name, revision: revision))
                    observedValues.append("\(name)=\(observation.reduceMotion)")
                    #expect(observation.reduceMotion == expectedReduceMotion,
                            "SwiftUI Reduce Motion at \(name) disagrees with NSWorkspace")
                }
                print("ReduceMotion revision=\(revision) os=\(expectedReduceMotion) observed=\(observedValues.joined(separator: ","))")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        throw NSError(domain: "DSPaneTransactionTests.Timeout", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "SwiftUI did not deliver probe updates for revision \(revision)"])
    }
}

enum PaneRoute: String, CaseIterable, Sendable {
    case leading, trailing, overlay
}

@MainActor @Observable
private final class PaneTestState {
    var leading = false
    var trailing = false
    var overlay = false
    var local = false
    var revision = 0

    func toggle(_ route: PaneRoute) {
        switch route {
        case .leading: leading.toggle()
        case .trailing: trailing.toggle()
        case .overlay: overlay.toggle()
        }
    }
}

@MainActor
private final class PaneTransactionObservations {
    struct Observation {
        let name: String
        let revision: Int
        let paneChange: Bool
        let animation: Animation?
        let disablesAnimations: Bool
        let reduceMotion: Bool
    }
    var samples: [Observation] = []
    func last(_ name: String, revision: Int) -> Observation? {
        samples.last { $0.name == name && $0.revision == revision }
    }
}

@MainActor
private struct PaneTransactionProbe: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let revision: Int
    let observations: PaneTransactionObservations
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        observations.samples.append(.init(name: name, revision: revision,
                                          paneChange: context.transaction[DSPaneChangeKey.self],
                                          animation: context.transaction.animation,
                                          disablesAnimations: context.transaction.disablesAnimations,
                                          reduceMotion: reduceMotion))
    }
}

@MainActor
private struct PaneTransactionFixture: View {
    let state: PaneTestState
    let observations: PaneTransactionObservations

    var body: some View {
        HStack(spacing: 0) {
            DSSidePane(edge: .leading, isOpen: state.leading, width: 100) {
                VStack {
                    probe("leading-pane")
                    probe("leading-local").animation(.linear(duration: 0.4), value: state.local)
                }
            }
            VStack {
                VStack {
                    probe("boundary")
                    probe("local").animation(.linear(duration: 0.4), value: state.local)
                }
            }
            DSSidePane(edge: .trailing, isOpen: state.trailing, width: 100) {
                VStack {
                    probe("trailing-pane")
                    probe("trailing-local").animation(.linear(duration: 0.4), value: state.local)
                }
            }
        }
        .dsPaneLayoutBoundary()
        .background(probe("parent")) // 配置境界の外側、開閉animationを受ける診断点。
        .dsPaneAnimation(value: state.trailing)
        .overlay(alignment: .trailing) {
            ZStack {
                probe("overlay")
                if state.overlay {
                    Color.clear.frame(width: 100).transition(.move(edge: .trailing))
                }
            }
        }
        // Dashboardと同じく、HStackの境界より外にoverlayと入口modifierを置く。
        .dsPaneAnimation(value: state.leading)
        .dsPaneAnimation(value: state.overlay)
    }

    private func probe(_ name: String) -> some View {
        PaneTransactionProbe(name: name, revision: state.revision, observations: observations)
            .frame(width: 20, height: 20)
    }
}
