import Features
import PhloxCore

/// シミュレーター見本・描画テスト用の初期ルート・ナビゲーションを適用する。
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
        case .sessionShellDetail:
            router.push(.sessionDetail(id: "attention-approval"))
        case .deleteConfirmation:
            router.push(.sessionDetail(id: "sess-rose"))
            router.present(.deleteConfirmation(id: "sess-rose", cascadeCount: 3))
        case .connectionSettings, .sessionList, .launchGate, .unreachable, .empty,
             .sessionShell, .sessionShellNoAttention, .sessionShellScrolled, .sessionShellOffline,
             .list, .listMulti, .listCollapsed, .listChildrenExpanded, .listAllAttention,
             .listLoading, .listJudging, .listEmpty, .listOffNet, .listOffHost, .listOffUnknown,
             .listError, .listError401, .listSE, .listDT:
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
        case .sessionShellOffline:
            return AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .unreachableHost)
        default:
            return AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        }
    }
}
