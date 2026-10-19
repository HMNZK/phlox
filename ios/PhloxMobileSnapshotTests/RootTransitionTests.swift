import SwiftUI
import UIKit
import Testing
import PhloxCore
import PhloxNetworking
import DesignSystemIOS
import Vision
@testable import Features
@testable import PhloxMobile

/// 本物のcomposition rootとnative presentationを同じwindowで結合する。
@MainActor
@Suite(.serialized)
struct RootTransitionTests {
    @Test func noSearchRequestAtStartupOrGateReentryDoesNotPushNewChat() async throws {
        try #require(UITestingSupport.isEnabled)
        let sessions = (0..<40).map { index in
            Session(id: "root-scroll-\(index)", name: "一覧のセッション \(index)", agent: .claudeCode,
                    status: .running, subtitle: "", updatedAt: Date())
        }
        let repository = RootRepository(initial: .loaded(sessions))
        let authenticator = RootControlledAuthenticator()
        defer { Task { await repository.finish(); await authenticator.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let router = NavigationRouter()
        let run = try RootInteractionRun(scene: "RootNoSearchLifecycle")
        let environment = rootEnvironment(repository: repository, sessions: sessions, authenticator: authenticator)
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model, router: router).environment(environment)) { window in
            try await rootWait {
                model.state == .sessions && rootLabels(window).contains(where: { $0.contains("一覧のセッション ") })
                    && rootNativeControlControllers(window).contains { $0.viewIfLoaded?.window === window && $0.viewControllers.count == 1 }
            }
            _ = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "startup-list")
            #expect(router.depth == 0)
            #expect(await authenticator.callCount == 0)
            try run.record(step: "startup", state: ["routerDepth": router.depth, "modelState": String(describing: model.state)])

            model.authState = .locked
            try await rootWait {
                let isWaiting = await authenticator.isWaiting
                let callCount = await authenticator.callCount
                return model.state == .locked && isWaiting && callCount == 1
                    && rootLabels(window).contains(where: { $0.contains("認証しています") })
            }
            #expect(router.depth == 0)
            await authenticator.resolve(true)
            try await rootWait {
                let isWaiting = await authenticator.isWaiting
                return model.state == .sessions && !isWaiting
                    && rootLabels(window).contains(where: { $0.contains("一覧のセッション ") })
                    && rootNativeControlControllers(window).contains { $0.viewIfLoaded?.window === window && $0.viewControllers.count == 1 }
            }
            _ = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "gate-reentry-list")
            #expect(router.depth == 0)
            #expect(model.authState == .unlocked)
            #expect(await authenticator.callCount == 1)
            try run.record(step: "gate-reentry", state: [
                "routerDepth": router.depth, "modelState": String(describing: model.state),
                "ownedNativeStackCounts": rootNativeControlControllers(window).filter { $0.viewIfLoaded?.window === window }.map { $0.viewControllers.count },
            ])
        }
    }

    @Test(arguments: [false, true])
    func repeatedDirectPushNativePopControl(resetEmptyPathBeforePush: Bool) async throws {
        try #require(UITestingSupport.isEnabled)
        let sessions = (0..<40).map { index in
            Session(id: "root-scroll-\(index)", name: "一覧のセッション \(index)", agent: .claudeCode,
                    status: .running, subtitle: "", updatedAt: Date())
        }
        let repository = RootRepository(initial: .loaded(sessions))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let router = NavigationRouter()
        let run = try RootInteractionRun(scene: "RepeatedDirectPushNativeBack-reset-\(resetEmptyPathBeforePush)")
        let environment = rootEnvironment(repository: repository, sessions: sessions)
        let mode = "repeat-direct-reset-\(resetEmptyPathBeforePush)"
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model, router: router).environment(environment)) { window in
            var navigation: UINavigationController?
            var tabBar: UITabBar?
            try await rootWait {
                navigation = rootNativeControlControllers(window).first { candidate in
                    guard let view = candidate.viewIfLoaded else { return false }
                    return view.window === window && candidate.viewControllers.count == 1
                        && rootObjects(view).contains { $0.accessibilityLabel?.contains("一覧のセッション ") == true }
                }
                tabBar = rootObjects(window).compactMap { $0 as? UITabBar }.first
                return navigation != nil && tabBar?.selectedItem?.title == "セッション" && router.depth == 0
            }
            let owned = try #require(navigation)
            let bar = try #require(tabBar)
            for iteration in 1...2 {
                try await rootWait {
                    owned.viewControllers.count == 1 && router.depth == 0
                        && owned.transitionCoordinator == nil && bar.selectedItem?.title == "セッション"
                }
                _ = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "loop-\(iteration)-stable-root")
                try rootRecordFinalBack(run, phase: "loop-\(iteration)-before-push", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                if resetEmptyPathBeforePush { router.popToRoot() }
                try rootRecordFinalBack(run, phase: "loop-\(iteration)-after-optional-empty-reset", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                router.push(.newChat(SessionComposeDraft(project: "")))
                do { try await rootWait { owned.viewControllers.count == 2 && router.depth == 1 } }
                catch {
                    try rootRecordFinalBack(run, phase: "loop-\(iteration)-push-timeout", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                    throw error
                }
                try rootRecordFinalBack(run, phase: "loop-\(iteration)-after-push", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                try #require(owned.viewIfLoaded?.window === window)
                try #require(owned.popViewController(animated: true) != nil)
                try rootRecordFinalBack(run, phase: "loop-\(iteration)-after-public-pop", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                do { try await rootWait { owned.viewControllers.count == 1 && router.depth == 0 } }
                catch {
                    try rootRecordFinalBack(run, phase: "loop-\(iteration)-pop-sync-timeout", router: router, oldBar: bar, window: window, mode: mode, control: owned)
                    throw error
                }
                try rootRecordFinalBack(run, phase: "loop-\(iteration)-pop-synchronized", router: router, oldBar: bar, window: window, mode: mode, control: owned)
            }
        }
    }

    @Test func directPushNativePopControlSynchronizesTheActualRootPath() async throws {
        try #require(UITestingSupport.isEnabled)
        let sessions = (0..<40).map { index in
            Session(id: "root-scroll-\(index)", name: "一覧のセッション \(index)", agent: .claudeCode,
                    status: .running, subtitle: "", updatedAt: Date())
        }
        let repository = RootRepository(initial: .loaded(sessions))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let router = NavigationRouter()
        let run = try RootInteractionRun(scene: "DirectPushNativeBackControl")
        let environment = rootEnvironment(repository: repository, sessions: sessions)
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model, router: router).environment(environment)) { window in
            var navigation: UINavigationController?
            @MainActor
            func record(_ phase: String) throws {
                let controllers = rootNativeControlControllers(window)
                try run.record(step: phase, state: [
                    "phase": phase, "routerDepth": router.depth, "windowIsKey": window.isKeyWindow,
                    "navigationControllers": controllers.map { controller in
                        ["identity": String(describing: ObjectIdentifier(controller)), "type": String(reflecting: type(of: controller)),
                         "count": controller.viewControllers.count, "ownedWindow": controller.viewIfLoaded?.window === window,
                         "selectedControl": controller === navigation,
                         "controllers": controller.viewControllers.map { child in
                             ["type": String(reflecting: type(of: child)), "title": child.title ?? "",
                              "ownedWindow": child.viewIfLoaded?.window === window,
                              "frame": String(describing: child.viewIfLoaded?.frame)] as [String: Any]
                         }] as [String: Any]
                    },
                ])
            }
            try await rootWait {
                navigation = rootNativeControlControllers(window).first { candidate in
                    guard let view = candidate.viewIfLoaded else { return false }
                    return view.window === window && candidate.viewControllers.count == 1
                        && rootObjects(view).contains { $0.accessibilityLabel?.contains("一覧のセッション ") == true }
                }
                return navigation != nil && rootLabels(window).contains(where: { $0.contains("一覧のセッション ") })
            }
            _ = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "root-stable")
            try record("before-direct-push")
            router.push(.newChat(SessionComposeDraft(project: "")))
            do { try await rootWait { (navigation?.viewControllers.count ?? 0) >= 2 && router.depth == 1 } }
            catch { try record("direct-push-timeout"); throw error }
            try record("after-direct-push")
            let owned = try #require(navigation)
            try #require(owned.viewIfLoaded?.window === window)
            try #require(owned.popViewController(animated: true) != nil)
            try record("after-public-native-pop")
            do { try await rootWait { owned.viewControllers.count == 1 && router.depth == 0 } }
            catch { try record("native-pop-sync-timeout"); throw error }
            try record("native-pop-synchronized")
        }
    }

    @Test(arguments: [false, true])
    func relockHidesConnectingAndFailureWithoutDiscardingThem(hasFailure: Bool) async throws {
        try #require(UITestingSupport.isEnabled)
        let failure = ConnectFailure(title: "接続失敗の保持", message: "再試行できます", detail: "HTTP 503")
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online,
                             isConnecting: true, connectFailure: hasFailure ? failure : nil)
        let repository = RootRepository(initial: .empty)
        defer { Task { await repository.finish() } }
        let authenticator = RootControlledAuthenticator()
        defer { Task { await authenticator.finish() } }
        let environment = rootEnvironment(repository: repository, authenticator: authenticator)
        let push = PushCoordinator()
        try await withRootWindow(AppRoot(pushCoordinator: push, model: model).environment(environment)) { window in
            let overlayLabel = hasFailure ? failure.title : "接続中"
            try await rootWait { rootLabels(window).contains(where: { $0.contains(overlayLabel) }) }
            let overlayImageText = hasFailure ? failure.title : "Macに接続しています"
            let beforeLock = try await rootCapture(window, name: hasFailure ? "failure-before-lock" : "connecting-before-lock",
                                                  requiredTextGroups: [[overlayImageText]])
            model.authState = .locked
            try await rootWait {
                let labels = rootLabels(window)
                let isWaiting = await authenticator.isWaiting
                let callCount = await authenticator.callCount
                return isWaiting && callCount == 1
                    && labels.contains(where: { $0.contains("認証しています") })
                    && labels.contains(where: { $0.contains("Face ID") })
                    && !labels.contains(where: { $0.contains(overlayLabel) })
            }
            #expect(model.authState == .locked && model.state == .locked)
            #expect(!rootLabels(window).contains(where: { $0.contains(overlayLabel) }))
            #expect(model.isConnecting)
            #expect(model.connectFailure == (hasFailure ? failure : nil))
            let locked = try await rootCapture(window, name: hasFailure ? "failure-locked" : "connecting-locked", differentFrom: beforeLock,
                                              requiredTextGroups: [["認証しています"], ["FaceID"]],
                                              forbiddenText: [overlayImageText])
            #expect(locked != beforeLock)
            await authenticator.resolve(true)
            try await rootWait {
                let isWaiting = await authenticator.isWaiting
                return model.authState == .unlocked && !isWaiting
            }
            #expect(await authenticator.callCount == 1)
            try await rootWait { rootLabels(window).contains(where: { $0.contains(overlayLabel) }) }
            #expect(model.isConnecting)
            #expect(model.connectFailure == (hasFailure ? failure : nil))
            let unlocked = try await rootCapture(window, name: hasFailure ? "failure-unlocked" : "connecting-unlocked", differentFrom: locked,
                                                requiredTextGroups: [[overlayImageText]])
            #expect(unlocked != locked)
        }
    }

    @Test func relockDismissesMissingSessionNativeAlertBeforeGate() async throws {
        try #require(UITestingSupport.isEnabled)
        let session = Session(id: "root-existing", name: "通知検査の一覧", agent: .claudeCode,
                              status: .running, subtitle: "", updatedAt: Date())
        let repository = RootRepository(initial: .loaded([session]))
        let authenticator = RootControlledAuthenticator()
        defer { Task { await repository.finish(); await authenticator.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let push = PushCoordinator()
        let run = try RootInteractionRun(scene: "MissingSessionAlertRelock")
        let environment = rootEnvironment(repository: repository, sessions: [session], authenticator: authenticator)
        try await withRootWindow(AppRoot(pushCoordinator: push, model: model).environment(environment)) { window in
            @MainActor
            func visibleAlerts(_ controller: UIViewController) -> [UIAlertController] {
                let own = (controller as? UIAlertController).map { $0.viewIfLoaded?.window === window ? [$0] : [] } ?? []
                return own + controller.children.flatMap(visibleAlerts)
                    + (controller.presentedViewController.map(visibleAlerts) ?? [])
            }
            @MainActor
            func alerts() -> [UIAlertController] { window.rootViewController.map(visibleAlerts) ?? [] }
            @MainActor
            func hasCanonicalRow(_ value: Session) -> Bool {
                rootObjects(window).contains {
                    $0.accessibilityLabel == SessionListRowPresentation(session: value, depth: 0).accessibilityLabel
                }
            }
            @MainActor
            func record(_ phase: String) throws {
                try run.record(step: phase, state: [
                    "modelState": String(describing: model.state), "labels": rootLabels(window),
                    "pendingSessionID": push.pendingSessionID ?? "none",
                    "windowIsKey": window.isKeyWindow, "windowHidden": window.isHidden,
                    "sceneActivationState": String(describing: window.windowScene?.activationState),
                    "uiTestingScreen": String(describing: UITestingSupport.screen),
                    "accessibilityElements": rootObjects(window).map {
                        ["label": $0.accessibilityLabel ?? "",
                         "identifier": ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""]
                    },
                    "visibleAlerts": alerts().map { ["class": String(reflecting: type(of: $0)), "title": $0.title ?? ""] },
                ])
            }
            try record("before-initial-list-wait")
            let entry = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "before-initial-list-wait")
            try entry.png.write(to: run.directory.appendingPathComponent("before-initial-list-wait.png"))
            do {
                try await rootWait {
                    let matchesRepository = await repository.matchesLoaded([session])
                    return model.state == .sessions && matchesRepository && hasCanonicalRow(session)
                }
            } catch {
                try record("initial-list-timeout")
                let capture = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "initial-list-timeout")
                try capture.png.write(to: run.directory.appendingPathComponent("initial-list-timeout.png"))
                throw error
            }
            let initial = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "before-missing-push")
            try initial.png.write(to: run.directory.appendingPathComponent("before-missing-push.png"))
            try record("before-missing-push")
            try #require(push.handleSessionURL(try #require(URL(string: "phlox://session/root-missing"))))
            try #require(push.pendingSessionID == "root-missing")
            try record("missing-push-pending")
            let refreshed = Session(id: session.id, name: "通知後に更新された一覧", agent: .claudeCode,
                                    status: .running, subtitle: "", updatedAt: Date())
            await repository.emit(.loaded([refreshed]))
            try record("fresh-list-emitted")
            do {
                try await rootWait {
                    let matchesRepository = await repository.matchesLoaded([refreshed])
                    return model.state == .sessions && matchesRepository && hasCanonicalRow(refreshed)
                        && push.pendingSessionID == nil
                }
                try record("fresh-list-observed-push-consumed")
                _ = try await rootAlert(in: window, title: "このセッションは見つかりません")
            } catch {
                try record("missing-alert-prerequisite-timeout")
                let capture = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "missing-alert-prerequisite-timeout")
                try capture.png.write(to: run.directory.appendingPathComponent("missing-alert-prerequisite-timeout.png"))
                throw error
            }
            try record("missing-alert-presented")
            model.authState = .locked
            do {
                try await rootWait {
                    let waiting = await authenticator.isWaiting
                    return model.state == .locked && waiting
                        && rootLabels(window).contains(where: { $0.contains("認証しています") }) && alerts().isEmpty
                }
            } catch {
                try record("gate-priority-timeout")
                let capture = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "gate-priority-timeout")
                try capture.png.write(to: run.directory.appendingPathComponent("gate-priority-timeout.png"))
                throw error
            }
            #expect(await authenticator.callCount == 1)
            #expect(alerts().isEmpty)
            try record("gate-priority-confirmed")
            _ = try await rootCapture(window, name: "missing-alert-relocked",
                                      requiredTextGroups: [["認証しています"], ["FaceID"]],
                                      forbiddenText: ["このセッションは見つかりません"])
            await authenticator.resolve(true)
            try await rootWait {
                let waiting = await authenticator.isWaiting
                return model.authState == .unlocked && !waiting
            }
        }
    }

    @Test func lockedPushWaitsForUnlockAndFreshListThenReplacesOldRoute() async throws {
        try #require(UITestingSupport.isEnabled)
        let session = Session(id: "root-push", name: "通知先のセッション", agent: .claudeCode,
                              status: .running, subtitle: "", updatedAt: Date())
        let repository = RootRepository(initial: .loaded([session]))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .locked, hasConnectionConfig: true, reachability: .online)
        let router = NavigationRouter()
        router.push(.settings)
        router.push(.settings)
        router.present(.deleteConfirmation(id: session.id, cascadeCount: 0))
        let push = PushCoordinator()
        let environment = rootEnvironment(repository: repository, sessions: [session])
        try await withRootWindow(AppRoot(pushCoordinator: push, model: model, router: router).environment(environment)) { window in
            try await rootWait { rootLabels(window).contains(where: { $0.contains("Face ID") }) }
            #expect(push.handleSessionURL(try #require(URL(string: "phlox://session/root-push"))))
            await repository.emit(.loaded([session]))
            try await Task.sleep(for: .milliseconds(150))
            #expect(push.pendingSessionID == session.id)
            #expect(router.depth == 2)
            #expect(router.presented == .deleteConfirmation(id: session.id, cascadeCount: 0))
            model.authState = .unlocked
            await repository.emit(.loaded([session]))
            try await rootWait { push.pendingSessionID == nil && router.depth == 1 }
            #expect(router.presented == nil)
            try await rootWait { rootLabels(window).contains(where: { $0.contains(session.name) }) }
        }
    }

    @Test func realRootTimeoutProducesC1AndRetryReturnsToSessions() async throws {
        try #require(UITestingSupport.isEnabled)
        let repository = RootRepository(initial: .offline)
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online,
                             isConnecting: true,
                             connectFailure: ConnectFailure(title: "接続の再試行待ち", message: ""))
        let config = InMemoryConnectionConfigStore(ConnectionConfig(host: "100.96.24.10", port: 9123))
        let environment = rootEnvironment(repository: repository)
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model,
                                         connectTimeout: 0, configStore: config).environment(environment)) { window in
            try await rootWait { rootLabels(window).contains("再試行") }
            try rootActivate(label: "再試行", in: window)
            try await rootWait { model.connectFailure?.title == "Mac から一覧を読み込めませんでした" }
            let failure = try #require(model.connectFailure)
            #expect(failure.message == "接続先は保存しました。20 秒待っても Mac から応答がありません。")
            #expect(failure.detail == "GET http://100.96.24.10:9123/sessions · 20 秒で無応答")
            #expect(failure.checklist == ["Mac がスリープしていない", "Mac で Phlox が起動している", "Mac と iPhone の Tailscale がオンになっている"])
            try await rootWait { rootLabels(window).contains(where: { $0.contains(failure.title) }) }
            let timeoutImage = try await rootCapture(window, name: "root-C1-timeout",
                                                      requiredTextGroups: [[failure.title], ["接続先は保存しました"]],
                                                      forbiddenText: ["接続の再試行待ち"])
            await repository.emit(.empty)
            try await Task.sleep(for: .milliseconds(200))
            try rootActivate(label: "再試行", in: window)
            try await rootWait { !model.isConnecting }
            try await rootWait {
                let labels = rootLabels(window)
                return labels.contains(where: { $0.contains(EmptyStateCopy.title) })
                    && !labels.contains(where: { $0.contains(failure.title) || $0 == "接続中" || $0 == "再試行" })
            }
            #expect(model.connectFailure == nil)
            #expect(config.load() == ConnectionConfig(host: "100.96.24.10", port: 9123))
            let recoveredImage = try await rootCapture(window, name: "root-C1-retry-success", differentFrom: timeoutImage,
                                                       requiredTextGroups: [[EmptyStateCopy.title]], forbiddenText: [failure.title])
            #expect(recoveredImage != timeoutImage)
        }
    }

    @Test func rateLimitedRepositoryErrorReachesRealRootCatalogCard() async throws {
        try #require(UITestingSupport.isEnabled)
        let repository = RootRepository(initial: .error(.rateLimited(retryAfter: 20)))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let environment = rootEnvironment(repository: repository)
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model).environment(environment)) { window in
            try await rootWait {
                let labels = rootLabels(window)
                return labels.contains(where: { $0.contains("Mac が混み合っています") })
                    && labels.contains(where: { $0.contains("HTTP 429") })
            }
            try await rootCapture(window, name: "root-F3-rate-limit-neutral-color-review")
        }
    }

}

@MainActor
private func rootNativeControlControllers(_ window: UIWindow) -> [UINavigationController] {
    @MainActor
    func visit(_ controller: UIViewController) -> [UINavigationController] {
        let current = (controller as? UINavigationController).map { [$0] } ?? []
        return current + controller.children.flatMap(visit)
    }
    return window.rootViewController.map(visit) ?? []
}

/// 親CUAの実操作をnonceで結び付ける。自動suiteとは実行対象を分ける。
@MainActor
@Suite(.serialized)
struct RootInteractiveTransitionTests {
    @Test func realRootFingerPanPreservesVisibleAttentionAndRecordsNativeTabGeometry() async throws {
        try #require(UITestingSupport.isEnabled)
        let attention = Session(id: "root-pan-attention", name: "指ドラッグ検査の承認", agent: .claudeCode,
                                status: .awaitingApproval(prompt: "変更を承認"), updatedAt: Date())
        let sessions = [attention] + (0..<39).map { index in
            Session(id: "root-pan-\(index)", name: "指ドラッグ検査の一覧 \(index)", agent: .claudeCode,
                    status: .running, updatedAt: Date())
        }
        let repository = RootRepository(initial: .loaded(sessions))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let environment = rootEnvironment(repository: repository, sessions: sessions)
        let run = try RootInteractionRun(scene: "RootFingerPanAttention")
        let touchTrace = RootTouchDeliveryTrace()
        let status = try #require(SessionListRowPresentation(session: attention, depth: 0).statusLabel)
        let attentionLabel = "対応待ち 1 件。先頭は \(attention.name)、\(status)。開く"
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model).environment(environment), touchTrace: touchTrace) { window in
            @MainActor
            func frame(_ object: NSObject) -> CGRect {
                window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
            }
            @MainActor
            func visibleAttention() -> Bool {
                rootObjects(window).contains {
                    let rect = frame($0)
                    return $0.accessibilityLabel == attentionLabel
                        && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                        && rect.width > 0 && rect.height > 0 && window.bounds.contains(rect)
                }
            }
            @MainActor
            func geometry(_ scroll: UIScrollView) -> [String: Any] {
                let objects = rootObjects(window)
                let controls = objects.filter { $0 is UIControl || $0.accessibilityLabel != nil }
                return ["scroll": rootScrollState(scroll), "labels": rootLabels(window),
                        "modelState": String(describing: model.state), "attentionLabel": attentionLabel,
                        "controlsAndAX": controls.map { object in
                            let rect = frame(object)
                            let finite = [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                            return ["class": String(reflecting: type(of: object)), "label": object.accessibilityLabel ?? "",
                                    "frameFinite": finite, "frame": finite ? rootRect(rect) : [],
                                    "insideWindow": finite && window.bounds.contains(rect)] as [String: Any]
                        },
                        "tabBars": objects.compactMap { $0 as? UITabBar }.map { bar in
                            ["frame": String(describing: bar.convert(bar.bounds, to: window)),
                             "hidden": bar.isHidden, "alpha": Double(bar.alpha),
                             "items": (bar.items ?? []).map { $0.title ?? "" }] as [String: Any]
                        },
                        "interpretation": "Tab container geometry and item count do not prove 56pt minimization or OS placement; review fresh full-size images"]
            }
            var list: UIScrollView?
            try await rootWait {
                list = rootObjects(window).compactMap { $0 as? UIScrollView }.first {
                    $0.window === window && $0.isScrollEnabled && $0.bounds.height > 0
                        && $0.contentSize.height > $0.bounds.height * 2
                }
                return model.state == .sessions && list != nil && visibleAttention()
            }
            let scroll = try #require(list)
            let before = scroll.contentOffset.y
            try run.record(step: "before-pan", state: geometry(scroll))
            try run.record(step: "touch-delivery-before-pan", state: touchTrace.state(window: window))
            do {
                try await run.waitForCUA(window: window, step: "scroll",
                    instruction: "一覧中央で指による上向きdragを1回行い、下の行へスクロールする。AXScrollToVisible・wheel・offset設定は使わない。対応待ち/タブ/新規チャットは押さない。fresh全画面でタブの丸の実境界と対応待ちとの配置を観測しACKする。",
                    state: geometry(scroll))
                try run.record(step: "touch-delivery-after-ack", state: touchTrace.state(window: window))
                try await rootWait {
                    let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
                    let visibleRow = rootObjects(scroll).contains {
                        let rect = frame($0)
                        return $0.accessibilityLabel?.hasPrefix("指ドラッグ検査の一覧 ") == true
                            && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                            && rect.width > 0 && rect.height > 0 && viewport.intersects(rect)
                    }
                    return scroll.contentOffset.y > before + 1 && visibleAttention() && model.state == .sessions
                        && visibleRow
                        && [viewport.minX, viewport.minY, viewport.width, viewport.height].allSatisfy(\.isFinite)
                        && viewport.width > 0 && viewport.height > 0 && window.bounds.intersects(viewport)
                }
            } catch {
                try run.record(step: "touch-delivery-timeout-or-error", state: touchTrace.state(window: window))
                throw error
            }
            let capture = try await rootFreshPNG(window, diagnosticDirectory: run.directory, diagnosticName: "after-pan")
            try capture.png.write(to: run.directory.appendingPathComponent("after-pan-window.png"))
            try run.record(step: "after-pan", state: geometry(scroll))
        }
    }

    @Test func realC1TimeoutChecklistAndEndpointAreReachableByExternalScroll() async throws {
        try #require(UITestingSupport.isEnabled)
        let repository = RootRepository(initial: .offline)
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online,
                             isConnecting: true, connectFailure: ConnectFailure(title: "接続の再試行待ち", message: ""))
        let environment = rootEnvironment(repository: repository)
        let run = try RootInteractionRun(scene: "C1TimeoutBodyScroll")
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model, connectTimeout: 0,
                                         configStore: InMemoryConnectionConfigStore(ConnectionConfig(host: "100.96.24.10", port: 9123)))
            .environment(environment)) { window in
            try await rootWait { rootLabels(window).contains("再試行") }
            try rootActivate(label: "再試行", in: window)
            try await rootWait { model.connectFailure?.checklist.count == 3 }
            let failure = try #require(model.connectFailure)
            try await rootCapture(window, name: "root-C1-before-body-scroll")
            let scrolls = rootObjects(window).compactMap { $0 as? UIScrollView }.filter {
                $0.isScrollEnabled && rootObjects($0).contains(where: { $0.accessibilityLabel?.contains(failure.title) == true })
            }
            let scroll = try #require(scrolls.first, "The actual C1 content must be hosted by a native scroll view")
            let initial = scroll.contentOffset.y
            if scroll.contentSize.height > scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom {
                try await run.waitForCUA(window: window, step: "body-scroll", instruction: "C1失敗本文を下端まで実スクロールし、3確認項目とGET http://100.96.24.10:9123/sessionsの技術行を読める位置にする。再試行/閉じるは押さない", state: rootScrollState(scroll))
                try await rootWait { scroll.contentOffset.y > initial + 1 }
            }
            let detail = try #require(failure.detail)
            let detailElement = try #require(rootObjects(scroll).first { $0.accessibilityLabel?.contains(detail) == true })
            let detailFrame = window.convert(detailElement.accessibilityFrame, from: window.screen.coordinateSpace)
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window).intersection(window.bounds)
            try #require(detailFrame.height > 0 && detailFrame.minY >= viewport.minY - 1 && detailFrame.maxY <= viewport.maxY + 1,
                         "The actual endpoint text must be fully reachable inside the visible scroll viewport")
            try run.record(step: "body-scroll-result", state: rootScrollState(scroll).merging(["detailFrame": rootRect(detailFrame), "viewport": rootRect(viewport)]) { _, new in new })
            try await rootCapture(window, name: "root-C1-endpoint-after-body-scroll", requiredTextGroups: [["100.96.24.10:9123"]])
        }
    }

    @Test func realRootSessionListScrollAndSettingsTabUseExternalInput() async throws {
        try #require(UITestingSupport.isEnabled)
        let sessions = (0..<40).map { index in
            Session(id: "root-scroll-\(index)", name: "一覧のセッション \(index)", agent: .claudeCode,
                    status: .running, subtitle: "", updatedAt: Date())
        }
        let repository = RootRepository(initial: .loaded(sessions))
        defer { Task { await repository.finish() } }
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        let router = NavigationRouter()
        let environment = rootEnvironment(repository: repository, sessions: sessions)
        let run = try RootInteractionRun(scene: "RootListScrollAndSettings")
        let processEnvironment = ProcessInfo.processInfo.environment
        let directComposeControl = (processEnvironment["PHLOX_ROOT_DIRECT_COMPOSE_CONTROL"]
            ?? processEnvironment["TEST_RUNNER_PHLOX_ROOT_DIRECT_COMPOSE_CONTROL"]) == "1"
        try await withRootWindow(AppRoot(pushCoordinator: PushCoordinator(), model: model, router: router).environment(environment)) { window in
            var list: UIScrollView?
            try await rootWait {
                list = rootObjects(window).compactMap { $0 as? UIScrollView }.first {
                    $0.isScrollEnabled && $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height * 2
                }
                return list != nil
            }
            if #unavailable(iOS 26) {
                @MainActor
                func visibleLegacyHeaderAction() -> Bool {
                    rootObjects(window).contains {
                        let rect = window.convert($0.accessibilityFrame, from: window.screen.coordinateSpace)
                        return $0.accessibilityLabel == "新規チャット"
                            && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                            && rect.width > 0 && rect.height > 0 && window.bounds.contains(rect)
                    }
                }
                try await rootWait { router.depth == 0 && visibleLegacyHeaderAction() }
                let proof = try await run.waitForCUA(window: window, step: "legacy-header-compose",
                    instruction: "初期一覧topの『セッション』見出し右『新規チャット』を実tap。本物newChatのfresh AX原文/rawAXTreeとwindowTitleを保存してACK。送信せずBackもまだ押さない")
                try await rootWaitForNewChat(run, phase: "legacy-header-compose", router: router, window: window, proof: proof)
                try await run.waitForCUA(window: window, step: "legacy-header-compose-back",
                    instruction: "左上の本物Backを実tapして一覧へ戻りACK。タブは押さない")
                try await rootWait {
                    let tabs = rootObjects(window).compactMap { $0 as? UITabBar }
                    return router.depth == 0 && tabs.contains { $0.window === window && $0.selectedItem?.title == "セッション" }
                        && visibleLegacyHeaderAction() && rootLabels(window).contains(where: { $0.contains("一覧のセッション ") })
                }
                try run.record(step: "legacy-header-return", state: ["routerDepth": router.depth, "labels": rootLabels(window)])
                try await rootWait {
                    list = rootObjects(window).compactMap { $0 as? UIScrollView }.first {
                        $0.window === window && $0.isScrollEnabled && $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height * 2
                    }
                    return list != nil
                }
            }
            let scroll = try #require(list)
            let initial = scroll.contentOffset.y
            try await run.waitForCUA(window: window, step: "scroll", instruction: "本物のセッション一覧を下へスクロールする。タブはまだ押さない", state: rootScrollState(scroll))
            try await rootWait { scroll.contentOffset.y > initial + 1 }
            try run.record(step: "scroll-result", state: rootScrollState(scroll))
            try await rootCapture(window, name: "root-list-after-external-scroll")
            let tabBar = try #require(rootObjects(window).compactMap { $0 as? UITabBar }.first)
            let tabFrame = tabBar.convert(tabBar.bounds, to: window)
            try #require(tabFrame.width > 0 && tabFrame.height > 0 && window.bounds.intersects(tabFrame))
            let tabController = window.rootViewController.flatMap { rootTabController($0, owning: tabBar) }
            let items = try #require(tabBar.items)
            let navigationTitles = ["セッション", "設定"]
            let actionItems = items.filter { !navigationTitles.contains($0.title ?? "") }
            try run.record(step: "tab-roles", state: [
                "tabBarItemTitles": (tabBar.items ?? []).map { $0.title ?? "" },
                "tabs": (tabController?.tabs ?? []).map { tab in
                    ["identifier": tab.identifier, "title": tab.title, "type": String(reflecting: type(of: tab)),
                     "role": tab is UISearchTab ? "search-action" : "navigation"]
                },
            ])
            #expect(items.filter { $0.title == "セッション" }.count == 1)
            #expect(items.filter { $0.title == "設定" }.count == 1)
            if #available(iOS 26, *) {
                #expect(actionItems.count == 1)
            } else {
                #expect(actionItems.isEmpty)
            }
            try await run.waitForCUA(window: window, step: "settings", instruction: "スクロール後の本物『設定』タブを押す", state: rootScrollState(scroll).merging(["tabFrame": rootRect(tabFrame)]) { _, new in new })
            try await rootWait { tabBar.selectedItem?.title == "設定" }
            #expect(router.depth == 0)
            try await rootWait { rootLabels(window).contains(where: { $0.contains("プッシュ通知を受け取る") }) }
            try await rootCapture(window, name: "root-settings-after-real-tab-tap")
            if #available(iOS 26, *) {
                if directComposeControl {
                    try await run.waitForCUA(window: window, step: "settings-select-sessions-for-direct-control", instruction: "全search排除対照。設定から本物『セッション』タブだけをtap。circleは押さず一覧に切り替わったところでack")
                    try await rootWait { tabBar.selectedItem?.title == "セッション" && router.depth == 0 }
                    router.push(.newChat(SessionComposeDraft(project: "")))
                }
                let composeInstruction = directComposeControl
                    ? "1回目compose直接push対照。テストが既にnewChatへ直接push済み。circleやBackは押さずfresh CUA AX原文をrawAXTree、実window名をwindowTitleへ保存してack。送信しない"
                    : "設定タブの右独立『新規チャット』circleを1回押す。fresh CUA AX原文をrawAXTreeへ、実window名をwindowTitleへ保存してack。送信しない"
                let proof = try await run.waitForCUA(window: window, step: "settings-compose", instruction: composeInstruction, state: ["directComposeControl": directComposeControl])
                try await rootWaitForNewChat(run, phase: "settings-compose", router: router, window: window, proof: proof)
                #expect(tabBar.selectedItem?.title == "セッション")
                try run.record(step: "settings-compose-result", state: ["routerDepth": router.depth, "selectedTab": tabBar.selectedItem?.title ?? "", "externalNewChatProof": true])
                try await run.waitForCUA(window: window, step: "settings-compose-back", instruction: "左上のホーム印（戻る）で一覧へ戻り、その後『設定』タブを実tap。設定画面に戻ったらack")
                try await rootWait { router.depth == 0 && tabBar.selectedItem?.title == "設定" }
                try await rootWait { rootLabels(window).contains(where: { $0.contains("プッシュ通知を受け取る") }) }
            }
            try await run.waitForCUA(window: window, step: "sessions", instruction: "本物『セッション』タブを押して一覧へ戻る")
            try await rootWait { tabBar.selectedItem?.title == "セッション" }
            #expect(router.depth == 0)
            try await rootCapture(window, name: "root-list-after-tab-return")
            if #available(iOS 26, *) {
                try run.record(step: "sessions-compose-mode", state: ["mode": directComposeControl ? "direct-push-control" : "native-search-circle", "routerDepthBefore": router.depth])
                if directComposeControl {
                    try #require(router.depth == 0 && tabBar.selectedItem?.title == "セッション")
                    router.push(.newChat(SessionComposeDraft(project: "")))
                }
                let composeInstruction = directComposeControl
                    ? "2回目compose直接push対照。テストが既にnewChatへ直接push済み。circleやBackは押さずfresh CUA AX原文をrawAXTree、実window名をwindowTitleへ保存してack。送信しない"
                    : "セッションタブの右独立『新規チャット』circleを1回押す。fresh CUA AX原文をrawAXTreeへ、実window名をwindowTitleへ保存してack。送信しない"
                let proof = try await run.waitForCUA(window: window, step: "sessions-compose", instruction: composeInstruction, state: ["directComposeControl": directComposeControl])
                try await rootWaitForNewChat(run, phase: "sessions-compose", router: router, window: window, proof: proof)
                #expect(tabBar.selectedItem?.title == "セッション")
                try run.record(step: "sessions-compose-result", state: ["routerDepth": router.depth, "selectedTab": tabBar.selectedItem?.title ?? "", "externalNewChatProof": true])
                let publicPopControl = (processEnvironment["PHLOX_ROOT_FINAL_PUBLIC_POP_CONTROL"]
                    ?? processEnvironment["TEST_RUNNER_PHLOX_ROOT_FINAL_PUBLIC_POP_CONTROL"]) == "1"
                let mode = publicPopControl ? "public-native-pop-control" : "native-back"
                try run.record(step: "sessions-compose-back-mode", state: ["mode": mode])
                let instruction = publicPopControl
                    ? "公開UIKit pop対照。Backも他の画面操作も押さず、新規チャットを表示したまま待機解除ackだけを書く。テストが当該owned stackをpublic popする。通常Back成功とは扱わない"
                    : "左上のホーム印（戻る）でセッション一覧へ戻る。戻ったところでack"
                try await run.waitForCUA(window: window, step: "sessions-compose-back", instruction: instruction, state: ["mode": mode])
                var control: UINavigationController?
                if publicPopControl {
                    let candidates = rootNativeControlControllers(window).filter {
                        $0.viewIfLoaded?.window === window && $0.viewControllers.count >= 2
                            && $0.topViewController?.viewIfLoaded?.window === window
                    }
                    try #require(candidates.count == 1, "Only the probe's one visible pushed navigation stack may be popped")
                    control = candidates.first
                    let owned = try #require(control)
                    try rootRecordFinalBack(run, phase: "before-public-pop", router: router, oldBar: tabBar, window: window, mode: mode, control: control)
                    try #require(owned.popViewController(animated: true) != nil)
                    try rootRecordFinalBack(run, phase: "after-public-pop", router: router, oldBar: tabBar, window: window, mode: mode, control: control)
                }
                try rootRecordFinalBack(run, phase: "before-wait", router: router, oldBar: tabBar, window: window, mode: mode, control: control)
                do {
                    try await rootWait { router.depth == 0 && tabBar.selectedItem?.title == "セッション" }
                } catch {
                    try rootRecordFinalBack(run, phase: "wait-timeout", router: router, oldBar: tabBar, window: window, mode: mode, control: control)
                    throw error
                }
                try rootRecordFinalBack(run, phase: "wait-succeeded", router: router, oldBar: tabBar, window: window, mode: mode, control: control)
            }
        }
    }

    @Test func nativeDeleteCancelDoesNotCallAPI() async throws {
        let api = RootDeleteAPI(fails: false)
        var cancelled = 0
        let model = DeleteConfirmationViewModel(sessionID: "delete-cancel", cascadeCount: 0, api: api,
                                                onDeleted: { Issue.record("Cancel executed deletion") })
        let run = try RootInteractionRun(scene: "NativeDeleteCancel")
        try await withRootWindow(DeleteConfirmationView(viewModel: model, onCancel: { cancelled += 1 })) { window in
            let alert = try await rootAlert(in: window)
            #expect(alert.actions.count == 2)
            try await run.waitForCUA(window: window, step: "cancel", instruction: "本物の削除確認alertで『キャンセル』を押す", state: ["apiRemoveCount": await api.removedIDs.count])
            try await rootWait { cancelled == 1 }
            #expect(await api.removedIDs.isEmpty)
            #expect(model.state == .idle)
            try run.record(step: "cancel-result", state: ["apiRemoveCount": await api.removedIDs.count, "cancelCallbacks": cancelled, "state": "idle"])
        }
    }

    @Test func nativeDeleteConfirmPresentsRealFailureAndRetryCallsAPIAgain() async throws {
        let api = RootDeleteAPI(fails: true)
        var cancelled = 0
        let model = DeleteConfirmationViewModel(sessionID: "delete-failure", sessionName: "残るセッション",
                                                cascadeCount: 2, api: api,
                                                onDeleted: { Issue.record("A failing API reported deletion") })
        let run = try RootInteractionRun(scene: "NativeDeleteFailureRetry")
        try await withRootWindow(DeleteConfirmationView(viewModel: model, onCancel: { cancelled += 1 })) { window in
            _ = try await rootAlert(in: window)
            try await rootRecordDeletePhase(run, phase: "before-confirm", model: model, api: api, window: window)
            try await run.waitForCUA(window: window, step: "confirm", instruction: "本物の削除確認alertで『3 件を削除』を押す", state: ["apiRemoveCount": await api.removedIDs.count])
            try await rootRecordDeletePhase(run, phase: "after-confirm-ack", model: model, api: api, window: window)
            let failure = try await rootAlert(in: window, title: "削除できませんでした")
            try await rootRecordDeletePhase(run, phase: "first-failure-presented", model: model, api: api, window: window)
            let presentation = try #require(model.failurePresentation)
            #expect(failure.message == [presentation.cause, presentation.nextStep, presentation.technicalDetail]
                .compactMap { $0 }.joined(separator: "\n"))
            #expect(await api.removedIDs == ["delete-failure"])
            try await rootCapture(window, name: "native-delete-failure")
            #expect(failure.actions.map(\.title).contains("もう一度削除"))
            try await rootRecordDeletePhase(run, phase: "before-retry", model: model, api: api, window: window)
            try await run.waitForCUA(window: window, step: "retry", instruction: "本物の削除失敗alertで『もう一度削除』を押す", state: ["apiRemoveCount": await api.removedIDs.count])
            try await rootRecordDeletePhase(run, phase: "after-retry-ack-before-api-wait", model: model, api: api, window: window)
            do {
                try await rootWait { await api.removedIDs.count == 2 }
            } catch {
                try await rootRecordDeletePhase(run, phase: "retry-api-count-timeout", model: model, api: api, window: window)
                throw error
            }
            try await rootRecordDeletePhase(run, phase: "retry-api-count-reached-before-alert-wait", model: model, api: api, window: window)
            do {
                _ = try await rootAlert(in: window, title: "削除できませんでした")
            } catch {
                try await rootRecordDeletePhase(run, phase: "retry-alert-timeout", model: model, api: api, window: window)
                throw error
            }
            try await rootRecordDeletePhase(run, phase: "retry-failure-presented", model: model, api: api, window: window)
            try await run.waitForCUA(window: window, step: "close", instruction: "再試行後の本物削除失敗alertで『閉じる』を押す", state: ["apiRemoveCount": await api.removedIDs.count])
            try await rootRecordDeletePhase(run, phase: "after-close-ack", model: model, api: api, window: window)
            try await rootWait { cancelled == 1 }
            #expect(await api.removedIDs == ["delete-failure", "delete-failure"])
            try run.record(step: "close-result", state: ["apiRemoveCount": await api.removedIDs.count, "cancelCallbacks": cancelled, "state": String(describing: model.state)])
        }
    }
    @Test func strongPermissionNativeAlertCancelThenConfirmInvokesRealViewModelAPI() async throws {
        let api = RootPermissionAPI()
        let session = Session(id: "root-permission", name: "強権限の確認検査", agent: .claudeCode,
                              status: .idle, subtitle: "", updatedAt: Date())
        let model = SessionDetailViewModel(session: session, api: api)
        await model.loadModelSettings()
        let run = try RootInteractionRun(scene: "StrongPermission")
        try await withRootWindow(NavigationStack {
            SessionDetailView(viewModel: model, scrollToBottomOnAppear: false, onDelete: {})
        }) { window in
            window.rootViewController?.title = run.scene
            try await rootWait { rootLabels(window).contains(where: { $0.contains("権限") || $0.contains("既定") }) }
            try await run.waitForCUA(window: window, step: "cancel", instruction: "権限メニューから『全部許可』を選び、実確認alertで『キャンセル』を押す")
            #expect(await api.updates.isEmpty)
            #expect(model.modelSettings?.selectedPermission == nil)
            try await run.waitForCUA(window: window, step: "confirm", instruction: "権限メニューから『全部許可』を選び、実確認alertで『全部許可 にする』を押す")
            try await rootWait { await api.updates.count == 1 && model.modelSettings?.selectedPermission == "bypassPermissions" }
            #expect(await api.updates == [SessionSettingsUpdate(permission: .some("bypassPermissions"))])
            try await rootCapture(window, name: "strong-permission-confirmed")
        }
    }
}

@MainActor
private func rootRecordFinalBack(_ run: RootInteractionRun, phase: String, router: NavigationRouter,
                                 oldBar: UITabBar, window: UIWindow, mode: String = "native-back",
                                 control: UINavigationController? = nil) throws {
    func safeRect(_ rect: CGRect) -> [String: Any] {
        let finite = rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
        return ["finite": finite, "values": finite ? rootRect(rect) : [], "description": String(describing: rect)]
    }
    func barState(_ bar: UITabBar) -> [String: Any] {
        var state: [String: Any] = [
            "identity": String(describing: ObjectIdentifier(bar)), "isOriginalBar": bar === oldBar,
            "hasWindow": bar.window != nil, "windowIsProbe": bar.window === window,
            "hasSuperview": bar.superview != nil, "superviewType": bar.superview.map { String(reflecting: type(of: $0)) } ?? "",
            "isDescendantOfProbe": bar.isDescendant(of: window), "hidden": bar.isHidden,
            "alpha": String(describing: bar.alpha), "frame": safeRect(bar.frame), "bounds": safeRect(bar.bounds),
            "selectedTitle": bar.selectedItem?.title as Any? ?? NSNull(),
            "itemTitles": (bar.items ?? []).map { $0.title ?? "" },
        ]
        if bar.window === window { state["frameInProbe"] = safeRect(bar.convert(bar.bounds, to: window)) }
        return state
    }
    func allBars(_ view: UIView) -> [UITabBar] {
        ((view as? UITabBar).map { [$0] } ?? []) + view.subviews.flatMap(allBars)
    }
    let fixtureLabels = rootLabels(window).filter { $0.contains("一覧のセッション ") }
    let controllers: [[String: Any]] = rootNativeControlControllers(window).map { navigation in
        let backItem = navigation.viewControllers.first?.navigationItem.backBarButtonItem
        return [
            "identity": String(describing: ObjectIdentifier(navigation)), "type": String(reflecting: type(of: navigation)),
            "isControl": navigation === control, "count": navigation.viewControllers.count,
            "ownedWindow": navigation.viewIfLoaded?.window === window,
            "delegate": navigation.delegate.map { String(reflecting: type(of: $0)) } ?? "nil",
            "navigationBarDelegate": navigation.navigationBar.delegate.map { String(reflecting: type(of: $0)) } ?? "nil",
            "rootBackItemTarget": backItem?.target.map { String(reflecting: type(of: $0)) } ?? "nil",
            "rootBackItemAction": backItem?.action.map { NSStringFromSelector($0) } ?? "nil",
            "stack": navigation.viewControllers.map { child in
                ["identity": String(describing: ObjectIdentifier(child)), "type": String(reflecting: type(of: child)),
                 "title": child.title ?? "", "ownedWindow": child.viewIfLoaded?.window === window,
                 "frame": String(describing: child.viewIfLoaded?.frame)] as [String: Any]
            },
        ]
    }
    try run.record(step: "sessions-compose-back-\(phase)", state: [
        "phase": phase, "mode": mode, "routerDepth": router.depth, "recordedAt": Date().timeIntervalSince1970,
        "navigationControllers": controllers,
        "originalBar": barState(oldBar), "allProbeWindowTabBars": allBars(window).map(barState),
        "probeWindowIsKey": window.isKeyWindow, "probeWindowHidden": window.isHidden,
        "hasFixtureSessionLabel": !fixtureLabels.isEmpty, "fixtureSessionLabels": fixtureLabels,
    ])
}

@MainActor
private func rootHasNewChatScreen(_ window: UIWindow) -> Bool {
    let objects = rootObjects(window).filter { object in
        let frame = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
        return frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0 && window.bounds.intersects(frame)
    }
    let greeting = objects.contains { object in
        (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier == "newChat.greeting"
            && NewChatViewModel.greetings.contains(object.accessibilityLabel ?? "")
    }
    let supportingElement = objects.contains { object in
        let identifier = (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""
        return identifier.hasPrefix("newChat.suggestion.")
            || object.accessibilityLabel == "やりたいことを入力"
            || (object.accessibilityLabel == "画像を添付" && object.accessibilityTraits.contains(.button))
    }
    return greeting && supportingElement
}

/// CUAが取得した仮想AX原文を検査する。UIKit列挙の代用品を人工生成しない。
@MainActor
private func rootValidateNewChatAXProof(_ proof: [String: Any]) throws {
    let raw = try #require(proof["rawAXTree"] as? String)
    let elements = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.first?.isNumber == true }
    func field(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name): ") else { return nil }
        return line[range.upperBound...].components(separatedBy: ", ").first
    }
    let greeting = elements.contains { line in
        field("ID", in: line) == "newChat.greeting"
            && NewChatViewModel.greetings.contains(field("Description", in: line) ?? "")
    }
    let suggestionLabels = NewChatViewModel.suggestions.map { "提案: \($0.title)。入力欄に追記します" }
    let supportingElement = elements.contains { line in
        let description = field("Description", in: line) ?? ""
        let identifier = field("ID", in: line) ?? ""
        let suggestion = identifier.hasPrefix("newChat.suggestion.")
            && Int(identifier.dropFirst("newChat.suggestion.".count)) != nil
            && suggestionLabels.contains(description)
        return suggestion || description == "やりたいことを入力" || description == "画像を添付"
    }
    try #require(greeting, "Fresh external AX must contain the greeting ID and a canonical full greeting on the same real element line")
    try #require(supportingElement, "Fresh external AX must contain a canonical suggestion, input or attachment element")
}

@MainActor
private func rootWaitForNewChat(_ run: RootInteractionRun, phase: String, router: NavigationRouter, window: UIWindow, proof: [String: Any]) async throws {
    func record(_ stage: String) throws {
        let children: [[String: Any]] = rootObjects(window).compactMap { object in
            let identifier = (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""
            let label = object.accessibilityLabel ?? ""
            guard identifier.hasPrefix("newChat.") || label == "やりたいことを入力" || label == "画像を添付" else { return nil }
            let frame = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
            let finite = frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
            return ["identifier": identifier, "label": label, "finiteFrame": finite,
                    "frame": finite ? rootRect(frame) : [], "intersectsWindow": finite && window.bounds.intersects(frame)]
        }
        try run.record(step: "\(phase)-\(stage)", state: [
            "routerDepth": router.depth, "UIKitChildDiagnostics": children, "UIKitDiagnosticHasNewChatScreen": rootHasNewChatScreen(window),
            "windowIsKey": window.isKeyWindow, "windowHidden": window.isHidden, "windowLevel": Double(window.windowLevel.rawValue),
            "sceneWindows": (window.windowScene?.windows ?? []).map {
                ["isProbeWindow": $0 === window, "isKey": $0.isKeyWindow, "hidden": $0.isHidden,
                 "level": Double($0.windowLevel.rawValue), "frame": rootRect($0.frame)] as [String: Any]
            },
        ])
    }
    try record("ack-before-depth-wait")
    do { try await rootWait { router.depth == 1 } }
    catch { try record("depth-timeout"); throw error }
    try record("depth-reached-before-external-proof")
    do { try rootValidateNewChatAXProof(proof) }
    catch { try record("external-proof-failed"); throw error }
    try record("external-proof-validated")
}

@MainActor
private func rootTabController(_ controller: UIViewController, owning tabBar: UITabBar) -> UITabBarController? {
    if let tabs = controller as? UITabBarController, tabs.tabBar === tabBar { return tabs }
    if let presented = controller.presentedViewController, let found = rootTabController(presented, owning: tabBar) { return found }
    for child in controller.children {
        if let found = rootTabController(child, owning: tabBar) { return found }
    }
    return nil
}

@MainActor
private func rootRecordDeletePhase(_ run: RootInteractionRun, phase: String, model: DeleteConfirmationViewModel,
                                   api: RootDeleteAPI, window: UIWindow) async throws {
    var controllers: [[String: Any]] = []
    var visited: Set<ObjectIdentifier> = []
    func inspect(_ controller: UIViewController, path: String) {
        guard visited.insert(ObjectIdentifier(controller)).inserted else { return }
        var state: [String: Any] = [
            "path": path, "type": String(reflecting: type(of: controller)), "title": controller.title ?? "",
            "isBeingPresented": controller.isBeingPresented, "isBeingDismissed": controller.isBeingDismissed,
            "hasPresentingController": controller.presentingViewController != nil,
            "viewInWindow": controller.viewIfLoaded?.window != nil,
            "hasTransitionCoordinator": controller.transitionCoordinator != nil,
        ]
        if let alert = controller as? UIAlertController {
            state["alertTitle"] = alert.title ?? ""
            state["alertMessage"] = alert.message ?? ""
            state["actions"] = alert.actions.map { ["title": $0.title ?? "", "style": $0.style.rawValue] as [String: Any] }
        }
        controllers.append(state)
        if let presented = controller.presentedViewController { inspect(presented, path: "\(path).presented") }
        for (index, child) in controller.children.enumerated() { inspect(child, path: "\(path).child\(index)") }
    }
    if let controller = window.rootViewController { inspect(controller, path: "root") }
    try run.record(step: phase, state: [
        "phase": phase, "recordedAt": Date().timeIntervalSince1970, "apiRemoveCount": await api.removedIDs.count,
        "modelState": String(describing: model.state), "isDeleting": model.isDeleting,
        "failureTitle": model.failurePresentation?.title ?? "", "controllers": controllers,
    ])
}

private actor RootPermissionAPI: PhloxAPI, SessionModelSelecting {
    private var permission: String?
    private(set) var updates: [SessionSettingsUpdate] = []
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.unsupported }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func remove(sessionID: String) async throws {}
    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        SessionModelSettings(selectedModel: nil, availableModels: [], selectedPermission: permission,
                             availablePermissions: [AgentSettingOption(value: "bypassPermissions", displayName: "全部許可")])
    }
    func setModel(sessionID: String, model: String) async throws { throw PhloxError.unsupported }
    func updateSessionSettings(sessionID: String, update: SessionSettingsUpdate) async throws {
        updates.append(update)
        if let selected = update.permission { permission = selected }
    }
}

@MainActor
private struct RootInteractionRun {
    let scene: String
    let directory: URL
    init(scene: String) throws {
        self.scene = scene
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["PHLOX_REMAINING_OUTPUT"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_PHLOX_REMAINING_OUTPUT"]
            ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining").path
        directory = URL(fileURLWithPath: path).appendingPathComponent("\(scene)-ios\(UIDevice.current.systemVersion)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func record(step: String, state: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(step)-state.json"))
    }

    @discardableResult
    func waitForCUA(window: UIWindow, step: String, instruction: String, state: [String: Any] = [:]) async throws -> [String: Any] {
        let nonce = UUID().uuidString
        let ack = directory.appendingPathComponent("\(step)-\(nonce)-ack.json")
        let requestedAt = Date().timeIntervalSince1970
        let pid = ProcessInfo.processInfo.processIdentifier
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let windowTitle = ProcessInfo.processInfo.environment["PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE"]
            ?? "unknown"
        let screenshot = directory.appendingPathComponent("\(step)-window.png")
        let capture = try await rootFreshPNG(window, diagnosticDirectory: directory, diagnosticName: step)
        try capture.png.write(to: screenshot)
        let ready: [String: Any] = [
            "scene": scene, "step": step, "phase": "awaitingCUA", "nonce": nonce,
            "pid": pid, "udid": udid, "windowTitle": windowTitle, "controllerTitle": scene, "requestedAt": requestedAt,
            "ackFile": ack.path, "instruction": instruction, "labels": rootLabels(window),
            "state": state, "screenshotFile": screenshot.path,
            "captureFrames": capture.frames, "capturePhase": "after-display-frames",
            "executable": CommandLine.arguments.first ?? "unknown", "session": "ios_root_transitions",
        ]
        let readyURL = directory.appendingPathComponent("\(step)-ready.json")
        try JSONSerialization.data(withJSONObject: ready, options: [.prettyPrinted, .sortedKeys]).write(to: readyURL)
        print("root transition awaitingCUA: \(readyURL.path)")
        let deadline = ContinuousClock.now + .seconds(180)
        while !FileManager.default.fileExists(atPath: ack.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(FileManager.default.fileExists(atPath: ack.path), "CUA operation acknowledgement was not provided")
        let reply = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any])
        try #require(reply["nonce"] as? String == nonce && reply["scene"] as? String == scene && reply["step"] as? String == step)
        try #require((reply["pid"] as? NSNumber)?.int32Value == pid && reply["udid"] as? String == udid)
        try #require(reply["phase"] as? String == "reviewed" && reply["confirmed"] as? Bool == true)
        let capturedAt = try #require(reply["capturedAt"] as? Double)
        try #require(capturedAt >= requestedAt && capturedAt <= Date().timeIntervalSince1970 + 5)
        try JSONSerialization.data(withJSONObject: reply, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(step)-reviewed.json"))
        if step == "settings-compose" || step == "sessions-compose" || step == "legacy-header-compose" {
            try #require(windowTitle != "unknown" && !windowTitle.isEmpty)
            try #require(reply["windowTitle"] as? String == windowTitle)
            try #require(Date().timeIntervalSince1970 - capturedAt <= 120)
            let raw = try #require(reply["rawAXTree"] as? String)
            try #require(raw.components(separatedBy: .newlines).contains("Window: \"\(windowTitle)\", App: Simulator."))
        }
        return reply
    }
}

@MainActor
private func rootScrollState(_ scroll: UIScrollView) -> [String: Any] {
    ["offsetY": Double(scroll.contentOffset.y), "contentHeight": Double(scroll.contentSize.height),
     "viewportHeight": Double(scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom),
     "isScrollEnabled": scroll.isScrollEnabled]
}

private func rootRect(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
}

@MainActor
private func rootEnvironment(repository: RootRepository, sessions: [Session] = [],
                             authenticator: any Authenticating = StubAuthenticator(allows: false)) -> AppEnvironment {
    AppEnvironment(tokenStore: InMemoryTokenStore(), authenticator: authenticator,
                   apiClient: StubPhloxAPI(sessions: sessions), reachability: StubReachability(.online),
                   sessionRepository: repository, auditLog: InMemoryAuditLog())
}

private actor RootControlledAuthenticator: Authenticating {
    private let decisions: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private(set) var callCount = 0
    private(set) var isWaiting = false

    init() {
        let pair = AsyncStream<Bool>.makeStream()
        decisions = pair.stream
        continuation = pair.continuation
    }

    func authenticate(reason: String) async throws -> Bool {
        callCount += 1
        isWaiting = true
        defer { isWaiting = false }
        for await decision in decisions { return decision }
        return false
    }

    func resolve(_ decision: Bool) {
        continuation.yield(decision)
        continuation.finish()
    }
    func finish() { continuation.finish() }
}

private actor RootRepository: SessionRepositoryProtocol {
    private var current: SessionsState
    private var continuations: [AsyncStream<SessionsState>.Continuation] = []

    init(initial: SessionsState) {
        current = initial
    }

    func matchesLoaded(_ sessions: [Session]) -> Bool {
        guard case .loaded(let values) = current else { return false }
        return values == sessions
    }

    nonisolated func sessionStream(interval: Duration) -> AsyncStream<SessionsState> {
        AsyncStream { continuation in Task { await self.register(continuation) } }
    }
    private func register(_ continuation: AsyncStream<SessionsState>.Continuation) {
        continuations.append(continuation)
        continuation.yield(current)
    }
    func emit(_ state: SessionsState) {
        current = state
        for continuation in continuations { continuation.yield(state) }
    }
    func refresh() async throws {}
    func finish() {
        for continuation in continuations { continuation.finish() }
        continuations.removeAll()
    }
}

private actor RootDeleteAPI: PhloxAPI {
    let fails: Bool
    private(set) var removedIDs: [String] = []
    init(fails: Bool) { self.fails = fails }
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.unsupported }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func remove(sessionID: String) async throws {
        removedIDs.append(sessionID)
        if fails { throw PhloxError.server(status: 503, message: "root-delete-unavailable") }
    }
}

@MainActor
private func rootObjects(_ root: NSObject) -> [NSObject] {
    var result: [NSObject] = []
    var visited: Set<ObjectIdentifier> = []
    func visit(_ object: NSObject) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        result.append(object)
        for child in object.accessibilityElements ?? [] {
            if let child = child as? NSObject { visit(child) }
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) }
            }
        }
        if let view = object as? UIView {
            for child in view.subviews where !child.isHidden && child.alpha > 0 { visit(child) }
        }
    }
    visit(root)
    return result
}

@MainActor
private func rootLabels(_ window: UIWindow) -> [String] {
    rootObjects(window).compactMap { $0.accessibilityLabel }
}

@MainActor
private func rootActivate(label: String, in view: UIView) throws {
    let candidates = rootObjects(view).filter { $0.accessibilityLabel == label }
    for object in candidates where object.accessibilityTraits.contains(.button) {
        if object.accessibilityActivate() { return }
    }
    for case let button as UIButton in rootObjects(view) where button.currentTitle == label {
        button.sendActions(for: .touchUpInside)
        return
    }
    throw RootTransitionError.publicActionUnavailable(label)
}

@MainActor
private func rootWait(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    repeat {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(30))
    } while ContinuousClock.now < deadline
    throw RootTransitionError.timeout
}

@MainActor
private func rootAlert(in window: UIWindow, title: String? = nil) async throws -> UIAlertController {
    func find(_ controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController, title == nil || alert.title == title { return alert }
        if let presented = controller.presentedViewController, let alert = find(presented) { return alert }
        return controller.children.lazy.compactMap(find).first
    }
    var result: UIAlertController?
    try await rootWait {
        result = window.rootViewController.flatMap(find)
        return result?.view.window != nil && result?.transitionCoordinator == nil
    }
    return try #require(result)
}

@MainActor
private func withRootWindow<Content: View>(_ content: Content, touchTrace: RootTouchDeliveryTrace? = nil,
                                         operation: (UIWindow) async throws -> Void) async throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive })
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window: UIWindow
    if let touchTrace {
        let measured = RootTouchDeliveryWindow(windowScene: scene)
        measured.trace = touchTrace
        window = measured
    } else {
        window = UIWindow(windowScene: scene)
    }
    window.frame = scene.screen.bounds
    let probe = RootScenePhaseRecorder(window: window)
    let probeRun = try RootInteractionRun(scene: "RootHostScenePhase")
    let bridge = RootScenePhaseBridge(scene: scene)
    let host = UIHostingController(rootView: RootScenePhaseHost(content: content, bridge: bridge, recorder: probe)
        .environment(\.locale, Locale(identifier: "ja_JP")))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
        bridge.stop()
        host.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKey()
    }
    try await rootWait {
        host.view.window != nil && scene.activationState == .foregroundActive
            && probe.phase == bridge.phase && bridge.phase == RootScenePhaseBridge.phase(for: scene.activationState)
    }
    probe.record("before-operation")
    try probeRun.record(step: "before-operation", state: ["events": probe.events])
    do {
        try await operation(window)
    } catch {
        probe.record("operation-failed")
        try probeRun.record(step: "operation-failed", state: ["events": probe.events])
        throw error
    }
    probe.record("after-operation")
    try probeRun.record(step: "after-operation", state: ["events": probe.events])
}

@MainActor
private final class RootTouchDeliveryWindow: UIWindow {
    var trace: RootTouchDeliveryTrace?
    override func sendEvent(_ event: UIEvent) {
        trace?.record(event, window: self)
        super.sendEvent(event)
    }
}

@MainActor
private final class RootTouchDeliveryTrace {
    private var events: [[String: Any]] = []
    private var touchSampleCount = 0

    func record(_ event: UIEvent, window: UIWindow) {
        guard event.type == .touches else { return }
        let touches: [[String: Any]] = (event.allTouches ?? []).map { touch in
            let point = touch.location(in: window)
            let screenPoint = window.convert(point, to: window.screen.coordinateSpace)
            return ["phase": String(describing: touch.phase), "phaseRaw": touch.phase.rawValue,
                    "timestamp": touch.timestamp, "windowIsProbe": touch.window === window,
                    "windowPoint": String(describing: point), "screenPoint": String(describing: screenPoint)]
        }
        touchSampleCount += touches.count
        let entry: [String: Any] = ["type": event.type.rawValue, "timestamp": event.timestamp, "touches": touches]
        events.append(entry)
        print("RootFingerPanTouchDelivery: \(entry)")
    }

    func state(window: UIWindow) -> [String: Any] {
        ["eventCount": events.count, "touchSampleCount": touchSampleCount, "events": events,
         "windowBounds": String(describing: window.bounds), "windowFrame": String(describing: window.frame),
         "screenBounds": String(describing: window.screen.bounds), "nativeBounds": String(describing: window.screen.nativeBounds),
         "screenScale": Double(window.screen.scale), "nativeScale": Double(window.screen.nativeScale),
         "interpretation": "Window points and screen coordinates are observed; CUA screenshot pixel-to-point mapping is not assumed"]
    }
}

@MainActor
private final class RootScenePhaseRecorder {
    private weak var window: UIWindow?
    private(set) var phase: ScenePhase?
    private(set) var events: [[String: Any]] = []

    init(window: UIWindow) { self.window = window }
    func record(_ event: String, phase: ScenePhase? = nil) {
        if let phase { self.phase = phase }
        let entry: [String: Any] = [
            "event": event, "capturedAt": Date().timeIntervalSince1970,
            "swiftUIScenePhase": self.phase.map { String(describing: $0) } ?? "unobserved",
            "uiWindowSceneActivationState": window?.windowScene.map { String(describing: $0.activationState) } ?? "unavailable",
            "windowIsKey": window?.isKeyWindow ?? false,
            "windowHidden": window?.isHidden ?? true,
        ]
        events.append(entry)
        print("RootHostScenePhase: \(entry)")
    }
}

/// 手動UIHostingControllerにはSwiftUI AppのScene環境がないため、実sceneの通知を橋渡しする。
@MainActor
private final class RootScenePhaseBridge: NSObject, ObservableObject {
    private let scene: UIWindowScene
    @Published private(set) var phase: ScenePhase

    init(scene: UIWindowScene) {
        self.scene = scene
        phase = Self.phase(for: scene.activationState)
        super.init()
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: name, object: scene)
        }
    }
    static func phase(for state: UIScene.ActivationState) -> ScenePhase {
        switch state {
        case .foregroundActive: .active
        case .foregroundInactive: .inactive
        case .background, .unattached: .background
        @unknown default: .background
        }
    }
    func stop() { NotificationCenter.default.removeObserver(self) }
    @objc private func update(_ notification: Notification) {
        guard let source = notification.object as? UIScene, source === scene else { return }
        switch notification.name {
        case UIScene.didActivateNotification: phase = .active
        case UIScene.willDeactivateNotification, UIScene.willEnterForegroundNotification: phase = .inactive
        case UIScene.didEnterBackgroundNotification: phase = .background
        default: break
        }
    }
}

@MainActor
private struct RootScenePhaseHost<Content: View>: View {
    let content: Content
    @ObservedObject var bridge: RootScenePhaseBridge
    let recorder: RootScenePhaseRecorder
    var body: some View {
        content
            .overlay { RootScenePhaseProbe(recorder: recorder).allowsHitTesting(false).accessibilityHidden(true) }
            .environment(\.scenePhase, bridge.phase)
    }
}

@MainActor
private struct RootScenePhaseProbe: View {
    @Environment(\.scenePhase) private var phase
    let recorder: RootScenePhaseRecorder
    var body: some View {
        Color.clear
            .onAppear { recorder.record("swiftui-onAppear", phase: phase) }
            .onChange(of: phase) { _, value in recorder.record("swiftui-onChange", phase: value) }
    }
}

private enum RootTransitionError: Error {
    case timeout
    case publicActionUnavailable(String)
}

@MainActor
@discardableResult
private func rootCapture(_ window: UIWindow, name: String, differentFrom previous: Data? = nil,
                         requiredTextGroups: [[String]] = [], forbiddenText: [String] = []) async throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let path = ProcessInfo.processInfo.environment["PHLOX_REMAINING_OUTPUT"]
        ?? ProcessInfo.processInfo.environment["TEST_RUNNER_PHLOX_REMAINING_OUTPUT"]
        ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining").path
    let directory = URL(fileURLWithPath: path).appendingPathComponent("RootTransitions-ios\(UIDevice.current.systemVersion)-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let labelsBeforeFrames = rootLabels(window)
    let deadline = ContinuousClock.now + .seconds(5)
    var capture = try await rootFreshPNG(window, diagnosticDirectory: directory, diagnosticName: "initial")
    var recognized = try rootRecognizedText(capture.png)
    func matchesExpectedImage() -> Bool {
        let normalized = rootNormalizedOCR(recognized.joined(separator: "\n"))
        return requiredTextGroups.allSatisfy { group in group.contains { normalized.contains(rootNormalizedOCR($0)) } }
            && !forbiddenText.contains { normalized.contains(rootNormalizedOCR($0)) }
    }
    while (capture.png == previous || !matchesExpectedImage()), ContinuousClock.now < deadline {
        capture = try await rootFreshPNG(window, diagnosticDirectory: directory, diagnosticName: "refresh")
        recognized = try rootRecognizedText(capture.png)
    }
    if let previous { try #require(capture.png != previous, "A changed root state must produce a fresh, different image") }
    let metadata: [String: Any] = [
        "purpose": "RootTransitionTests native window evidence", "session": "ios_root_transitions",
        "pid": ProcessInfo.processInfo.processIdentifier,
        "executable": CommandLine.arguments.first ?? "unknown", "output": directory.path,
        "labelsBeforeFrames": labelsBeforeFrames, "labels": rootLabels(window),
        "capturePhase": "after-display-frames", "captureFrames": capture.frames,
        "requiredDifferentFromPreviousState": previous != nil,
        "recognizedText": recognized, "requiredTextGroups": requiredTextGroups, "forbiddenText": forbiddenText,
    ]
    try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("record.json"))
    try capture.png.write(to: directory.appendingPathComponent("window.png"))
    try #require(matchesExpectedImage(), "The saved PNG must show the required state-specific text and exclude the previous overlay: \(recognized)")
    print("root transition evidence: \(directory.path)")
    return capture.png
}

private func rootNormalizedOCR(_ text: String) -> String {
    String(text.filter { !$0.isWhitespace }).replacingOccurrences(of: "...", with: "…")
}

@MainActor
private func rootRecognizedText(_ png: Data) throws -> [String] {
    let image = try #require(UIImage(data: png)?.cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

/// 実display callbackと局所layout/commitを待つ。常駐演出の停止は要求しない。
@MainActor
private func rootFreshPNG(_ window: UIWindow, diagnosticDirectory: URL, diagnosticName: String) async throws -> (png: Data, frames: [Double]) {
    let observer = RootDisplayFrames()
    observer.start()
    defer { observer.stop() }
    window.setNeedsLayout()
    window.layoutIfNeeded()
    CATransaction.flush()
    func record(_ phase: String) throws {
        let metadata: [String: Any] = [
            "phase": phase, "displayTimestamps": observer.timestamps,
            "layers": rootLayerAnimations(window.layer), "labels": rootLabels(window),
            "recordedAt": Date().timeIntervalSince1970,
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: diagnosticDirectory.appendingPathComponent("\(diagnosticName)-\(phase).json"))
    }
    try record("frame-wait-before")
    do {
        try await rootWait { observer.timestamps.count >= 3 }
    } catch {
        try record("frame-wait-timeout")
        throw error
    }
    try record("frames-observed")
    window.layoutIfNeeded()
    window.layer.displayIfNeeded()
    CATransaction.flush()
    let committedFrames = observer.timestamps.count
    do {
        try await rootWait { observer.timestamps.count > committedFrames }
    } catch {
        try record("commit-frame-timeout")
        throw error
    }
    try record("commit-frame-observed")
    var drawn = false
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try #require(drawn)
    return (try #require(image.pngData()), observer.timestamps)
}

@MainActor
private func rootLayerAnimations(_ layer: CALayer, path: String = "window") -> [[String: Any]] {
    let animations: [[String: Any]] = (layer.animationKeys() ?? []).compactMap { key in
        guard let animation = layer.animation(forKey: key) else { return nil }
        return ["key": key, "beginTime": String(animation.beginTime), "duration": String(animation.duration),
                "repeatCount": String(animation.repeatCount), "repeatDuration": String(animation.repeatDuration),
                "speed": String(animation.speed), "timeOffset": String(animation.timeOffset),
                "isRemovedOnCompletion": animation.isRemovedOnCompletion, "fillMode": animation.fillMode.rawValue]
    }
    var result: [[String: Any]] = animations.isEmpty ? [] : [[
        "layerPath": path, "layerType": String(reflecting: type(of: layer)), "animations": animations,
        "layerLocalTime": String(layer.convertTime(CACurrentMediaTime(), from: nil)),
    ]]
    for (index, child) in (layer.sublayers ?? []).enumerated() {
        result += rootLayerAnimations(child, path: "\(path).\(index)")
    }
    return result
}

@MainActor
private final class RootDisplayFrames: NSObject {
    private var link: CADisplayLink?
    private(set) var timestamps: [Double] = []
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func frame(_ link: CADisplayLink) { timestamps.append(link.timestamp) }
}
