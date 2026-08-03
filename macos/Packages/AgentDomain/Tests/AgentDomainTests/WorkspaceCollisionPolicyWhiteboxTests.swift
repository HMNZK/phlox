import Foundation
import Testing
@testable import AgentDomain

@Suite("WorkspaceCollisionPolicy whitebox")
struct WorkspaceCollisionPolicyWhiteboxTests {
    private func workspace(
        _ directory: String,
        sessionID: SessionID = SessionID(),
        isActive: Bool = true
    ) -> SessionWorkspace {
        SessionWorkspace(
            sessionID: sessionID,
            workingDirectory: directory,
            isActive: isActive
        )
    }

    @Test("空の作業ディレクトリは識別子にならず、空パス同士を衝突させない")
    func emptyWorkspaceDoesNotBecomeCurrentDirectory() {
        let result = WorkspaceCollisionPolicy.collisions(among: [
            workspace(""),
            workspace(""),
        ])

        #expect(WorkspaceCollisionPolicy.canonicalPath("") == "")
        #expect(result.isEmpty)
    }

    @Test("相対パスの語彙的なドット参照を安全に正規化する")
    func relativePathIsNormalizedWithoutCrashing() {
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("relative/./sub/../repo")
                == WorkspaceCollisionPolicy.canonicalPath("relative/repo")
        )
    }

    @Test("パスの大文字小文字を保持する")
    func canonicalPathIsCaseSensitive() {
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/Repo")
                != WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo")
        )
    }

    @Test("存在しないパスも値を返し、同じ正規化結果だけを共有扱いにする")
    func nonexistentPathsRemainSafeAndComparable() {
        let first = "/tmp/phlox-ca-missing/one/../repo"
        let second = "/tmp/phlox-ca-missing/repo/"
        let a = SessionID()
        let b = SessionID()

        let result = WorkspaceCollisionPolicy.collisions(among: [
            workspace(first, sessionID: a),
            workspace(second, sessionID: b),
        ])

        #expect(!WorkspaceCollisionPolicy.canonicalPath(first).isEmpty)
        #expect(result.count == 1)
        #expect(result.values.first == Set([a, b]))
    }

    @Test("非アクティブな対象の peers は空で、他方だけを衝突扱いにしない")
    func inactiveWorkspaceIsExcludedBeforePeerLookup() {
        let inactive = SessionID()
        let active = SessionID()
        let workspaces = [
            workspace("/tmp/phlox-ca/repo", sessionID: inactive, isActive: false),
            workspace("/tmp/phlox-ca/repo", sessionID: active),
        ]

        #expect(WorkspaceCollisionPolicy.peers(of: inactive, among: workspaces).isEmpty)
        #expect(WorkspaceCollisionPolicy.peers(of: active, among: workspaces).isEmpty)
    }
}
