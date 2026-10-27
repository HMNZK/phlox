import Foundation
import AgentDomain
import SessionFeature

/// 24 時間使われていないチャットのエージェントプロセスを止める（ADR 0221）。見回りは常駐側で行う。
extension DashboardViewModel {
    nonisolated static let idleSuspendAfter: TimeInterval = 24 * 60 * 60
    nonisolated static let idleSuspendCheckInterval: Duration = .seconds(10 * 60)

    /// 画面に表示中のセッションを使われたものとして記録する。画面は表示が変わったときと 5 分ごとに呼ぶ。
    public func noteSessionsViewed(_ ids: [SessionID]) {
        guard !ids.isEmpty else { return }
        if isRuntimeProjection { sendRuntimeReport(.sessionsViewed(ids)); return }
        let now = Date()
        for id in ids { lastViewedAt[id] = now }
    }

    func suspendIdleChatSessions(now: Date) async {
        guard !isRuntimeProjection else { return }
        let cutoff = now.addingTimeInterval(-Self.idleSuspendAfter)
        for node in sessionNodes {
            guard case .appServer(let chat) = node, chat.canSuspendForIdle,
                  max(chat.lastActivityAt, lastViewedAt[chat.id] ?? .distantPast) <= cutoff else { continue }
            await chat.suspendForIdle()
        }
    }
}
