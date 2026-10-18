import Foundation
import Testing
import Features
import PhloxCore

@MainActor
struct SessionURLNavigationTests {
    @Test func URLAndNotificationUseTheSamePendingRequest() throws {
        let coordinator = PushCoordinator()
        #expect(coordinator.handleSessionURL(try #require(SessionURL.make(sessionID: "approval"))))
        #expect(coordinator.pendingSessionID == "approval")
        coordinator.handleNotificationTap(userInfo: ["phlox": ["sessionId": "question", "type": "question_pending"]])
        #expect(coordinator.pendingSessionID == "question")
        #expect(!coordinator.handleSessionURL(try #require(URL(string: "phlox://pair/a"))))
        #expect(coordinator.pendingSessionID == "question")
    }

    @Test(arguments: [SessionStatus.awaitingApproval(prompt: "許可しますか"), .awaitingUserQuestion, .running])
    func waitsForUnlockAndSuccessfulLoadThenOpensSession(status: SessionStatus) throws {
        let coordinator = PushCoordinator()
        let router = NavigationRouter()
        router.push(.settings)
        router.present(.settings)
        let session = Session(id: "target", name: "名前", agent: .claudeCode, status: status, updatedAt: Date())
        coordinator.handleSessionURL(try #require(SessionURL.make(sessionID: session.id)))
        #expect(coordinator.openPendingSession(canNavigate: false, listState: .loaded([session]), fetchedAt: Date(), router: router) == nil)
        #expect(coordinator.openPendingSession(canNavigate: true, listState: .loaded([session]), fetchedAt: .distantPast, router: router) == nil)
        #expect(coordinator.openPendingSession(canNavigate: true, listState: .loaded([session]), fetchedAt: nil, router: router) == nil)
        #expect(router.depth == 1)
        #expect(router.presented == .settings)
        for state in [SessionsState.loading, .offline, .error(.unreachable)] {
            #expect(coordinator.openPendingSession(canNavigate: true, listState: state, fetchedAt: Date(), router: router) == nil)
            #expect(coordinator.pendingSessionID == session.id)
        }
        #expect(coordinator.openPendingSession(canNavigate: true, listState: .loaded([session]), fetchedAt: Date(), router: router) == .session(session.id))
        #expect(coordinator.pendingSessionID == nil)
        #expect(router.depth == 1)
        #expect(router.presented == nil)
        let expected = NavigationRouter()
        expected.push(.sessionDetail(id: session.id))
        #expect(router.path == expected.path)
        #expect(coordinator.openPendingSession(canNavigate: true, listState: .loaded([session]), fetchedAt: Date(), router: router) == nil)
    }

    @Test func missingSessionIsConfirmedOnlyBySuccessfulList() throws {
        for state in [SessionsState.empty, .loaded([])] {
            let coordinator = PushCoordinator()
            let router = NavigationRouter()
            router.push(.settings)
            coordinator.handleSessionURL(try #require(SessionURL.make(sessionID: "gone")))
            #expect(coordinator.openPendingSession(canNavigate: true, listState: state, fetchedAt: Date(), router: router) == .notFound)
            #expect(coordinator.pendingSessionID == nil)
            #expect(router.depth == 0)
        }
    }
}
