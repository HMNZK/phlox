import SwiftUI
import UIKit
import Testing
import DesignSystemIOS
import PhloxCore
import PhloxNetworking
import ChatRenderKit
@testable import Features
@testable import PhloxMobile

/// Candidate only. Native programmatic scrolling is not evidence of finger-pan delivery.
@MainActor
@Suite(.serialized)
struct AdditionalAccessibilityAcceptanceTests {
    @Test(arguments: ["code", "diff"])
    func longTechnicalLineKeepsOneLineAndMovesHorizontally(kind: String) async throws {
        try #require(UITestingSupport.isEnabled)
        let run = try AdditionalRun("horizontal-\(kind)")
        let short = "LEFT_MARKER value RIGHT_MARKER"
        let long = "LEFT_MARKER " + String(repeating: "longIdentifier_", count: 40) + " RIGHT_MARKER"
        let shortMetrics = try await technicalMetrics(kind: kind, text: short, run: run, step: "short", exercise: false)
        let longMetrics = try await technicalMetrics(kind: kind, text: long, run: run, step: "long", exercise: true)
        let tolerance = 1 / UIScreen.main.scale
        #expect(abs(shortMetrics.viewportHeight - longMetrics.viewportHeight) <= tolerance,
                "A longer single source line must not grow the native horizontal viewport height")
        #expect(abs(shortMetrics.contentHeight - longMetrics.contentHeight) <= tolerance,
                "A longer single source line must not wrap into additional content rows")
        #expect(longMetrics.contentWidth > longMetrics.viewportWidth)
    }

    @Test(arguments: [true, false])
    func modelSheetAndRenameAlertRemainExclusive(modelFirst: Bool) async throws {
        try #require(UITestingSupport.isEnabled)
        let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: nil)
        let seedSession = try #require(try await environment.apiClient.listSessions().first {
            !$0.isPTY && $0.agent == .claudeCode
        })
        let api = makeAdditionalModelPresentationSnapshotAPI(session: seedSession)
        let session = try #require(try await api.listSessions().first { $0.id == seedSession.id })
        let model = SessionDetailViewModel(session: session, api: api)
        await model.loadModelSettings()
        try #require(model.showsModelSelectorChip, "The real fixture API must provide selectable models")
        let run = try AdditionalRun(modelFirst ? "model-to-rename" : "rename-to-model")
        try await withAdditionalWindow(content: NavigationStack {
            SessionDetailView(viewModel: model, scrollToBottomOnAppear: false, onDelete: {})
        }, run: run) { window, clock in
            if modelFirst { model.beginModelSelection() } else { model.beginRename() }
            try await clock.wait("first-native-presentation") {
                additionalPresentationMatches(window: window, model: model)
            }
            try run.capture(window, step: "first", extra: additionalModalMetrics(window, model: model))
            if modelFirst { model.beginRename() } else { model.beginModelSelection() }
            try await clock.wait("opposite-intent-exclusive-presentation") {
                additionalPresentationMatches(window: window, model: model)
            }
            let presented = additionalPresentedControllers(window)
            try run.capture(window, step: "after-opposite-intent", extra: additionalModalMetrics(window, model: model))
            #expect(presented.count == 1)
            #expect(model.isRenamePresented != model.isModelSheetPresented)
            #expect(additionalPresentationMatches(window: window, model: model))
        }
    }

    private func technicalMetrics(kind: String, text: String, run: AdditionalRun, step: String,
                                  exercise: Bool) async throws -> AdditionalScrollMetrics {
        let product: AnyView
        if kind == "code" {
            product = AnyView(DSCodeBlock(language: "text", code: text))
        } else {
            product = AnyView(SessionDetailFileChangeCard(
                change: ChatFileChange(path: "example.swift", diff: "+" + text, kind: "edit"),
                isExpanded: true, onToggle: {}
            ))
        }
        var result: AdditionalScrollMetrics?
        try await withAdditionalWindow(content: VStack(spacing: 0) {
            product.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }, run: run) { window, clock in
            try await clock.wait("\(step)-scroll-view-created") { !additionalScrolls(window).isEmpty }
            let candidates = additionalScrolls(window)
            try run.write("\(step)-scroll-candidates", ["scrolls": candidates.map { AdditionalScrollMetrics($0).json }])
            let scroll = try #require(candidates.count == 1 ? candidates.first : nil,
                                      "The single product view must expose exactly one visible native non-text scroll view")
            try await additionalStableScroll(scroll, clock: clock)
            let initial = AdditionalScrollMetrics(scroll)
            result = initial
            try run.capture(window, step: "\(step)-initial", extra: initial.json)
            guard exercise else { return }
            try #require(initial.contentWidth > initial.viewportWidth)
            let left = -scroll.adjustedContentInset.left
            let right = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
            try #require(right > left)
            scroll.setContentOffset(CGPoint(x: left, y: scroll.contentOffset.y), animated: false)
            try await additionalStableScroll(scroll, clock: clock)
            let before = scroll.contentOffset.x
            #expect(abs(before - left) <= 1 / window.screen.scale)
            try run.capture(window, step: "\(step)-left", extra: AdditionalScrollMetrics(scroll).json)
            scroll.setContentOffset(CGPoint(x: right, y: scroll.contentOffset.y), animated: false)
            try await additionalStableScroll(scroll, clock: clock)
            let after = scroll.contentOffset.x
            try run.capture(window, step: "\(step)-right", extra: AdditionalScrollMetrics(scroll).json)
            #expect(after > before)
            #expect(abs(after - right) <= 1 / window.screen.scale)
            #expect(abs(scroll.contentOffset.y - initial.offsetY) <= 1 / window.screen.scale)
            scroll.setContentOffset(CGPoint(x: left, y: scroll.contentOffset.y), animated: false)
            try await additionalStableScroll(scroll, clock: clock)
            #expect(abs(scroll.contentOffset.x - before) <= 1 / window.screen.scale)
            try run.capture(window, step: "\(step)-returned-left", extra: AdditionalScrollMetrics(scroll).json)
        }
        return try #require(result)
    }
}

private enum AdditionalError: Error { case timeout(String) }

@MainActor
private final class AdditionalFrameClock: NSObject {
    private var link: CADisplayLink?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func tick() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
    func next() async { await withCheckedContinuation { waiters.append($0) } }
    func wait(_ name: String, until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        var matchingFrames = 0
        while ContinuousClock.now < deadline {
            await next()
            matchingFrames = predicate() ? matchingFrames + 1 : 0
            if matchingFrames >= 3 { return }
        }
        throw AdditionalError.timeout(name)
    }
    func stop() { link?.invalidate(); link = nil }
}

@MainActor
private func additionalStableScroll(_ scroll: UIScrollView, clock: AdditionalFrameClock) async throws {
    var previous: [CGFloat]?
    try await clock.wait("native-scroll-geometry-stable") {
        let current = [scroll.bounds.width, scroll.bounds.height, scroll.contentSize.width,
                       scroll.contentSize.height, scroll.contentOffset.x, scroll.contentOffset.y]
        let same = previous == current
        previous = current
        return same && current.allSatisfy(\.isFinite) && scroll.bounds.width > 0 && scroll.bounds.height > 0
    }
}

@MainActor
private struct AdditionalScrollMetrics {
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    init(_ scroll: UIScrollView) {
        viewportWidth = scroll.bounds.width; viewportHeight = scroll.bounds.height
        contentWidth = scroll.contentSize.width; contentHeight = scroll.contentSize.height
        offsetX = scroll.contentOffset.x; offsetY = scroll.contentOffset.y
    }
    var json: [String: Any] {
        ["viewport": [viewportWidth, viewportHeight], "content": [contentWidth, contentHeight],
         "offset": [offsetX, offsetY], "inputMethod": "public-setContentOffset-not-finger-pan"]
    }
}

@MainActor
private func additionalViews(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(additionalViews) }

@MainActor
private func additionalScrolls(_ window: UIWindow) -> [UIScrollView] {
    additionalViews(window).compactMap { $0 as? UIScrollView }.filter {
        !($0 is UITextView) && $0.isScrollEnabled && !$0.isHidden && $0.alpha > 0
            && $0.window === window && $0.bounds.width > 0 && $0.bounds.height > 0
    }
}

@MainActor
private func additionalPresentedControllers(_ window: UIWindow) -> [UIViewController] {
    var visited: Set<ObjectIdentifier> = []
    var presented: [UIViewController] = []
    func inspect(_ controller: UIViewController, viaPresentation: Bool) {
        guard visited.insert(ObjectIdentifier(controller)).inserted else { return }
        if viaPresentation, controller.viewIfLoaded?.window === window,
           controller.viewIfLoaded?.isHidden == false { presented.append(controller) }
        if let next = controller.presentedViewController { inspect(next, viaPresentation: true) }
        controller.children.forEach { inspect($0, viaPresentation: false) }
    }
    if let root = window.rootViewController { inspect(root, viaPresentation: false) }
    return presented
}

@MainActor
private func additionalLabels(_ root: NSObject) -> [String] {
    var seen: Set<ObjectIdentifier> = []
    var labels: [String] = []
    func inspect(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted else { return }
        if let label = object.accessibilityLabel { labels.append(label) }
        for child in object.accessibilityElements ?? [] { if let child = child as? NSObject { inspect(child) } }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { inspect(child) } }
        }
        if let view = object as? UIView { view.subviews.forEach(inspect) }
    }
    inspect(root)
    return labels
}

@MainActor
private func additionalPresentationMatches(window: UIWindow, model: SessionDetailViewModel) -> Bool {
    let presented = additionalPresentedControllers(window)
    guard presented.count == 1, let top = presented.first,
          !top.isBeingPresented, !top.isBeingDismissed, top.transitionCoordinator == nil else { return false }
    if let alert = top as? UIAlertController {
        return alert.title == "名前を変更" && model.isRenamePresented && !model.isModelSheetPresented
    }
    return model.isModelSheetPresented && !model.isRenamePresented
        && additionalLabels(top.view).contains("モデルを絞り込む")
}

@MainActor
private func additionalModalMetrics(_ window: UIWindow, model: SessionDetailViewModel) -> [String: Any] {
    ["renameFlag": model.isRenamePresented, "modelFlag": model.isModelSheetPresented,
     "controllers": additionalPresentedControllers(window).map {
         ["type": String(reflecting: type(of: $0)), "title": $0.title ?? "",
          "transitioning": $0.transitionCoordinator != nil, "labels": additionalLabels($0.view)] as [String: Any]
     }]
}

@MainActor
private final class AdditionalHostingController: UIHostingController<AnyView> {
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}

@MainActor
private func withAdditionalWindow<Content: View>(content: Content, run: AdditionalRun,
    operation: (UIWindow, AdditionalFrameClock) async throws -> Void) async throws {
    let defaults = UserDefaults.standard
    let previousDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    var fixtureDomain = previousDomain
    fixtureDomain[ThemeStore.themeKey] = AppearancePreference.system.themeID(systemColorScheme: .light)
    defaults.setVolatileDomain(fixtureDomain, forName: UserDefaults.argumentDomain)
    defer { defaults.setVolatileDomain(previousDomain, forName: UserDefaults.argumentDomain) }
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKey = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
    window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    let host = AdditionalHostingController(rootView: AnyView(content.environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.locale, Locale(identifier: "ja_JP")).environment(\.colorScheme, .light)))
    host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    window.rootViewController = host
    let clock = AdditionalFrameClock()
    defer {
        clock.stop()
        window.isHidden = true
        window.rootViewController = nil
        if let previousKey, !previousKey.isHidden { previousKey.makeKey() }
    }
    window.makeKeyAndVisible()
    do {
        try await clock.wait("native-host-appeared") {
            host.hasAppeared && host.viewIfLoaded?.window === window && host.view.bounds.width == 375
        }
        try await operation(window, clock)
    } catch {
        let original = error
        do { try run.capture(window, step: "failure-\(UUID().uuidString)", extra: ["error": String(describing: original)]) }
        catch { Issue.record("Diagnostic capture also failed: \(error)") }
        if host.presentedViewController != nil {
            await withCheckedContinuation { continuation in host.dismiss(animated: false) { continuation.resume() } }
        }
        throw original
    }
    if host.presentedViewController != nil {
        await withCheckedContinuation { continuation in host.dismiss(animated: false) { continuation.resume() } }
    }
}

@MainActor
private struct AdditionalRun {
    let directory: URL
    init(_ name: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["PHLOX_ADDITIONAL_OUTPUT"]
            ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining/additional-accessibility-owned/runtime").path
        try #require(path.hasPrefix("/"))
        directory = URL(fileURLWithPath: path).appendingPathComponent("\(name)-ios\(UIDevice.current.systemVersion)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("owner", ["pid": ProcessInfo.processInfo.processIdentifier, "executable": Bundle.main.executableURL?.path ?? "unknown",
                            "purpose": name, "output": directory.path])
    }
    func write(_ name: String, _ payload: [String: Any]) throws {
        try #require(JSONSerialization.isValidJSONObject(payload))
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
    }
    func capture(_ window: UIWindow, step: String, extra: [String: Any]) throws {
        try write(step, extra)
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(drawn)
        try #require(image.pngData()).write(to: directory.appendingPathComponent(step + ".png"), options: .atomic)
    }
}
