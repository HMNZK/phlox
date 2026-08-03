import Foundation
import Testing
@testable import AgentDomain

@Suite("SessionChangeScope resolver whitebox")
struct SessionChangeScopeWhiteboxTests {
    @Test("選択セッションの作業ディレクトリを root provider に渡す")
    func resolverUsesSelectedWorkspacePath() {
        let selected = SessionID()
        let other = SessionID()
        var receivedPaths: [String] = []

        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: selected,
            workspaces: [
                SessionWorkspace(
                    sessionID: selected,
                    workingDirectory: "/tmp/phlox-scope/repository/subdirectory",
                    isActive: true
                ),
                SessionWorkspace(
                    sessionID: other,
                    workingDirectory: "/tmp/phlox-scope/other",
                    isActive: true
                ),
            ],
            repositoryRootProvider: { path in
                receivedPaths.append(path)
                return "/tmp/phlox-scope/repository"
            }
        )

        #expect(receivedPaths == ["/tmp/phlox-scope/repository/subdirectory"])
        #expect(scope == .isolated(repositoryRoot: "/tmp/phlox-scope/repository"))
    }

    @Test("共有判定の正規化は WorkspaceCollisionPolicy に従う")
    func resolverUsesWorkspaceCollisionPolicyForPeers() {
        let selected = SessionID()
        let peer = SessionID()

        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: selected,
            workspaces: [
                SessionWorkspace(
                    sessionID: selected,
                    workingDirectory: "/tmp/phlox-scope/repository/./",
                    isActive: true
                ),
                SessionWorkspace(
                    sessionID: peer,
                    workingDirectory: "/tmp/phlox-scope/repository",
                    isActive: true
                ),
            ],
            repositoryRootProvider: { _ in "/tmp/phlox-scope/repository" }
        )

        #expect(scope == .shared(repositoryRoot: "/tmp/phlox-scope/repository", peerCount: 1))
    }

    @Test("終了済み選択セッションでも稼働中の共有相手がいれば帰属不能")
    func resolverCountsActivePeersForInactiveSelection() {
        let dead = SessionID()
        let liveOne = SessionID()
        let liveTwo = SessionID()

        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: dead,
            workspaces: [
                SessionWorkspace(
                    sessionID: dead,
                    workingDirectory: "/tmp/phlox-scope/repository",
                    isActive: false
                ),
                SessionWorkspace(
                    sessionID: liveOne,
                    workingDirectory: "/tmp/phlox-scope/repository",
                    isActive: true
                ),
                SessionWorkspace(
                    sessionID: liveTwo,
                    workingDirectory: "/tmp/phlox-scope/repository",
                    isActive: true
                ),
            ],
            repositoryRootProvider: { _ in "/tmp/phlox-scope/repository" }
        )

        #expect(
            scope == .shared(repositoryRoot: "/tmp/phlox-scope/repository", peerCount: 2)
        )
        #expect(!scope.attributesChangesToSession)
    }
}
