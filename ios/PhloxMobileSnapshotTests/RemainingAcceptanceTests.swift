import SwiftUI
import UIKit
import Testing
import PhloxCore
import DesignSystemIOS
import PhloxNetworking
@testable import Features
@testable import PhloxMobile

/// 公開AX操作とnative UIKitの検査。タッチgestureの成功とは区別する。
@MainActor
@Suite(.serialized)
struct RemainingAcceptanceTests {
    @Test func usagePopoverHasFiniteViewportAndRecordsPublicAXCapability() async throws {
        try await withRemainingUsagePopover(scene: "UsagePopoverNativeCapabilityAX5") { _, scroll, run in
            let before = scroll.contentOffset.y
            let accepted = scroll.accessibilityScroll(.down)
            try await Task.sleep(for: .milliseconds(500))
            var metrics = remainingScrollMetrics(scroll)
            metrics["publicAXAccepted"] = accepted
            metrics["previousOffsetY"] = Double(before)
            metrics["scrollCompletionVerified"] = false
            metrics["capability"] = accepted ? "accepted" : "unsupported"
            try run.write(name: "public-ax-capability", payload: metrics)
            print("remaining public AX capability: \(accepted ? "accepted" : "unsupported; scroll completion remains unverified")")
            if accepted {
                try #require(scroll.contentOffset.y > before + 0.5,
                             "An accepted public AX action must move the real scroll view")
            } else {
                try #require(abs(scroll.contentOffset.y - before) < 0.5)
            }
        }
    }

    @Test func nativeDeleteAlertStacksExecutionAboveCancelAtAX5() async throws {
        try #require(UITestingSupport.isEnabled)
        let environment = AppEnvironment.uiTesting(scenario: .goldenPath)
        let model = DeleteConfirmationViewModel(
            sessionID: "remaining-delete-confirmation", sessionName: "残る検証用セッション", cascadeCount: 2,
            api: environment.apiClient, onDeleted: { Issue.record("The layout test must not execute deletion") }
        )
        let run = try RemainingAcceptanceRun(scene: "NativeDeleteAlertAX5")
        try await withRemainingWindow(content: DeleteConfirmationView(viewModel: model, onCancel: {})) { host in
            let presented = try await host.waitForPresentedController { $0 is UIAlertController }
            let alert = try #require(presented as? UIAlertController, "The product view must present a real native alert")
            try #require(alert.actions.count == 2)
            let execution = try #require(alert.actions.first { $0.style == .destructive })
            let cancel = try #require(alert.actions.first { $0.style == .cancel })
            try #require(execution.title == model.deleteButtonLabel && cancel.title == "キャンセル")
            try #require(alert.title == model.title && alert.message == model.message)
            let frames = try await remainingAlertButtonFrames(alert: alert, titles: [model.deleteButtonLabel, "キャンセル"], window: host.window)
            let executionFrame = try #require(frames[model.deleteButtonLabel])
            let cancelFrame = try #require(frames["キャンセル"])
            let labels = remainingViews(in: alert.view).compactMap { $0 as? UILabel }.map { label in
                ["text": label.text ?? "", "fontName": label.font.fontName,
                 "fontPointSize": Double(label.font.pointSize),
                 "frame": remainingRect(label.convert(label.bounds, to: host.window)),
                 "nativeContentSizeCategory": label.traitCollection.preferredContentSizeCategory.rawValue] as [String: Any]
            }
            try await run.captureAndHold(window: host.window, name: "native-alert", payload: [
                "globalContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
                "controllerContentSizeCategory": alert.traitCollection.preferredContentSizeCategory.rawValue,
                "viewContentSizeCategory": alert.view.traitCollection.preferredContentSizeCategory.rawValue,
                "labels": labels,
                "actions": alert.actions.map { ["title": $0.title ?? "", "style": $0.style.rawValue] as [String: Any] },
                "executionFrame": remainingRect(executionFrame), "cancelFrame": remainingRect(cancelFrame),
            ])
            try #require(UIApplication.shared.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
            try #require(alert.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
            try #require(alert.view.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
            try #require(!labels.isEmpty, "Native alert font measurements must exist")
            try #require(executionFrame.height >= 44 && cancelFrame.height >= 44)
            try #require(abs(executionFrame.midX - cancelFrame.midX) < 1)
            try #require(executionFrame.maxY <= cancelFrame.minY + 1,
                         "AC-10-5: execution must be above cancel in a non-overlapping vertical stack")
            #expect(model.state == .idle)
        }
    }
}

@MainActor
private func remainingViews(in root: UIView) -> [UIView] {
    [root] + root.subviews.flatMap { remainingViews(in: $0) }
}

private func remainingRect(_ value: CGRect) -> [Double] {
    [Double(value.origin.x), Double(value.origin.y), Double(value.width), Double(value.height)]
}

@MainActor
private func remainingTop(_ scroll: UIScrollView) -> CGFloat { -scroll.adjustedContentInset.top }

@MainActor
private func remainingBottom(_ scroll: UIScrollView) -> CGFloat {
    max(remainingTop(scroll), scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
}

private func remainingInsets(_ value: UIEdgeInsets) -> [Double] {
    [Double(value.top), Double(value.left), Double(value.bottom), Double(value.right)]
}

@MainActor
private func remainingLabelMetrics(in scroll: UIScrollView) -> [String: Any] {
    guard let window = scroll.window else { return ["status": "unavailable: no window"] }
    var visited: Set<ObjectIdentifier> = []
    var labels: [(bottom: CGFloat, payload: [String: Any])] = []
    func inspect(_ object: NSObject, exposedByAXContainer: Bool) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        let text: String?
        let rect: CGRect
        let source: String
        if let label = object as? UILabel, let value = label.text, !value.isEmpty {
            text = value
            rect = label.convert(label.bounds, to: window)
            source = "UILabel"
        } else if object.isAccessibilityElement || (exposedByAXContainer && !(object is UIView)) {
            text = object.accessibilityLabel
            rect = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
            source = "publicAX"
        } else {
            text = nil
            rect = .zero
            source = "unavailable"
        }
        if let text, !text.isEmpty, rect.width > 0, rect.height > 0, !object.accessibilityTraits.contains(.button) {
            let contentRect = scroll.convert(rect, from: window)
            labels.append((contentRect.maxY, ["label": text, "source": source,
                "windowRect": remainingRect(rect), "contentRect": remainingRect(contentRect)]))
        }
        for child in object.accessibilityElements ?? [] {
            if let child = child as? NSObject { inspect(child, exposedByAXContainer: true) }
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject {
                    inspect(child, exposedByAXContainer: true)
                }
            }
        }
        if let view = object as? UIView {
            for child in view.subviews { inspect(child, exposedByAXContainer: false) }
        }
    }
    inspect(scroll, exposedByAXContainer: false)
    let ordered = labels.sorted { $0.bottom < $1.bottom }
    return ["status": ordered.isEmpty ? "unavailable: no public UILabel/AX label frames" : "observed public labels only",
            "labels": ordered.map(\.payload),
            "lastObservedLabel": ordered.last?.payload as Any? ?? NSNull()]
}

@MainActor
private func remainingScrollMetrics(_ scroll: UIScrollView) -> [String: Any] {
    ["type": String(reflecting: type(of: scroll)), "bounds": remainingRect(scroll.bounds),
     "contentSize": [Double(scroll.contentSize.width), Double(scroll.contentSize.height)],
     "offset": [Double(scroll.contentOffset.x), Double(scroll.contentOffset.y)],
     "contentInset": remainingInsets(scroll.contentInset),
     "adjustedContentInset": remainingInsets(scroll.adjustedContentInset),
     "safeAreaInsets": remainingInsets(scroll.safeAreaInsets),
     "publicLabelFrames": remainingLabelMetrics(in: scroll),
     "top": Double(remainingTop(scroll)), "bottom": Double(remainingBottom(scroll)),
     "isScrollEnabled": scroll.isScrollEnabled,
     "nativeContentSizeCategory": scroll.traitCollection.preferredContentSizeCategory.rawValue]
}

/// Explicit external interaction; never a fallback from the public AX capability test.
@MainActor
@Suite(.serialized)
struct RemainingInteractiveAcceptanceTests {
    @Test(arguments: ["T1", "T3", "P3"])
    func remainingNativeAlertCallersStackExecutionAboveCancelAtAX5(caller: String) async throws {
        try #require(UITestingSupport.isEnabled)
        try #require(ProcessInfo.processInfo.environment["PHLOX_REMAINING_INTERACTIVE"] == "1"
            && ProcessInfo.processInfo.environment["PHLOX_REMAINING_HOLD"] == "1",
            "This caller test needs explicitly coordinated native CUA operations")
        let api = RemainingNativeAlertAPI()
        let session = Session(id: "remaining-\(caller)", name: "本物alertの検査", agent: .claudeCode,
                              status: .idle, updatedAt: Date())
        let detail = SessionDetailViewModel(session: session, api: api)
        await detail.loadModelSettings()
        let deletion = DeleteConfirmationViewModel(sessionID: session.id, sessionName: session.name, cascadeCount: 2,
            api: api, onDeleted: { Issue.record("A failing deletion API must not report success") })
        let run = try RemainingAcceptanceRun(scene: "NativeAlert\(caller)AX5")
        let content = Group {
            if caller == "T3" {
                DeleteConfirmationView(viewModel: deletion, onCancel: {})
            } else {
                NavigationStack {
                    SessionDetailView(viewModel: detail, scrollToBottomOnAppear: false, onDelete: {})
                }
            }
        }
        try await withRemainingWindow(content: content) { host in
            let title: String
            let executionTitle: String
            let cancelTitle: String
            switch caller {
            case "T1":
                detail.beginRename()
                title = "名前を変更"; executionTitle = "変更"; cancelTitle = "キャンセル"
            case "T3":
                _ = try await host.waitForPresentedController { ($0 as? UIAlertController)?.title == deletion.title }
                try await run.captureAndHold(window: host.window, name: "execute-delete", payload: [
                    "instruction": "本物の初期削除確認で『3 件を削除』を押す。失敗alertは押さずACKする",
                    "apiRemoveCount": await api.removeCount,
                ])
                title = "削除できませんでした"; executionTitle = "もう一度削除"; cancelTitle = "閉じる"
            case "P3":
                try await run.captureAndHold(window: host.window, name: "select-strong-permission", payload: [
                    "instruction": "本物入力欄の『思考の強さと権限を変更』Menuから『Bypass Permissions』を選択する。確認alertの実行/キャンセルは押さずACKする",
                    "apiSettingUpdateCount": await api.updateCount,
                ])
                title = "確認なしで全部を許可しますか？"; executionTitle = "Bypass Permissions にする"; cancelTitle = "キャンセル"
            default:
                throw RemainingAcceptanceError.presentationTimeout
            }
            let presented = try await host.waitForPresentedController { ($0 as? UIAlertController)?.title == title }
            let alert = try #require(presented as? UIAlertController)
            try #require(alert.title == title && alert.actions.count == 2)
            let execution = try #require(alert.actions.first { $0.title == executionTitle })
            let cancel = try #require(alert.actions.first { $0.title == cancelTitle })
            try #require(cancel.style == .cancel && execution.style != .cancel)
            try #require(execution.style == (caller == "P3" ? .destructive : .default))
            if caller == "T1" { try #require(alert.message == "一覧と詳細に出る名前です。") }
            if caller == "T3" { try #require(deletion.failurePresentation != nil) }
            let frames = try await remainingAlertButtonFrames(alert: alert, titles: [executionTitle, cancelTitle], window: host.window)
            let executeFrame = try #require(frames[executionTitle]), cancelFrame = try #require(frames[cancelTitle])
            let labels = remainingViews(in: alert.view).compactMap { $0 as? UILabel }.map {
                ["text": $0.text ?? "", "fontPointSize": Double($0.font.pointSize),
                 "frame": String(describing: $0.convert($0.bounds, to: host.window)),
                 "contentSizeCategory": $0.traitCollection.preferredContentSizeCategory.rawValue] as [String: Any]
            }
            try await run.captureAndHold(window: host.window, name: "native-alert", payload: [
                "caller": caller, "title": alert.title ?? "", "message": alert.message ?? "", "labels": labels,
                "globalContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
                "controllerContentSizeCategory": alert.traitCollection.preferredContentSizeCategory.rawValue,
                "viewContentSizeCategory": alert.view.traitCollection.preferredContentSizeCategory.rawValue,
                "actions": alert.actions.map { ["title": $0.title ?? "", "style": $0.style.rawValue] as [String: Any] },
                "executionFrame": String(describing: executeFrame), "cancelFrame": String(describing: cancelFrame),
                "apiRemoveCount": await api.removeCount, "apiSettingUpdateCount": await api.updateCount,
            ])
            try #require(UIApplication.shared.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge
                && alert.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge
                && alert.view.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
            try #require(!labels.isEmpty)
            let finite = [executeFrame.minX, executeFrame.minY, executeFrame.width, executeFrame.height,
                          cancelFrame.minX, cancelFrame.minY, cancelFrame.width, cancelFrame.height].allSatisfy(\.isFinite)
            try #require(finite && executeFrame.width >= 44 && executeFrame.height >= 44
                && cancelFrame.width >= 44 && cancelFrame.height >= 44)
            try #require(abs(executeFrame.midX - cancelFrame.midX) < 1 && executeFrame.maxY <= cancelFrame.minY + 1,
                         "AC10-5: the real execution action must be above cancel without overlap")
            #expect(await api.removeCount == (caller == "T3" ? 1 : 0))
            #expect(await api.updateCount == 0)
            if caller == "P3" { #expect(detail.modelSettings?.selectedPermission == "manual") }
        }
        try run.write(name: "after-window-close", payload: [
            "globalContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "restorationContract": "Execution owner restores global Large and records readback after the suite; runtime warnings stay in the complete log",
        ])
    }

    @Test func usagePopoverExternalScrollReachesBottomAndReturnsToTop() async throws {
        try #require(ProcessInfo.processInfo.environment["PHLOX_REMAINING_INTERACTIVE"] == "1",
                     "Select this suite only for an explicitly coordinated external CUA run")
        try await withRemainingUsagePopover(scene: "UsagePopoverExternalScrollAX5") { host, scroll, run in
            let initial = scroll.contentOffset.y
            try await run.requestExternalScroll(window: host.window, scroll: scroll, action: "scrollToBottom")
            #expect(scroll.contentOffset.y > initial + 0.5)
            #expect(abs(scroll.contentOffset.y - remainingBottom(scroll)) < 1)
            try await run.captureAndHold(window: host.window, name: "bottom", payload: remainingScrollMetrics(scroll))
            let bottom = scroll.contentOffset.y
            try await run.requestExternalScroll(window: host.window, scroll: scroll, action: "scrollToTop")
            try #require(scroll.contentOffset.y < bottom - 0.5)
            try #require(abs(scroll.contentOffset.y - remainingTop(scroll)) < 1)
            try await run.captureAndHold(window: host.window, name: "top", payload: remainingScrollMetrics(scroll))
        }
    }
}

@MainActor
private func withRemainingUsagePopover(
    scene: String, operation: (RemainingAcceptanceWindow, UIScrollView, RemainingAcceptanceRun) async throws -> Void
) async throws {
    try #require(UITestingSupport.isEnabled)
    let environment = AppEnvironment.uiTesting(scenario: .goldenPath)
    let usage = UsageViewModel(
        api: environment.apiClient, agents: UITestUsageFixtures.values(for: .normal), state: .loaded,
        lastSuccessfulAt: UITestUsageFixtures.asOfDate, now: { UITestUsageFixtures.asOfDate }
    )
    let run = try RemainingAcceptanceRun(scene: scene)
    try await withRemainingWindow(content: VStack {
        Spacer()
        UsageRingRow(viewModel: usage, isPopoverPresented: true).padding(.horizontal, 16)
    }) { host in
        let popover = try await host.waitForPresentedController { $0.popoverPresentationController != nil }
        try #require(popover.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
        let candidates = remainingViews(in: popover.view).compactMap { $0 as? UIScrollView }
        try run.write(name: "initial-scrolls", payload: ["scrollViews": candidates.map(remainingScrollMetrics)])
        let scroll = try #require(candidates.first {
            $0.isScrollEnabled && $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height
        }, "The real AX5 popover must contain a finite, enabled, overflowing native scroll view")
        try #require(scroll.bounds.height.isFinite && scroll.contentSize.height.isFinite)
        try #require(abs(scroll.contentOffset.y - remainingTop(scroll)) < 1)
        try await operation(host, scroll, run)
    }
}

@MainActor
private func remainingAlertButtonFrames(alert: UIAlertController, titles: [String], window: UIWindow) async throws -> [String: CGRect] {
    let deadline = ContinuousClock.now + .seconds(3)
    repeat {
        var frames: [String: CGRect] = [:]
        var visited: Set<ObjectIdentifier> = []
        func inspect(_ object: NSObject, exposedByAXContainer: Bool) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement || (exposedByAXContainer && !(object is UIView)) {
                if object.accessibilityTraits.contains(.button), let label = object.accessibilityLabel, titles.contains(label) {
                    let frame = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
                    if frame.width > 0 && frame.height > 0 { frames[label] = frame }
                }
            }
            if let button = object as? UIButton, let title = button.currentTitle, titles.contains(title) {
                frames[title] = button.convert(button.bounds, to: window)
            }
            for child in object.accessibilityElements ?? [] {
                if let child = child as? NSObject { inspect(child, exposedByAXContainer: true) }
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { inspect(child, exposedByAXContainer: true) }
                }
            }
            if let view = object as? UIView {
                for child in view.subviews { inspect(child, exposedByAXContainer: false) }
            }
        }
        inspect(alert.view, exposedByAXContainer: false)
        if titles.allSatisfy({ frames[$0] != nil }) { return frames }
        try await Task.sleep(for: .milliseconds(50))
    } while ContinuousClock.now < deadline
    Issue.record("Native alert button frames were unavailable through public UIKit/AX; no private action-view lookup is used")
    throw RemainingAcceptanceError.nativeButtonsUnavailable
}

/// API依存だけを制御し、alertは本物のcallerが生成する。
private actor RemainingNativeAlertAPI: PhloxAPI, SessionModelSelecting {
    private(set) var removeCount = 0
    private(set) var updateCount = 0
    private var permission: String? = "manual"
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.unsupported }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func remove(sessionID: String) async throws {
        removeCount += 1
        throw PhloxError.server(status: 503, message: "native-alert-delete-unavailable")
    }
    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        SessionModelSettings(selectedModel: nil, availableModels: [], selectedPermission: permission,
            availablePermissions: [AgentSettingOption(value: "manual", displayName: "Manual"),
                AgentSettingOption(value: "bypassPermissions", displayName: "Bypass Permissions")])
    }
    func setModel(sessionID: String, model: String) async throws { throw PhloxError.unsupported }
    func updateSessionSettings(sessionID: String, update: SessionSettingsUpdate) async throws {
        updateCount += 1
        if let selected = update.permission { permission = selected }
    }
}

private enum RemainingAcceptanceError: Error { case nativeButtonsUnavailable, presentationTimeout, appearanceTimeout }

@MainActor
private final class RemainingHostingController: UIHostingController<AnyView> {
    private(set) var hasAppeared = false
    private(set) var hasDisappeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        hasDisappeared = false
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hasDisappeared = true
    }
}

/// Owns the child appearance pairs, including explicit removal before hiding the window.
@MainActor
private final class RemainingContainerController: UIViewController {
    let host: RemainingHostingController
    private var pendingAppearance: Bool?
    private var childIsVisible = false
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    init(host: RemainingHostingController) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        beginChildAppearance(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        endChildAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        beginChildAppearance(false, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        endChildAppearance()
    }

    private func beginChildAppearance(_ appearing: Bool, animated: Bool) {
        guard host.parent === self, pendingAppearance == nil, childIsVisible != appearing else { return }
        pendingAppearance = appearing
        host.beginAppearanceTransition(appearing, animated: animated)
    }

    private func endChildAppearance() {
        guard let appearing = pendingAppearance else { return }
        host.endAppearanceTransition()
        childIsVisible = appearing
        pendingAppearance = nil
    }

    func removeHostedContent() {
        guard host.parent === self else { return }
        endChildAppearance()
        host.willMove(toParent: nil)
        beginChildAppearance(false, animated: false)
        host.view.removeFromSuperview()
        endChildAppearance()
        host.removeFromParent()
    }
}

@MainActor
private final class RemainingAcceptanceWindow {
    let window: UIWindow
    private let host: RemainingHostingController
    private let container: RemainingContainerController
    private let previousKeyWindow: UIWindow?
    private(set) var isClosed = false

    init<Content: View>(content: Content) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        host = RemainingHostingController(rootView: AnyView(content.environment(\.dynamicTypeSize, .accessibility5).environment(\.locale, Locale(identifier: "ja_JP"))))
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        container = RemainingContainerController(host: host)
        container.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.rootViewController = container
    }

    func show() async throws {
        window.makeKeyAndVisible()
        let deadline = ContinuousClock.now + .seconds(5)
        while !host.hasAppeared, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(host.hasAppeared, "The real hosting controller did not finish appearing")
    }

    func waitForPresentedController(matching predicate: (UIViewController) -> Bool) async throws -> UIViewController {
        func find(_ controller: UIViewController) -> UIViewController? {
            if predicate(controller), controller.presentingViewController != nil { return controller }
            if let presented = controller.presentedViewController, let found = find(presented) { return found }
            for child in controller.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            window.layoutIfNeeded()
            if let presented = find(container), presented.transitionCoordinator == nil, presented.view.window != nil {
                presented.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                return presented
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw RemainingAcceptanceError.presentationTimeout
    }

    func close() async throws {
        guard !isClosed else { return }
        if container.presentedViewController != nil || host.presentedViewController != nil {
            await withCheckedContinuation { continuation in container.dismiss(animated: false) { continuation.resume() } }
        }
        container.removeHostedContent()
        try #require(!host.hasAppeared || host.hasDisappeared, "The explicitly removed child must finish its paired disappearance")
        window.isHidden = true
        window.rootViewController = nil
        if let previousKeyWindow, !previousKeyWindow.isHidden { previousKeyWindow.makeKey() }
        isClosed = true
    }
}

@MainActor
private func withRemainingWindow<Content: View>(content: Content, operation: (RemainingAcceptanceWindow) async throws -> Void) async throws {
    let host = try RemainingAcceptanceWindow(content: content)
    do {
        try await host.show()
        try await operation(host)
        try await host.close()
    } catch {
        let failure = error
        if !host.isClosed {
            do { try await host.close() }
            catch { Issue.record("Native host teardown also failed: \(error)") }
        }
        throw failure
    }
}

@MainActor
private struct RemainingAcceptanceRun {
    let scene: String
    let directory: URL

    init(scene: String) throws {
        self.scene = scene
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["PHLOX_REMAINING_OUTPUT"]
            ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining").path
        try #require(path.hasPrefix("/"))
        directory = URL(fileURLWithPath: path).appendingPathComponent("\(scene)-ios\(UIDevice.current.systemVersion)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("remaining acceptance output: \(directory.path)")
    }

    func write(name: String, payload: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    }

    func requestExternalScroll(window: UIWindow, scroll: UIScrollView, action: String) async throws {
        let before = scroll.contentOffset.y
        try await captureAndHold(window: window, name: "\(action)-before", payload: remainingScrollMetrics(scroll), allowHold: false)
        let nonce = UUID().uuidString
        let ack = directory.appendingPathComponent("\(action)-\(nonce)-ack.json")
        let pid = ProcessInfo.processInfo.processIdentifier
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let requestedAt = Date().timeIntervalSince1970
        try write(name: "\(action)-ready", payload: [
            "scene": scene, "step": action, "action": action, "phase": "awaitingScroll", "nonce": nonce,
            "pid": pid, "udid": udid, "requestedAt": requestedAt, "ackFile": ack.path,
            "screenshotFile": directory.appendingPathComponent("\(action)-before.png").path,
            "viewportRectInWindow": remainingRect(scroll.convert(scroll.bounds, to: window)),
            "previousOffsetY": Double(before),
            "targetOffsetY": Double(action == "scrollToBottom" ? remainingBottom(scroll) : remainingTop(scroll)),
        ])
        print("remaining acceptance awaitingScroll: \(directory.appendingPathComponent("\(action)-ready.json").path)")
        let deadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: ack.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(FileManager.default.fileExists(atPath: ack.path), "External CUA scroll acknowledgement was not provided")
        let reply = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any])
        try #require(reply["nonce"] as? String == nonce && reply["scene"] as? String == scene)
        try #require(reply["step"] as? String == action && reply["action"] as? String == action)
        try #require((reply["pid"] as? NSNumber)?.int32Value == pid && reply["udid"] as? String == udid)
        try #require(reply["phase"] as? String == "acted" && reply["confirmed"] as? Bool == true)
        let capturedAt = try #require(reply["capturedAt"] as? Double)
        try #require(capturedAt >= requestedAt && capturedAt <= Date().timeIntervalSince1970 + 5)
        try await Task.sleep(for: .milliseconds(400))
        try write(name: "\(action)-acted", payload: reply)
        try write(name: "\(action)-actual", payload: remainingScrollMetrics(scroll))
        // The caller requires actual movement and the actual edge; acknowledgement alone cannot pass.
    }

    func captureAndHold(window: UIWindow, name: String, payload: [String: Any], allowHold: Bool = true) async throws {
        try write(name: name, payload: payload)
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(drawn)
        let screenshot = directory.appendingPathComponent("\(name).png")
        let png = try #require(image.pngData())
        try png.write(to: screenshot, options: .atomic)
        guard allowHold, ProcessInfo.processInfo.environment["PHLOX_REMAINING_HOLD"] == "1" else { return }
        let nonce = UUID().uuidString
        let ack = directory.appendingPathComponent("\(name)-\(nonce)-ack.json")
        let pid = ProcessInfo.processInfo.processIdentifier
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let requestedAt = Date().timeIntervalSince1970
        let ready: [String: Any] = [
            "scene": scene, "step": name, "phase": "awaitingCUA", "nonce": nonce, "pid": pid, "udid": udid,
            "requestedAt": requestedAt, "ackFile": ack.path, "screenshotFile": screenshot.path,
            "nativeContentSizeCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
        ]
        try write(name: "\(name)-ready", payload: ready)
        print("remaining acceptance awaitingCUA: \(directory.appendingPathComponent("\(name)-ready.json").path)")
        let deadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: ack.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(FileManager.default.fileExists(atPath: ack.path), "The requested fresh CUA visual confirmation was not provided")
        let reply = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any])
        try #require(reply["nonce"] as? String == nonce && reply["scene"] as? String == scene && reply["step"] as? String == name)
        try #require((reply["pid"] as? NSNumber)?.int32Value == pid && reply["udid"] as? String == udid)
        try #require(reply["phase"] as? String == "reviewed" && reply["confirmed"] as? Bool == true)
        let capturedAt = try #require(reply["capturedAt"] as? Double)
        try #require(capturedAt >= requestedAt && capturedAt <= Date().timeIntervalSince1970 + 5)
        try write(name: "\(name)-reviewed", payload: reply)
    }
}
