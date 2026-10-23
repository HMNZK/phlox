import AgentDomain
import AppKit
import DesignSystem
import Foundation
import os
import SwiftUI
import Testing
@testable import SessionFeature

/// 起動は明示 opt-in。通常のテストではfixture契約だけを検査し、窓を作らない。
@Suite("SidebarTranscriptRenderHarness", .serialized)
@MainActor
struct SidebarTranscriptRenderHarness {
    @Test func unsupportedAXAttributesAreNotInvoked() {
        let plainObject = NSObject()
        #expect(sidebarHarnessAXAttribute(plainObject, "accessibilityIdentifier") == nil)
        #expect(sidebarHarnessAXAttribute(plainObject, "accessibilityChildren") == nil)
        #expect(sidebarHarnessAXAttribute(plainObject, "accessibilityLabel") == nil)
        #expect(sidebarHarnessAXAttribute(plainObject, "accessibilityTitle") == nil)
        #expect(sidebarHarnessAXAttribute(plainObject, "accessibilityValue") == nil)
        #expect(sidebarHarnessElements(plainObject).count == 1)
        #expect(findSidebarHarnessElement(plainObject, identifier: "missing") == nil)
        #expect(sidebarHarnessAccessibilityText(plainObject).isEmpty)
        #expect(!performPress(plainObject))
        let accessible = NSAccessibilityElement()
        accessible.setAccessibilityLabel("対応する属性は読む")
        #expect((sidebarHarnessAXAttribute(accessible, "accessibilityLabel") as? String) == "対応する属性は読む")
    }

    @Test func measureVisibleTranscript() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SIDEBAR_TRANSCRIPT_OUT"], !path.isEmpty else { return }
        let expansions = Int(env["SIDEBAR_TRANSCRIPT_EXPANSIONS"] ?? "0") ?? -1
        let all = env["SIDEBAR_TRANSCRIPT_ALL"] == "1"
        let noAnimation = env["SIDEBAR_TRANSCRIPT_NO_ANIMATION"] == "1"
        let leading = env["SIDEBAR_TRANSCRIPT_EDGE"] == "leading"
        let overlay = env["SIDEBAR_TRANSCRIPT_OVERLAY"] == "1"
        let rounds = Int(env["SIDEBAR_TRANSCRIPT_ROUNDS"] ?? "10") ?? 0
        try #require([0, 1, 4, 8].contains(expansions))
        try #require(rounds > 0)
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(SidebarTranscriptFixture.manifest).write(to: output.appendingPathComponent("fixture-manifest.json"))

        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { app.setActivationPolicy(previousPolicy) }
        let model = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.claudeCode), client: DisconnectedHarnessClient(),
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-sidebar-artificial-fixture"
        )
        let controls = SidebarHarnessControls()
        let log = SidebarWidthLog(output: output)
        let root = SidebarHarnessRoot(model: model, controls: controls, log: log,
                                      noAnimation: noAnimation, leading: leading, overlay: overlay)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 1_400, height: 850)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_400, height: 850),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Phlox 人工会話・幅到達計測"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        // AXのchildrenだけではNSHostingView内のAppKit scroll/document境界を越えない。
        // 実際のNSView subviewsも調べ、初期配置と期待件数を待つ（時間だけで準備完了にしない）。
        let initialReady = try await waitForSidebarHarness(hosting) {
            sidebarHarnessHasHiddenCount(hosting, count: 491)
        }
        try writeSidebarHarnessDiagnostics(hosting, window: window, to: output, name: "initial")
        try #require(initialReady, "initial layout/AX not ready; inspect initial-ax.txt and initial.png")
        for expansion in 0..<expansions {
            let history = try #require(findSidebarHarnessElement(hosting, identifier: "ChatTranscript.history"))
            let actions = try #require(sidebarHarnessAXAttribute(history, "accessibilityCustomActions") as? [NSAccessibilityCustomAction])
            let action = try #require(actions.first { $0.name == "以前のメッセージを読み込む" })
            try #require(action.handler?() == true)
            let ready = try await waitForSidebarHarness(hosting) {
                sidebarHarnessHasHiddenCount(hosting, count: 500 - SidebarTranscriptFixture.allowed(expansions: expansion + 1))
            }
            if !ready {
                try writeSidebarHarnessDiagnostics(hosting, window: window, to: output, name: "expansion-\(expansion + 1)-failed")
            }
            try #require(ready, "load-earlier did not expose the expected block count")
        }
        if all {
            controls.target = SidebarTranscriptFixture.items[0].id
            let ready = try await waitForSidebarHarness(hosting) {
                sidebarHarnessHasHiddenCount(hosting, count: 0)
            }
            try writeSidebarHarnessDiagnostics(hosting, window: window, to: output, name: "all")
            try #require(ready, "first-block jump did not expose the entire history")
        } else {
            let history = try #require(findSidebarHarnessElement(hosting, identifier: "ChatTranscript.history"))
            let expectedHidden = 500 - SidebarTranscriptFixture.allowed(expansions: expansions)
            let text = sidebarHarnessAccessibilityOwnText(history)
            #expect(text.contains("\(expectedHidden)"), "actual load-earlier label: \(text)")
        }
        let config: [String: String] = [
            "pid": "\(ProcessInfo.processInfo.processIdentifier)",
            "expansions": "\(expansions)", "expectedVisibleBlocks": "\(all ? 500 : SidebarTranscriptFixture.allowed(expansions: expansions))",
            "noAnimation": "\(noAnimation)", "leading": "\(leading)", "overlay": "\(overlay)",
            "rounds": "\(rounds)", "measurement": "container model-width arrival; NOT layout/display completion",
            "windowWidth": "\(window.contentLayoutRect.width)", "windowHeight": "\(window.contentLayoutRect.height)",
        ]
        try encoder.encode(config).write(to: output.appendingPathComponent("configuration.json"))
        // CPUの事前10秒と事後5+10秒を外部から採取できる区間。
        try await Task.sleep(for: .seconds(10))
        for operation in 0..<(rounds * 2) {
            let open = !controls.open
            let target = overlay ? window.contentLayoutRect.width
                : window.contentLayoutRect.width - (open ? 280 + DSLayout.paneSeparatorWidth : 0)
            log.begin(operation: operation, target: target)
            controls.open = open
            let deadline = ContinuousClock.now + .seconds(60)
            while !log.arrived && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try log.save()
            try #require(log.arrived, "width arrival timed out; not a display completion test")
            try await Task.sleep(for: .seconds(1))
        }
        try await Task.sleep(for: .seconds(15))
        try log.save()
    }
}

@MainActor @Observable
private final class SidebarHarnessControls {
    var open = false
    var target: String?
}

@MainActor
private struct SidebarHarnessRoot: View {
    let model: ChatSessionViewModel
    @Bindable var controls: SidebarHarnessControls
    let log: SidebarWidthLog
    let noAnimation: Bool
    let leading: Bool
    let overlay: Bool

    var body: some View {
        HStack(spacing: 0) {
            if leading && !overlay { pane }
            GeometryReader { geometry in
                ChatTranscriptView(
                    viewModel: model, transcript: SidebarTranscriptFixture.items,
                    showsThinkingIndicator: false,
                    contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: geometry.size.width),
                    requestedScrollTarget: $controls.target
                )
                .frame(width: geometry.size.width)
            }
            .background(SidebarWidthProbe(log: log))
            if !leading && !overlay { pane }
        }
        .dsPaneLayoutBoundary()
        .overlay(alignment: leading ? .leading : .trailing) {
            if overlay && controls.open {
                paneContent.frame(width: 280)
                    .transition(leading ? .move(edge: .leading) : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .modifier(SidebarHarnessAnimation(open: controls.open, disabled: noAnimation))
    }

    private var pane: some View {
        DSSidePane(edge: leading ? .leading : .trailing, isOpen: controls.open, width: 280) {
            paneContent
        }
    }

    private var paneContent: some View {
        Text("人工データ計測ペイン").frame(maxHeight: .infinity).background(DSColor.chatBackground)
    }
}

private struct SidebarHarnessAnimation: ViewModifier {
    let open: Bool
    let disabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if disabled { content } else { content.dsPaneAnimation(value: open) }
    }
}

@MainActor
private final class SidebarWidthLog {
    struct Sample: Codable {
        let event: String
        let operation: Int
        let uptime: TimeInterval
        let epoch: TimeInterval
        let width: CGFloat?
        let animated: Bool?
    }
    private let output: URL
    private let signposts = OSLog(subsystem: "phlox.tests.sidebar-transcript", category: .pointsOfInterest)
    private var samples: [Sample] = []
    private var operation = -1
    private var target: CGFloat = 0
    private var currentWidth: CGFloat = 0
    private(set) var arrived = false

    init(output: URL) { self.output = output }

    func begin(operation: Int, target: CGFloat) {
        self.operation = operation
        self.target = target
        arrived = false
        append("begin", width: target)
        os_signpost(.begin, log: signposts, name: "SidebarWidthArrival", "operation=%d target=%f", operation, Double(target))
        // 重ね表示の中央幅は変わらない。この到達0は描画時間を意味しない。
        if abs(currentWidth - target) <= 1 { observe(width: currentWidth) }
    }

    func observe(width: CGFloat) {
        currentWidth = width
        append("width", width: width)
        if operation >= 0 && !arrived && abs(width - target) <= 1 {
            arrived = true
            append("width-arrived", width: width)
            os_signpost(.end, log: signposts, name: "SidebarWidthArrival", "operation=%d width=%f", operation, Double(width))
        }
    }

    func transaction(animated: Bool) { append("transaction", animated: animated) }

    private func append(_ event: String, width: CGFloat? = nil, animated: Bool? = nil) {
        samples.append(Sample(event: event, operation: operation,
                              uptime: ProcessInfo.processInfo.systemUptime,
                              epoch: Date().timeIntervalSince1970, width: width, animated: animated))
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: output.appendingPathComponent("width-and-transactions.json"), options: .atomic)
    }
}

@MainActor
private struct SidebarWidthProbe: NSViewRepresentable {
    let log: SidebarWidthLog
    func makeNSView(context: Context) -> ProbeView { ProbeView(log: log) }
    func updateNSView(_ view: ProbeView, context: Context) {
        log.transaction(animated: context.transaction.animation != nil)
    }

    final class ProbeView: NSView {
        let log: SidebarWidthLog
        init(log: SidebarWidthLog) { self.log = log; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            log.observe(width: newSize.width)
        }
    }
}

@MainActor
private func findSidebarHarnessElement(_ element: Any, identifier: String) -> AnyObject? {
    sidebarHarnessElements(element).first {
        (sidebarHarnessAXAttribute($0, "accessibilityIdentifier") as? String) == identifier
    }
}

/// SwiftUIのAX要素とAppKitのホスト境界を両方辿る。両経路に現れる要素は一度だけ読む。
@MainActor
private func sidebarHarnessElements(_ root: Any) -> [AnyObject] {
    var result: [AnyObject] = []
    var pending: [AnyObject] = [root as AnyObject]
    var seen = Set<ObjectIdentifier>()
    while let object = pending.popLast() {
        guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
        result.append(object)
        let children = sidebarHarnessAXAttribute(object, "accessibilityChildren") as? [AnyObject] ?? []
        pending.append(contentsOf: children)
        if let view = object as? NSView {
            pending.append(contentsOf: view.subviews)
        }
    }
    return result
}

@MainActor
private func sidebarHarnessAccessibilityText(_ element: Any) -> String {
    sidebarHarnessElements(element).map(sidebarHarnessAccessibilityOwnText).joined(separator: " ")
}

@MainActor
private func sidebarHarnessHasHiddenCount(_ hosting: NSView, count: Int) -> Bool {
    guard let history = findSidebarHarnessElement(hosting, identifier: "ChatTranscript.history") else { return false }
    return sidebarHarnessAccessibilityOwnText(history).contains("以前のメッセージ: \(count) 件")
}

@MainActor
private func waitForSidebarHarness(_ hosting: NSView, until ready: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + .seconds(15)
    repeat {
        hosting.layoutSubtreeIfNeeded()
        if ready() { return true }
        try await Task.sleep(for: .milliseconds(50))
    } while ContinuousClock.now < deadline
    return false
}

@MainActor
private func writeSidebarHarnessDiagnostics(_ hosting: NSView, window: NSWindow, to output: URL, name: String) throws {
    var lines = ["visible=\(window.isVisible) key=\(window.isKeyWindow) hostFrame=\(hosting.frame) windowFrame=\(window.frame)"]
    lines += sidebarHarnessElements(hosting).map { object in
        "\(type(of: object)) role=\(String(describing: sidebarHarnessAXAttribute(object, "accessibilityRole"))) id=\(String(describing: sidebarHarnessAXAttribute(object, "accessibilityIdentifier"))) text=\(sidebarHarnessAccessibilityOwnText(object))"
    }
    try lines.joined(separator: "\n").write(to: output.appendingPathComponent("\(name)-ax.txt"), atomically: true, encoding: .utf8)
    if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    } else {
        try "bitmapImageRepForCachingDisplay returned nil".write(to: output.appendingPathComponent("\(name)-capture-error.txt"), atomically: true, encoding: .utf8)
    }
}

@MainActor
private func sidebarHarnessAccessibilityOwnText(_ object: AnyObject) -> String {
    ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
        .compactMap { sidebarHarnessAXAttribute(object, $0) as? String }.joined(separator: " ")
}

/// AX要素はNSObjectであっても各属性への応答を保証しない。
/// ここで使うgetterはすべてObjective-Cのオブジェクト戻り値・引数なし。
@MainActor
private func sidebarHarnessAXAttribute(_ object: AnyObject, _ attribute: String) -> Any? {
    guard let receiver = object as? NSObject else { return nil }
    let selector = NSSelectorFromString(attribute)
    guard receiver.responds(to: selector) else { return nil }
    return receiver.perform(selector)?.takeUnretainedValue()
}
