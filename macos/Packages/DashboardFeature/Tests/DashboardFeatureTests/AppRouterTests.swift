import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// MARK: - mainRoute

@Test @MainActor
func appRouter_defaultsToSessionsRoute() {
    let router = AppRouter()

    #expect(router.mainRoute == .sessions)
}

@Test @MainActor
func showSessions_setsMainRouteToSessions() {
    let router = AppRouter()

    router.showSessions()

    #expect(router.mainRoute == .sessions)
}

// MARK: - gridFilterProjectID

@Test @MainActor
func toggleGridFilter_setsProjectIDWhenNil() {
    let router = AppRouter()
    let projectID = ProjectID()

    router.toggleGridFilter(projectID: projectID)

    #expect(router.gridFilterProjectID == projectID)
}

@Test @MainActor
func toggleGridFilter_clearsWhenSameProjectID() {
    let router = AppRouter()
    let projectID = ProjectID()
    router.gridFilterProjectID = projectID

    router.toggleGridFilter(projectID: projectID)

    #expect(router.gridFilterProjectID == nil)
}

@Test @MainActor
func toggleGridFilter_replacesWhenDifferentProjectID() {
    let router = AppRouter()
    let first = ProjectID()
    let second = ProjectID()
    router.gridFilterProjectID = first

    router.toggleGridFilter(projectID: second)

    #expect(router.gridFilterProjectID == second)
}

@Test @MainActor
func clearGridFilter_resetsToNil() {
    let router = AppRouter()
    router.gridFilterProjectID = ProjectID()

    router.clearGridFilter()

    #expect(router.gridFilterProjectID == nil)
}
