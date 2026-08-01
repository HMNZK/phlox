import AgentDomain
import Foundation
import Testing

@testable import DashboardFeature

// task-3 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// 固定する契約: 孤児 descriptor の正規化を、特権 requester が複数になっても
// **descriptor ごとに個別判定**で行う。集合全体で 1 回だけ実在判定して全件へ適用すると、
// 端末が複数あるとき「片方が実在するので、もう片方の孤児も救済されない」という取りこぼしが出る。

struct AcceptanceOrphanedRemoteSessionMigrationTests {
    @Test
    func emptySet_leavesDescriptorsUnchanged() {
        let orphan = descriptor(id: SessionID(), parentSessionID: SessionID(), launchContext: .orchestration)

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequesters: []
        )

        #expect(migrated == [orphan])
    }

    @Test
    func singleRequester_matchesLegacyBehavior() {
        let requester = SessionID()
        let orphan = descriptor(id: SessionID(), parentSessionID: requester, launchContext: .orchestration)

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequesters: [requester]
        )

        #expect(migrated.count == 1)
        #expect(migrated[0].launchContext == .remoteUser)
        #expect(migrated[0].parentSessionID == nil)
        #expect(migrated[0].id == orphan.id)
    }

    @Test
    func requesterThatExistsAsDescriptor_leavesItsChildUnchanged() {
        let requester = SessionID()
        let parent = descriptor(id: requester, parentSessionID: nil, launchContext: .interactive)
        let child = descriptor(id: SessionID(), parentSessionID: requester, launchContext: .orchestration)

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [parent, child],
            privilegedRequesters: [requester]
        )

        #expect(migrated == [parent, child])
    }

    // ここが単数 → 集合の一般化で最も落としやすい点。
    // phone のセッションは実在し、pad のセッションは実在しない。
    // pad の孤児だけが救済され、phone の子はそのまま維持されなければならない。
    @Test
    func perDescriptorDecision_rescuesOnlyOrphansWhoseParentIsMissing() {
        let phone = SessionID()
        let pad = SessionID()
        let phoneSession = descriptor(id: phone, parentSessionID: nil, launchContext: .interactive)
        let phoneChild = descriptor(id: SessionID(), parentSessionID: phone, launchContext: .orchestration)
        let padOrphan = descriptor(id: SessionID(), parentSessionID: pad, launchContext: .orchestration)

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [phoneSession, phoneChild, padOrphan],
            privilegedRequesters: [phone, pad]
        )

        #expect(migrated.count == 3)
        #expect(migrated[0] == phoneSession)
        #expect(migrated[1] == phoneChild)
        #expect(migrated[2].launchContext == .remoteUser)
        #expect(migrated[2].parentSessionID == nil)
    }

    @Test
    func nonOrchestrationDescriptors_areNeverTouched() {
        let requester = SessionID()
        let interactive = descriptor(id: SessionID(), parentSessionID: requester, launchContext: .interactive)

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [interactive],
            privilegedRequesters: [requester]
        )

        #expect(migrated == [interactive])
    }

    @Test
    func migration_isIdempotent() {
        let requester = SessionID()
        let orphan = descriptor(id: SessionID(), parentSessionID: requester, launchContext: .orchestration)

        let once = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequesters: [requester]
        )
        let twice = OrphanedRemoteSessionMigration.migrate(
            descriptors: once,
            privilegedRequesters: [requester]
        )

        #expect(once == twice)
    }

    @Test
    func result_doesNotDependOnSetIterationOrder() {
        let phone = SessionID()
        let pad = SessionID()
        let mac = SessionID()
        let orphan = descriptor(id: SessionID(), parentSessionID: pad, launchContext: .orchestration)

        let a = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequesters: Set([phone, pad, mac])
        )
        let b = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequesters: Set([mac, pad, phone])
        )

        #expect(a == b)
    }

    private func descriptor(
        id: SessionID,
        parentSessionID: SessionID?,
        launchContext: SessionLaunchContext
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: id,
            kind: .codex,
            workingDirectory: "/tmp/acceptance-orphan-migration",
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
