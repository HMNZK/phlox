#if canImport(UIKit)
import SwiftUI
import UIKit

/// NavigationStack が所有するナビゲーションバーだけに家の戻る印を適用する。
public struct NavigationStackHomeBackButton: ViewModifier {
    public func body(content: Content) -> some View {
        content.background {
            NavigationControllerResolver()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    /// この NavigationStack のシステム戻るボタンを家の印にする。ジェスチャとデリゲートは変更しない。
    func navigationStackHomeBackButton() -> some View {
        modifier(NavigationStackHomeBackButton())
    }
}

@MainActor
enum NavigationStackHomeBackButtonInstaller {
    private static let house = UIImage(systemName: "house")?.withRenderingMode(.alwaysTemplate)
    private static let accessibilityLabel = "ホーム（セッション一覧に戻る）"

    /// SwiftUI の更新のたびに呼ばれるので、掛け済みなら何もしない。
    static func apply(to navigationController: UINavigationController) {
        guard let house else { return }
        let bar = navigationController.navigationBar
        let tint = UIColor(DSNavigationChrome.accentTint)
        if bar.tintColor?.isEqual(tint) != true {
            bar.tintColor = tint
        }

        if bar.standardAppearance.backIndicatorImage !== house {
            bar.standardAppearance = appearance(bar.standardAppearance, house: house)
            bar.scrollEdgeAppearance = appearance(bar.scrollEdgeAppearance ?? bar.standardAppearance, house: house)
            bar.compactAppearance = appearance(bar.compactAppearance ?? bar.standardAppearance, house: house)
            bar.compactScrollEdgeAppearance = appearance(
                bar.compactScrollEdgeAppearance ?? bar.standardAppearance,
                house: house
            )
        }

        guard let root = navigationController.viewControllers.first,
              root.navigationItem.backBarButtonItem?.accessibilityLabel != accessibilityLabel
        else { return }
        let backItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        backItem.accessibilityLabel = accessibilityLabel
        root.navigationItem.backBarButtonItem = backItem
    }

    private static func appearance(_ source: UINavigationBarAppearance, house: UIImage) -> UINavigationBarAppearance {
        let copy = source.copy()
        copy.setBackIndicatorImage(house, transitionMaskImage: house)
        return copy
    }
}

private struct NavigationControllerResolver: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ResolverController {
        ResolverController()
    }

    func updateUIViewController(_ controller: ResolverController, context: Context) {
        controller.installIfPossible()
    }

    @MainActor
    final class ResolverController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            installIfPossible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfPossible()
        }

        func installIfPossible() {
            if let navigationController {
                NavigationStackHomeBackButtonInstaller.apply(to: navigationController)
                return
            }

            guard let root = view.window?.rootViewController,
                  let navigationController = Self.findNavigationController(containing: view, in: root)
            else { return }
            NavigationStackHomeBackButtonInstaller.apply(to: navigationController)
        }

        private static func findNavigationController(
            containing view: UIView,
            in controller: UIViewController
        ) -> UINavigationController? {
            if let navigationController = controller as? UINavigationController,
               view.isDescendant(of: navigationController.view) {
                return navigationController
            }
            for child in controller.children {
                if let navigationController = findNavigationController(containing: view, in: child) {
                    return navigationController
                }
            }
            return nil
        }
    }
}
#else
import SwiftUI

public struct NavigationStackHomeBackButton: ViewModifier {
    public func body(content: Content) -> some View { content }
}

public extension View {
    func navigationStackHomeBackButton() -> some View {
        modifier(NavigationStackHomeBackButton())
    }
}
#endif
