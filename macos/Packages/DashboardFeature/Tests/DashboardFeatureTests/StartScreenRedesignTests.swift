import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

// 新規チャット入口を差し替えた後も残す worktree 起動失敗と復元データの確認。

@Suite("Start screen redesign (08)")
struct StartScreenRedesignTests {

    @Test func worktreeFailureLog_showsGitOutput_andIgnoresOtherErrors() {
        let failed = WorktreeIsolationSpawnError.worktreeCreationFailed(path: "/w", branchName: "b", detail: "fatal: already checked out")
        #expect(NewSessionCollisionGate.worktreeFailureLog(failed) == "fatal: already checked out")
        let aborted = WorktreeIsolationSpawnError.aborted(.notAGitRepository(path: "/p"))
        #expect(NewSessionCollisionGate.worktreeFailureLog(aborted) == aborted.localizedDescription)
        #expect(NewSessionCollisionGate.worktreeFailureLog(AgentSpawnError.unsupportedBackend) == nil)
    }

    @Test func isolationOptOut_survivesPersistence_andOldDataHasNone() throws {
        let base = PersistedSessionDescriptor(
            id: SessionID(), kind: .codex, workingDirectory: "/tmp/p", name: "n",
            projectID: nil, startedAt: Date(timeIntervalSince1970: 0), command: "/bin/cat", args: [], env: [:]
        )
        let roundTrip = { (value: PersistedSessionDescriptor) in
            try JSONDecoder().decode(PersistedSessionDescriptor.self, from: JSONEncoder().encode(value))
        }
        #expect(try roundTrip(base.updating(worktreeIsolationOptOut: true)).worktreeIsolationOptOut == true)
        #expect(try roundTrip(base).worktreeIsolationOptOut == nil)
    }
}
