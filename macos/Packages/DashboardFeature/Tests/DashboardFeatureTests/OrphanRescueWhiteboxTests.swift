import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

struct OrphanRescueWhiteboxTests {
    @Test
    func privilegedRequesterDescriptorExists_childIsUnchanged() {
        let requester = SessionID()
        let parent = descriptor(
            id: requester,
            parentSessionID: nil,
            launchContext: .interactive
        )
        let child = descriptor(
            id: SessionID(),
            parentSessionID: requester,
            launchContext: .orchestration
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [parent, child],
            privilegedRequester: requester
        )

        #expect(migrated == [parent, child])
    }

    private func descriptor(
        id: SessionID,
        parentSessionID: SessionID?,
        launchContext: SessionLaunchContext
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: id,
            kind: .codex,
            workingDirectory: "/tmp/orphan-rescue-whitebox",
            name: "Session",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            command: "/usr/local/bin/codex",
            args: [],
            env: [:],
            parentSessionID: parentSessionID,
            launchContext: launchContext
        )
    }
}
