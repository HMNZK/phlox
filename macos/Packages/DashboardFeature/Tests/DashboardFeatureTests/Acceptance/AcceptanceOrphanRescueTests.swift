import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-4 の受け入れテスト（不変・実装役は編集禁止）。
///
/// 契約: すでに `sessions.json` に取り残された「モバイル発の孤児セッション」を、
/// 起動時に**決定論的に** `.remoteUser` ルートへ正規化して救済する。
///
/// 背景（`docs/phase0.md` §2）: Control API 経由の spawn が、モバイルトークンに紐づく
/// **実在しない合成 SessionID**（Keychain 上の requester）を `parentSessionID` に書いていたため、
/// 生成時点で孤児になり UI から到達できなくなっていた。task-2 で発生源は断たれたが、
/// 既存データはそのまま残る。本タスクはその救済にあたる。
///
/// ユーザーのゲート①決定: 「**iPhone 由来と特定できるものだけ出す**」。
/// したがって「親が居ない孤児をすべて救済する」のは誤りで、
/// `parentSessionID` がその Mac の実 requester ID と一致するものだけが対象。
struct AcceptanceOrphanRescueTests {

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    /// モバイルトークンに紐づく合成 requester（＝実在しないセッション ID）。
    private static let mobileRequester = SessionID(
        rawValue: UUID(uuidString: "67EA7FF6-738B-4E1B-AB5C-6044AE822878")!
    )

    private static func descriptor(
        id: SessionID,
        name: String,
        parentSessionID: SessionID?,
        launchContext: SessionLaunchContext,
        workingDirectory: String = "/tmp/orphan-rescue",
        token: String? = "orphan-token",
        resumeID: String? = "resume-1",
        pid: pid_t? = 4242,
        role: String? = nil
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: id,
            kind: .codex,
            workingDirectory: workingDirectory,
            name: name,
            projectID: nil,
            startedAt: fixedNow,
            command: "/usr/local/bin/codex",
            args: ["--foo"],
            env: ["BAR": "baz"],
            token: token,
            resumeID: resumeID,
            parentSessionID: parentSessionID,
            pid: pid,
            launchContext: launchContext,
            role: role
        )
    }

    // MARK: - 判定（純粋関数）

    /// 対象: `.orchestration` かつ親が特権 requester かつその ID が descriptor 集合に実在しない。
    /// → `.remoteUser` のルート（親リンクなし）へ正規化する。
    @Test func migrate_mobileOrphan_becomesRemoteUserRoot() throws {
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "Daisy",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequester: Self.mobileRequester
        )

        #expect(migrated.count == 1)
        let rescued = try #require(migrated.first)
        #expect(rescued.id == orphan.id)
        #expect(rescued.launchContext == .remoteUser)
        #expect(rescued.parentSessionID == nil)
    }

    /// 親が実在する `.orchestration`（正常な CLI サブセッション）は**一切変更しない**。
    /// 誤って可視化すると ADR 0027 の除外規則を壊す。
    @Test func migrate_realParent_isUnchanged() {
        let parent = Self.descriptor(
            id: SessionID(),
            name: "Parent",
            parentSessionID: nil,
            launchContext: .interactive
        )
        let child = Self.descriptor(
            id: SessionID(),
            name: "Child",
            parentSessionID: parent.id,
            launchContext: .orchestration
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [parent, child],
            privilegedRequester: Self.mobileRequester
        )

        #expect(migrated == [parent, child])
    }

    /// 親が実在しなくても、特権 requester と一致しない孤児は由来を特定できないので対象外。
    @Test func migrate_orphanWithUnrelatedParent_isUnchanged() {
        let unrelatedParent = SessionID(
            rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "UnknownOrigin",
            parentSessionID: unrelatedParent,
            launchContext: .orchestration
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequester: Self.mobileRequester
        )

        #expect(migrated == [orphan])
    }

    /// 特権 requester が未設定（モバイル未使用の Mac）なら何もしない。
    @Test func migrate_nilPrivilegedRequester_changesNothing() {
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "Daisy",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequester: nil
        )

        #expect(migrated == [orphan])
    }

    /// `.orchestration` 以外（ユーザーが直接起動したもの）は、親が requester でも触らない。
    @Test func migrate_nonOrchestrationContext_isUnchanged() {
        let interactive = Self.descriptor(
            id: SessionID(),
            name: "Interactive",
            parentSessionID: Self.mobileRequester,
            launchContext: .interactive
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [interactive],
            privilegedRequester: Self.mobileRequester
        )

        #expect(migrated == [interactive])
    }

    /// **冪等**: 2回走らせても結果が変わらない（毎起動でマイグレートし続けない）。
    @Test func migrate_isIdempotent() {
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "Rose",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration
        )

        let once = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequester: Self.mobileRequester
        )
        let twice = OrphanedRemoteSessionMigration.migrate(
            descriptors: once,
            privilegedRequester: Self.mobileRequester
        )

        #expect(once == twice)
    }

    /// 正規化で変えてよいのは `launchContext` と `parentSessionID` の2つだけ。
    /// 他のフィールドを落とすと、復元できないセッションが生まれる。
    @Test func migrate_preservesEveryOtherField() throws {
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "Lily",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration,
            workingDirectory: "/tmp/lily",
            token: "lily-token",
            resumeID: "lily-resume",
            pid: 9999,
            role: "批判者"
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [orphan],
            privilegedRequester: Self.mobileRequester
        )
        let rescued = try #require(migrated.first)

        #expect(rescued.id == orphan.id)
        #expect(rescued.agentRef == orphan.agentRef)
        #expect(rescued.workingDirectory == orphan.workingDirectory)
        #expect(rescued.name == orphan.name)
        #expect(rescued.projectID == orphan.projectID)
        #expect(rescued.startedAt == orphan.startedAt)
        #expect(rescued.command == orphan.command)
        #expect(rescued.args == orphan.args)
        #expect(rescued.env == orphan.env)
        #expect(rescued.backend == orphan.backend)
        #expect(rescued.token == orphan.token)
        #expect(rescued.resumeID == orphan.resumeID)
        #expect(rescued.pid == orphan.pid)
        #expect(rescued.role == orphan.role)
    }

    /// 並び順と件数を変えない（復元順・表示順を壊さない）。
    @Test func migrate_preservesOrderAndCount() {
        let first = Self.descriptor(
            id: SessionID(),
            name: "First",
            parentSessionID: nil,
            launchContext: .interactive
        )
        let orphan = Self.descriptor(
            id: SessionID(),
            name: "Petunia",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration
        )
        let last = Self.descriptor(
            id: SessionID(),
            name: "Last",
            parentSessionID: nil,
            launchContext: .interactive
        )

        let migrated = OrphanedRemoteSessionMigration.migrate(
            descriptors: [first, orphan, last],
            privilegedRequester: Self.mobileRequester
        )

        #expect(migrated.map(\.id) == [first.id, orphan.id, last.id])
    }

    // MARK: - 起動時の統合（復元 → 永続化 → UI 到達）

    /// 起動して復元すると、孤児は救済され、**その結果が永続化され**、UI から到達できる。
    @Test @MainActor
    func restore_mobileOrphan_isRescuedPersistedAndReachable() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let sessionID = SessionID()
        let orphan = Self.descriptor(
            id: sessionID,
            name: "Daisy",
            parentSessionID: Self.mobileRequester,
            launchContext: .orchestration,
            workingDirectory: workspaceRoot.path,
            pid: nil
        )
        let sessionStore = InMemorySessionStore([orphan])
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"]
        )

        let dashboard = DashboardViewModel(environment: environment)
        // 本番の配線順（CompositionRoot: setPrivilegedRequester → start）と同じ。
        dashboard.setPrivilegedRequester(Self.mobileRequester)
        await dashboard.start()

        // 復元されたセッションが UI に現れる。
        try await waitUntil { dashboard.sessionNode(id: sessionID) != nil }
        let node = try #require(dashboard.sessionNode(id: sessionID))
        #expect(node.launchContext == .remoteUser)
        #expect(node.controllable.parentSessionID == nil)
        #expect(dashboard.isReachableFromUI(sessionID))
        #expect(dashboard.gridVisibleSessionNodes.contains { $0.id == sessionID })

        // 救済結果が永続化される（次回起動で再度マイグレートしない）。
        try await waitUntil {
            await sessionStore.load().first { $0.id == sessionID }?.launchContext == .remoteUser
        }
        let persisted = try #require(await sessionStore.load().first { $0.id == sessionID })
        #expect(persisted.launchContext == .remoteUser)
        #expect(persisted.parentSessionID == nil)
    }

    /// 対象外の孤児（由来を特定できない）は、復元後も従来どおり非表示のまま。
    @Test @MainActor
    func restore_unrelatedOrphan_staysHidden() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let sessionID = SessionID()
        let unrelatedParent = SessionID(
            rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let orphan = Self.descriptor(
            id: sessionID,
            name: "UnknownOrigin",
            parentSessionID: unrelatedParent,
            launchContext: .orchestration,
            workingDirectory: workspaceRoot.path,
            pid: nil
        )
        let sessionStore = InMemorySessionStore([orphan])
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"]
        )

        let dashboard = DashboardViewModel(environment: environment)
        dashboard.setPrivilegedRequester(Self.mobileRequester)
        await dashboard.start()

        try await waitUntil { dashboard.sessionNode(id: sessionID) != nil }
        let node = try #require(dashboard.sessionNode(id: sessionID))
        #expect(node.launchContext == .orchestration)
        #expect(node.controllable.parentSessionID == unrelatedParent)
        #expect(!dashboard.gridVisibleSessionNodes.contains { $0.id == sessionID })
    }
}
