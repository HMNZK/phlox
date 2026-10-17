import Foundation

@MainActor
enum SessionPullRefresh {
    static func perform(sessionList: SessionListViewModel, usage: UsageViewModel?) async {
        async let refreshSessions: Void = sessionList.refresh()
        async let refreshUsage: Void? = usage?.load()
        _ = await (refreshSessions, refreshUsage)
    }
}
