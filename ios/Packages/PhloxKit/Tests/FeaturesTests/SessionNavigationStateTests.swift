import AgentDomain
import Features
import Foundation
import PhloxCore
import Testing

@Suite("Session navigation state")
struct SessionNavigationStateTests {
    @Test("対応待ちに入るのは承認待ち・質問あり・エラー・無応答の4状態")
    func includesTheFourAttentionStates() {
        let sessions = [
            session("approval", status: .awaitingApproval(prompt: "approve")),
            session("question", status: .awaitingUserQuestion),
            session("error", status: .error(message: "failed")),
            session("stalled", status: .running, isStalled: true),
            session("running", status: .running),
            session("done", status: .completed(exitCode: 0)),
        ]

        let state = SessionNavigationState.resolve(
            listState: .loaded(sessions),
            lastKnownSessions: sessions,
            reachability: .online
        )

        #expect(state.badgeCount == 4)
        #expect(state.attentionItems.map(\.displayState) == [.approval, .question, .error, .stalled])
        #expect(state.accessory == .attention)
    }

    @Test("欄・バー・長押しメニューは待ち時間順で同じ先頭になる")
    func sharesWaitingOrderWithList() {
        let sessions = [
            session("running", status: .running),
            session("first", status: .error(message: "failed"), since: Date(timeIntervalSince1970: 20)),
            session("second", status: .awaitingApproval(prompt: "approve"), since: Date(timeIntervalSince1970: 10)),
        ]

        let state = SessionNavigationState.resolve(
            listState: .loaded(sessions),
            lastKnownSessions: sessions,
            reachability: .online
        )

        let projection = SessionListProjection.make(sessions: sessions)
        #expect(state.firstAttentionItem?.id == "second")
        #expect(state.attentionItems.map(\.id) == ["second", "first"])
        #expect(state.firstAttentionItem?.id == projection.attentionSessions.first?.id)
        #expect(state.attentionItems.map(\.id) == projection.attentionSessions.map(\.id))
    }

    @Test("対応待ちバーは読み込み中・空・取得エラー・空の一覧で出ない")
    func hidesAttentionAccessoryWhenListIsNotLoadedWithSessions() {
        let lastKnown = [session("old", status: .awaitingApproval(prompt: "approve"))]
        let states: [SessionsState] = [
            .loading,
            .empty,
            .loaded([]),
            .error(.server(status: 500, message: "failed")),
            .offline,
        ]

        for listState in states {
            let state = SessionNavigationState.resolve(
                listState: listState,
                lastKnownSessions: lastKnown,
                reachability: .online
            )
            #expect(state.accessory == nil)
        }

        let judging = SessionNavigationState.resolve(
            listState: .loaded(lastKnown),
            lastKnownSessions: lastKnown,
            reachability: .unknown
        )
        #expect(judging.accessory == nil)
    }

    @Test("オフラインでは最後のバッジ件数を残して到達不可の欄へ替える")
    func preservesBadgeCountWhileOffline() {
        let lastKnown = [
            session("approval", status: .awaitingApproval(prompt: "approve")),
            session("question", status: .awaitingUserQuestion),
            session("error", status: .error(message: "failed")),
            session("stalled", status: .running, isStalled: true),
        ]

        let state = SessionNavigationState.resolve(
            listState: .offline,
            lastKnownSessions: lastKnown,
            reachability: .unreachableHost
        )

        #expect(state.badgeCount == 4)
        #expect(state.sessionsTabAccessibilityLabel == "セッション、対応待ち 4 件")
        #expect(state.accessory == .offline)
        #expect(state.attentionItems.isEmpty)
    }

    @Test("0件のVoiceOver名に件数を付けない")
    func omitsZeroCountFromSessionsAccessibilityLabel() {
        let state = SessionNavigationState.resolve(
            listState: .empty,
            lastKnownSessions: [],
            reachability: .online
        )

        #expect(state.badgeCount == 0)
        #expect(state.sessionsTabAccessibilityLabel == "セッション")
    }

    private func session(
        _ id: String,
        status: SessionStatus,
        isStalled: Bool = false,
        since: Date? = nil
    ) -> Session {
        Session(
            id: id,
            name: id,
            agent: .codex,
            status: status,
            projectName: "Phlox",
            isStalled: isStalled,
            statusEnteredAt: since,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
