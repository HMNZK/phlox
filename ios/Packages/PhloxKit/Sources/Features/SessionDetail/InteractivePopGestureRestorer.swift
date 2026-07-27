import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// ナビゲーションバーを隠した画面（セッション詳細）で、iOS 標準の端スワイプ pop を復活させる
/// ための判定層。UIKit へ依存しないので macOS ホストの `swift test` で検証できる。
///
/// 公開面は PM が凍結した契約面（task-1 の入出力契約）。振る舞いの実装と UIKit への接続は task-1 が行う。
/// 契約の正本: Tests/FeaturesTests/AcceptanceSessionViewUXTests.swift
public protocol InteractivePopGestureHost: AnyObject {
    /// ナビゲーションスタックに積まれている画面数（1 は根の画面＝戻れない）。
    var navigationStackDepth: Int { get }
    /// 端スワイプ pop ジェスチャが有効か。
    var isInteractivePopGestureEnabled: Bool { get set }
}

public enum InteractivePopGestureRestorer {
    /// 端スワイプ pop を有効に戻す。
    ///
    /// - Returns: 有効化した（または既に有効だった）なら true。根の画面では触らず false。
    @discardableResult
    public static func restore(on host: some InteractivePopGestureHost) -> Bool {
        guard host.navigationStackDepth >= 2 else { return false }
        host.isInteractivePopGestureEnabled = true
        return true
    }
}

/// 詳細画面の表示・再表示ごとに UIKit の端スワイプを復元する接続層。
/// 本文へ DragGesture を付けず、縦スクロールやキーボード操作と競合させない。
struct InteractivePopGestureRestorerModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(
            InteractivePopGestureRestorationView()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
        #else
        content
        #endif
    }
}

#if os(iOS)
private struct InteractivePopGestureRestorationView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RestorationViewController {
        RestorationViewController()
    }

    func updateUIViewController(_ uiViewController: RestorationViewController, context: Context) {
        uiViewController.restoreInteractivePopGesture()
    }
}

private final class RestorationViewController: UIViewController {
    /// `UIGestureRecognizer` は delegate を弱参照するため、この view controller が強参照する。
    private var interactivePopGestureDelegate: NavigationControllerInteractivePopGestureDelegate?
    private var originalInteractivePopGestureDelegate: UIGestureRecognizerDelegate?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        restoreInteractivePopGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreInteractivePopGesture()
        DispatchQueue.main.async { [weak self] in
            self?.restoreInteractivePopGesture()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restoreInteractivePopGesture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreOriginalInteractivePopGestureDelegate()
    }

    func restoreInteractivePopGesture() {
        guard let navigationController else { return }
        guard InteractivePopGestureRestorer.restore(
            on: NavigationControllerInteractivePopGestureHost(navigationController: navigationController)
        ), let gestureRecognizer = navigationController.interactivePopGestureRecognizer else {
            return
        }

        if interactivePopGestureDelegate == nil {
            originalInteractivePopGestureDelegate = gestureRecognizer.delegate
            interactivePopGestureDelegate = NavigationControllerInteractivePopGestureDelegate(
                navigationController: navigationController
            )
        }

        if let interactivePopGestureDelegate {
            gestureRecognizer.delegate = interactivePopGestureDelegate
        }
    }

    private func restoreOriginalInteractivePopGestureDelegate() {
        guard let navigationController,
              let gestureRecognizer = navigationController.interactivePopGestureRecognizer,
              let interactivePopGestureDelegate
        else {
            return
        }

        if gestureRecognizer.delegate === interactivePopGestureDelegate {
            gestureRecognizer.delegate = originalInteractivePopGestureDelegate
        }
        self.interactivePopGestureDelegate = nil
        originalInteractivePopGestureDelegate = nil
    }
}

/// ナビゲーションバーを隠した詳細画面でのみ、UIKit の既定 delegate に代わって開始可否を守る。
/// 本文の横スクロールと競合しないよう、同時認識は許可しない。
private final class NavigationControllerInteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.count >= 2
            && navigationController.transitionCoordinator == nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class NavigationControllerInteractivePopGestureHost: InteractivePopGestureHost {
    private weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    var navigationStackDepth: Int {
        navigationController?.viewControllers.count ?? 0
    }

    var isInteractivePopGestureEnabled: Bool {
        get { navigationController?.interactivePopGestureRecognizer?.isEnabled ?? false }
        set { navigationController?.interactivePopGestureRecognizer?.isEnabled = newValue }
    }
}
#endif
