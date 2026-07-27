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
                from: .desktop,
                launchContext: launchContext,
                projectID: nil
            )
        )
    }

    @Test
    func orchestrationSessionIsReachableOnlyWhenAssignedToProject() {
        #expect(
            SessionReachability.isReachable(
                from: .desktop,
                launchContext: .orchestration,
                projectID: ProjectID()
            )
        )
        #expect(
            !SessionReachability.isReachable(
                from: .desktop,
                launchContext: .orchestration,
                projectID: nil
            )
        )
    }

    @Test(
        arguments: [
            SessionLaunchContext.interactive,
            SessionLaunchContext.remoteUser,
            SessionLaunchContext.orchestration,
        ]
    )
    func mobileSessionsAreReachableRegardlessOfLaunchContext(
        launchContext: SessionLaunchContext
    ) {
        #expect(
            SessionReachability.isReachable(
                from: .mobile,
                launchContext: launchContext,
                projectID: nil
            )
        )
    }
}
