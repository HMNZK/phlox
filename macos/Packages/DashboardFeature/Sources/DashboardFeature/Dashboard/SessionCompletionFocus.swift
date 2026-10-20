import Foundation
import SessionFeature
import SwiftUI
import AppKit

/// ウインドウと会話のフォーカスをまとめて監視する、描画を持たない部品。
struct SessionCompletionFocusObserver: View {
    let viewModel: DashboardViewModel
    let router: AppRouter
    // NSApp.isActive自体は描画更新を通知しないため、前面・背面の通知時に状態を保持する。
    @State private var applicationIsActive: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        isApplicationActive: () -> Bool = { NSApp.isActive }
    ) {
        self.viewModel = viewModel
        self.router = router
        _applicationIsActive = State(initialValue: isApplicationActive())
    }

    var body: some View {
        SessionCompletionFocusEvents(
            viewModel: viewModel, router: router,
            isWindowFocused: applicationIsActive && controlActiveState == .key
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            applicationIsActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            applicationIsActive = false
        }
    }
}

/// 完了の発生では既読にせず、その後のフォーカス変更で確認済みにする。
struct SessionCompletionFocusEvents: View {
    let viewModel: DashboardViewModel
    let router: AppRouter
    let isWindowFocused: Bool

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: router.focusedSessionID, initial: true) { _, _ in acknowledge() }
            .onChange(of: isWindowFocused) { _, _ in acknowledge() }
            .accessibilityHidden(true)
    }

    private func acknowledge() {
        viewModel.markFocusedCompletionSeen(
            router: router, isWindowFocused: isWindowFocused
        )
    }
}

extension DashboardViewModel {
    /// フォーカス中の会話だけを確認済みにする。背面のウインドウでは完了を残す。
    func markFocusedCompletionSeen(router: AppRouter, isWindowFocused: Bool) {
        guard isWindowFocused, let id = router.focusedSessionID,
              let node = sessionNode(id: id) else { return }
        if router.viewMode == .grid, !gridTileOrder().contains(id) { return }
        node.markCompletionSeen()
    }
}
