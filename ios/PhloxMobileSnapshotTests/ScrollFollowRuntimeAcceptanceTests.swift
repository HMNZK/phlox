import SwiftUI
import UIKit
import Testing
import AgentDomain
import PhloxCore
import DesignSystemIOS
@testable import Features
@testable import PhloxMobile

@MainActor
@Suite(.serialized)
struct ScrollFollowRuntimeAcceptanceTests {
    @Test(arguments: [79, 81])
    func followsOnlyInsideEightyPointBoundary(preparedDistance: Int) async throws {
        let variables = ProcessInfo.processInfo.environment
        try #require(variables["PHLOX_SCROLL_FOLLOW_RUNTIME"] == "1" && UITestingSupport.isEnabled)
        let path = try #require(variables["PHLOX_SCROLL_FOLLOW_OUTPUT"])
        try #require(path.hasPrefix("/") && path.contains("/.verification/"))
        let output = URL(fileURLWithPath: path).appendingPathComponent("distance-\(preparedDistance)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled,
            "Animation measurement requires actual animations enabled and Reduce Motion disabled")
        let session = Session(id: "follow-runtime", name: "追従の描画検査", agent: .claudeCode,
            status: .running, updatedAt: Date())
        let api = FollowRuntimeAPI(session: session)
        let model = SessionDetailViewModel(session: session, api: api)
        let geometry = FollowRuntimeRootGeometry()
        let content = SessionDetailView(viewModel: model, onDelete: {})
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, value in
                geometry.scrollEvents.append(["time": CACurrentMediaTime(),
                    "contentOffset": String(describing: value.contentOffset),
                    "contentSize": String(describing: value.contentSize),
                    "containerSize": String(describing: value.containerSize),
                    "contentInsets": String(describing: value.contentInsets),
                    "visibleRect": String(describing: value.visibleRect),
                    "bounds": String(describing: value.bounds)])
            }
            .background(GeometryReader { proxy in
                Color.clear.onAppear { geometry.height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in geometry.height = height }
            })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKey?.makeKey() }
        var recorder: FollowRuntimeFrames?
        defer { recorder?.stop() }
        @MainActor
        func write(_ phase: String, _ extra: [String: Any] = [:]) throws {
            var data = extra
            data["phase"] = phase; data["preparedDistance"] = preparedDistance
            data["rootGeometryHeight"] = geometry.height
            data["swiftUIScrollGeometryEvents"] = geometry.scrollEvents
            data["windowBounds"] = String(describing: window.bounds)
            data["screenBounds"] = String(describing: window.screen.bounds)
            data["traitCategory"] = window.traitCollection.preferredContentSizeCategory.rawValue
            data["samples"] = recorder?.records ?? []
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(phase).json"))
        }
        do {
            try await wait { model.chatMessages.count == FollowRuntimeAPI.initialCount && geometry.height > 0 }
            let scroll = try #require(views(window).compactMap { $0 as? UIScrollView }.filter {
                $0.window === window && $0.isScrollEnabled && $0.bounds.width > window.bounds.width * 0.7
            }.max { $0.contentSize.height < $1.contentSize.height })
            let frames = FollowRuntimeFrames(scroll: scroll, model: model)
            recorder = frames; frames.start()
            try await wait { frames.isStable && scroll.contentSize.height > scroll.bounds.height + 200 }
            let inset = scroll.adjustedContentInset
            let layout = scroll.contentLayoutGuide.layoutFrame
            try write("mapping-before", ["contentLayoutFrame": String(describing: layout),
                "adjustedInsets": String(describing: inset), "scrollBounds": String(describing: scroll.bounds),
                "nativeContentCandidates": scroll.subviews.map { view in
                    ["class": String(reflecting: type(of: view)), "identity": String(describing: ObjectIdentifier(view)),
                     "frameInScroll": String(describing: view.convert(view.bounds, to: scroll)),
                     "frameInWindow": String(describing: view.convert(view.bounds, to: window)),
                     "bounds": String(describing: view.bounds), "hidden": view.isHidden, "alpha": String(describing: view.alpha)] as [String: Any]
                }])
            try #require(abs(inset.top) < 0.01 && abs(inset.bottom) < 0.01 && abs(inset.left) < 0.01 && abs(inset.right) < 0.01,
                "Unmeasured: native inset must be zero to identify the product anchor distance without an inferred correction")
            try #require(abs(scroll.bounds.height - geometry.height) <= 0.25
                && abs(layout.minY) <= 0.25 && abs(layout.height - scroll.contentSize.height) <= 0.25,
                "Unmeasured: actual viewport and content layout must match the source-derived terminal-anchor coordinate mapping")
            let preparedOffset = scroll.contentSize.height - scroll.bounds.height - CGFloat(preparedDistance)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: preparedOffset), animated: false)
            frames.resetStability()
            try await wait { frames.isStable && abs(scroll.contentOffset.y - preparedOffset) <= 0.25 }
            let distance = scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height
            try write("prepared", ["nativeRawAnchorDistance": distance,
                "nativeAdjustedBottomDistance": scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height + scroll.adjustedContentInset.bottom])
            try #require(abs(distance - CGFloat(preparedDistance)) <= 0.25)
            let heldOffset = scroll.contentOffset.y
            frames.beginUpdate()
            await api.publishOneArrival()
            try await wait(seconds: 10) {
                frames.hasAdoptedArrival && frames.isStable && frames.elapsedAfterAdoption >= 0.3 + 2 * frames.period
            }
            try write("after-arrival", ["publishCount": await api.publishCount,
                "heldOffset": heldOffset, "finalOffset": scroll.contentOffset.y,
                "finalRawAnchorDistance": scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height])
            let publishCount = await api.publishCount
            try #require(publishCount == 1 && model.chatMessages.count == FollowRuntimeAPI.initialCount + 1)
            try #require(frames.contentGrew, "The actual adopted arrival must increase rendered content height")
            if preparedDistance == 79 {
                try #require(abs(scroll.contentSize.height - scroll.bounds.height - scroll.contentOffset.y) <= 1,
                    "Inside the boundary, the actual product must reach its terminal anchor")
                let duration = try #require(frames.movementDuration,
                    "Unmeasured: actual presentation movement must span multiple display frames")
                try #require(frames.movingFrames >= 3 && abs(duration - 0.3) <= 2 * frames.period,
                    "Actual presentation follow duration must be 0.3 seconds within two observed frame periods")
            } else {
                try #require(frames.maximumOffsetDeviation(from: heldOffset) <= 0.5,
                    "Outside the boundary, adopted content must not pull the reader to the bottom")
            }
            try write("verified")
        } catch {
            try write("failed", ["error": String(describing: error)])
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: output.appendingPathComponent("failed.png"))
            throw error
        }
    }

    private func wait(seconds: Double = 5, until predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !predicate() && ContinuousClock.now < deadline { await Task.yield() }
        try #require(predicate(), "Required actual UI state was not measured within the deadline")
    }
    private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
}

@MainActor
private final class FollowRuntimeRootGeometry {
    var height: CGFloat = 0
    var scrollEvents: [[String: Any]] = []
}

private actor FollowRuntimeAPI: PhloxAPI {
    static let initialCount = 24
    let session: Session
    private var arrived = false
    private(set) var publishCount = 0
    init(session: Session) { self.session = session }
    func publishOneArrival() { publishCount += 1; arrived = true }
    private func snapshot() -> [ChatMessage] {
        var result: [ChatMessage] = (0..<Self.initialCount).map {
            .agent(id: "initial-\($0)", text: "描画検査 \($0)\n変更内容と確認結果を読み返すための本文です。")
        }
        if arrived { result.append(.agent(id: "one-arrival", text: "新着はこの1件だけです。\n本物の追従アニメーションと読取り位置保持を検査します。")) }
        return result
    }
    func listSessions() async throws -> [Session] { [session] }
    func messages(sessionID: String) async throws -> [ChatMessage] { snapshot() }
    func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta {
        MessagesDelta(messages: snapshot(), cursor: arrived ? "one" : "initial", isSnapshot: true)
    }
    func approvals() async throws -> [Approval] { [] }
    func usage(sessionID: String) async throws -> TurnUsage? { nil }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.notFound }
    func send(_ request: SendRequest) async throws -> SendResult { throw PhloxError.notFound }
    func remove(sessionID: String) async throws { throw PhloxError.notFound }
    func respond(approvalID: String, decision: ApprovalDecision) async throws { throw PhloxError.notFound }
}

@MainActor
private final class FollowRuntimeFrames: NSObject {
    let scroll: UIScrollView
    let model: SessionDetailViewModel
    private var link: CADisplayLink?
    private var previous: [CGFloat]?
    private var stableCount = 0
    private var updateStarted = false
    private var startingHeight: CGFloat = 0
    private var adoptedAt: TimeInterval?
    private var latestTime: TimeInterval = 0
    private var previousTime: TimeInterval = 0
    private var previousPresentationY: CGFloat?
    private var firstMovement: TimeInterval?
    private var lastMovement: TimeInterval?
    private var updateOffsets: [CGFloat] = []
    private(set) var movingFrames = 0
    private(set) var records: [[String: Any]] = []
    private(set) var period: TimeInterval = 0
    var isStable: Bool { stableCount >= 3 }
    var hasAdoptedArrival: Bool { adoptedAt != nil }
    var elapsedAfterAdoption: TimeInterval { adoptedAt.map { latestTime - $0 } ?? 0 }
    var contentGrew: Bool { scroll.contentSize.height > startingHeight + 1 }
    var movementDuration: TimeInterval? {
        guard let firstMovement, let lastMovement else { return nil }
        return lastMovement - firstMovement
    }
    init(scroll: UIScrollView, model: SessionDetailViewModel) { self.scroll = scroll; self.model = model }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    func resetStability() { stableCount = 0; previous = nil }
    func beginUpdate() {
        updateStarted = true; startingHeight = scroll.contentSize.height
        previousPresentationY = scroll.layer.presentation()?.bounds.minY
        firstMovement = nil; lastMovement = nil; movingFrames = 0
        updateOffsets = []; resetStability()
    }
    func maximumOffsetDeviation(from offset: CGFloat) -> CGFloat {
        updateOffsets.map { abs($0 - offset) }.max() ?? .infinity
    }
    @objc private func sample(_ link: CADisplayLink) {
        latestTime = link.timestamp; period = link.targetTimestamp - link.timestamp
        let presentation = scroll.layer.presentation()?.bounds
        let inset = scroll.adjustedContentInset
        let values: [CGFloat] = [scroll.contentOffset.x, scroll.contentOffset.y,
            scroll.bounds.minY, scroll.bounds.height, scroll.contentSize.height,
            inset.top, inset.bottom, presentation?.minY ?? .nan]
        let valid = values.allSatisfy(\.isFinite) && !scroll.isTracking && !scroll.isDragging
            && !scroll.isDecelerating && !scroll.isScrollAnimating
            && abs(scroll.bounds.minY - (presentation?.minY ?? .infinity)) <= 0.01
        let unchanged = previous.map { zip($0, values).allSatisfy { abs($0.0 - $0.1) <= 0.01 } } ?? false
        stableCount = valid ? (unchanged ? stableCount + 1 : 1) : 0
        if !valid { previous = nil } else if !unchanged { previous = values }
        if updateStarted {
            updateOffsets.append(scroll.contentOffset.y)
            if model.chatMessages.count == FollowRuntimeAPI.initialCount + 1, adoptedAt == nil { adoptedAt = link.timestamp }
            if let y = presentation?.minY, let old = previousPresentationY, abs(y - old) > 0.01 {
                if firstMovement == nil { firstMovement = previousTime }
                lastMovement = link.timestamp; movingFrames += 1
            }
        }
        previousPresentationY = presentation?.minY; previousTime = link.timestamp
        records.append(["timestamp": link.timestamp, "period": period,
            "contentOffset": String(describing: scroll.contentOffset), "modelBounds": String(describing: scroll.layer.bounds),
            "presentationBounds": String(describing: presentation), "adjustedInsets": String(describing: inset),
            "contentSize": String(describing: scroll.contentSize), "messageCount": model.chatMessages.count,
            "isScrollAnimating": scroll.isScrollAnimating, "isDecelerating": scroll.isDecelerating,
            "stableFrames": stableCount, "updateStarted": updateStarted])
    }
}
