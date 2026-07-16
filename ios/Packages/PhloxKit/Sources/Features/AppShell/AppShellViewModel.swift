import Foundation

public enum AppTab: CaseIterable, Equatable, Sendable {
    case sessions
    case settings
    case usage
}

@MainActor
@Observable
public final class AppShellViewModel {
    public private(set) var selectedTab: AppTab
    public let overview: SessionsOverviewViewModel

    public init(
        selectedTab: AppTab = .sessions,
        overview: SessionsOverviewViewModel
    ) {
        self.selectedTab = selectedTab
        self.overview = overview
    }

    public func selectTab(_ tab: AppTab) {
        selectedTab = tab
    }

    /// 下部タブボタンのタップを、選択済みタブを含めて必ず選択処理へ渡す。
    public func handleTabTap(_ tab: AppTab) {
        selectTab(tab)
    }
}
