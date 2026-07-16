import Features
import PhloxCore

/// UI テスト / スクリーンショット用の初期ルート・ナビゲーションを適用する。
@MainActor
enum UITestingNavigator {
    static func initialModel() -> AppModel {
        guard UITestingSupport.isEnabled else { return AppModel() }

        if let screen = UITestingSupport.screen {
            return model(for: screen)
        }

        switch UITestingSupport.scenario {
        case .launchGate:
            return AppModel(authState: .locked, hasConnectionConfig: true, reachability: .online)
        case .goldenPath, .empty:
            return AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        }
    }

    static func initialRouter() -> NavigationRouter {
        var router = NavigationRouter()
        guard UITestingSupport.isEnabled, UITestingSupport.screen != nil else { return router }
        applyNavigation(router: &router, listVM: nil)
        return router
    }

    static func applyNavigation(router: inout NavigationRouter, listVM: SessionListViewModel?) {
        guard UITestingSupport.isEnabled, let screen = UITestingSupport.screen else { return }

        switch screen {
        case .sessionDetail:
            router.push(.sessionDetail(id: "sess-rose"))
        case .deleteConfirmation:
            router.push(.sessionDetail(id: "sess-rose"))
            router.present(.deleteConfirmation(id: "sess-rose", cascadeCount: 3))
        case .spawn, .spawnError:
            break // spawn 画面は wave-4 で廃止（遷移なし。Screen ケースは screenshot 用に残置）
        case .chatAnswer:
            router.push(.chatAnswer(sessionID: "sess-tulip"))
        case .codexApproval:
            router.push(.sessionDetail(id: "sess-codex"))
        case .connectionSettings, .sessionList, .launchGate, .unreachable, .empty:
            break
        }
    }

    private static func model(for screen: UITestingSupport.Screen) -> AppModel {
        switch screen {
        case .launchGate:
            return AppModel(authState: .locked, hasConnectionConfig: true, reachability: .online)
        case .connectionSettings:
            return AppModel(authState: .unlocked, hasConnectionConfig: false, reachability: .online)
        case .unreachable:
            return AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .unreachableHost)
        default:
            return AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        }
    }
}
