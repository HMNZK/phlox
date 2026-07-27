import Testing
import AgentDomain
@testable import DashboardFeature

struct SessionReachabilityWhiteboxTests {
    @Test(
        arguments: [
            SessionLaunchContext.interactive,
            SessionLaunchContext.remoteUser,
        ]
    )
    func topLevelGridSessionsAreReachableWithoutProject(
        launchContext: SessionLaunchContext
    ) {
        #expect(
            SessionReachability.isReachable(
                launchContext: launchContext,
                projectID: nil
            )
        )
    }

    @Test
    func orchestrationSessionIsReachableOnlyWhenAssignedToProject() {
        #expect(
            SessionReachability.isReachable(
                launchContext: .orchestration,
                projectID: ProjectID()
            )
        )
        #expect(
            !SessionReachability.isReachable(
                launchContext: .orchestration,
                projectID: nil
            )
        )
    }
}
