import SwiftUI
import UIKit
import Testing
@testable import DesignSystemIOS

/// 左上のホーム印を付けた NavigationStack の UIKit 状態を読む。
/// ボタン押下・タッチ・ジェスチャイベントは発生させない。
@MainActor
struct NavigationBackSwipeProbeTests {
    @Test func homeBackIndicatorPreservesInteractivePopAcrossPopAndPush() async throws {
        let previousAnimationState = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(previousAnimationState) }

        let probe = try HomeBackProbeWindow()
        defer { probe.close() }

        _ = try await probe.waitForStackDepth(1)
        probe.state.path = ["detail"]
        var navigationController = try await probe.waitForStackDepth(2)
        try assertHomeBackContract(navigationController)

        probe.state.path.removeLast()
        _ = try await probe.waitForStackDepth(1)
        probe.state.path.append("detail")
        navigationController = try await probe.waitForStackDepth(2)
        try assertHomeBackContract(navigationController)
    }

    private func assertHomeBackContract(_ navigationController: UINavigationController) throws {
        let gesture = try #require(navigationController.interactivePopGestureRecognizer)
        #expect(gesture.isEnabled)
        #expect(gesture.delegate?.gestureRecognizerShouldBegin?(gesture) == true)

        let house = try #require(UIImage(systemName: "house"))
        let bar = navigationController.navigationBar
        let appearances = [
            bar.standardAppearance,
            try #require(bar.scrollEdgeAppearance),
            try #require(bar.compactAppearance),
            try #require(bar.compactScrollEdgeAppearance),
        ]
        for appearance in appearances {
            let image = appearance.backIndicatorImage
            #expect(image.pngData() == house.pngData())
        }

        let rootItem = try #require(navigationController.viewControllers.first?.navigationItem)
        #expect(rootItem.backBarButtonItem?.accessibilityLabel == "ホーム（セッション一覧に戻る）")
    }
}

@MainActor
private final class HomeBackProbeState: ObservableObject {
    @Published var path: [String] = []
}

private struct HomeBackProbeRoot: View {
    @ObservedObject var state: HomeBackProbeState

    var body: some View {
        NavigationStack(path: $state.path) {
            Text("セッション一覧")
                .navigationTitle("セッション")
                .navigationBarTitleDisplayMode(.inline)
                .navigationStackHomeBackButton()
                .navigationDestination(for: String.self) { _ in
                    Text("セッション詳細")
                        .navigationTitle("詳細")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarRole(.editor)
                }
        }
    }
}

@MainActor
private final class HomeBackProbeWindow {
    let state = HomeBackProbeState()
    let window: UIWindow
    private let host: UIHostingController<HomeBackProbeRoot>

    init() throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        host = UIHostingController(rootView: HomeBackProbeRoot(state: state))
        window.rootViewController = host
        window.isHidden = false
    }

    func waitForStackDepth(_ depth: Int) async throws -> UINavigationController {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            if let navigationController = findNavigationController(in: host),
               navigationController.viewControllers.count == depth,
               navigationController.transitionCoordinator == nil {
                try await Task.sleep(for: .milliseconds(50))
                return navigationController
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw ProbeError.navigationStackDidNotSettle(depth)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func findNavigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigationController = controller as? UINavigationController {
            return navigationController
        }
        for child in controller.children {
            if let navigationController = findNavigationController(in: child) {
                return navigationController
            }
        }
        return nil
    }

    private enum ProbeError: Error {
        case navigationStackDidNotSettle(Int)
    }
}
