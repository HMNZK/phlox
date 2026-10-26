import Foundation
import AgentDomain
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

struct SessionCompletionFocusEvents: View {
    let viewModel: DashboardViewModel
    let router: AppRouter
    let isWindowFocused: Bool

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: router.focusedSessionID, initial: true) { _, _ in acknowledge() }
            .onChange(of: isWindowFocused) { _, _ in acknowledge() }
            .onChange(of: router.focusedSessionID.flatMap { viewModel.sessionNode(id: $0)?.hasUnseenCompletion }) { _, _ in acknowledge() }
            .onChange(of: router.viewMode) { _, _ in acknowledge() }
            .onChange(of: router.viewMode == .grid ? viewModel.gridTileOrder() : []) { _, _ in acknowledge() }
            .onChange(of: displayedSessionIDs, initial: true) { _, ids in viewModel.noteSessionsViewed(ids) }
            // 表示し続けているセッションを常駐側が止めないよう、5 分ごとに知らせる（ADR 0221）。
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5 * 60))
                    viewModel.noteSessionsViewed(displayedSessionIDs)
                }
            }
            .accessibilityHidden(true)
    }

    /// 画面に表示中のセッション。単一表示では出ている会話、グリッドでは並んでいるタイル。
    private var displayedSessionIDs: [SessionID] {
        if router.viewMode == .grid { return viewModel.gridTileOrder() }
        return router.displayedChatSessionIDs { viewModel.sessionNode(id: $0)?.projectID }
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
