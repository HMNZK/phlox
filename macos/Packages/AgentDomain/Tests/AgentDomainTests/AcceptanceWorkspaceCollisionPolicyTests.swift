// 契約の正本: tasks/task-1.md — 同一作業ディレクトリを共有する複数セッションの検知。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 背景: `Project.isManagedDirectory == false` のプロジェクトでは全セッションが同じ作業ツリーを
// 共有するが、検知も警告も存在しない。ここではその判定を純関数として凍結する。
// 挙動は変えない（spawn をブロックしない）＝警告として可視化するだけ、が task-1 の契約。

import Foundation
import Testing
@testable import AgentDomain

@Suite("Acceptance: WorkspaceCollisionPolicy（task-1）")
struct AcceptanceWorkspaceCollisionPolicyTests {
    private func sid() -> SessionID { SessionID() }

    private func ws(_ id: SessionID, _ dir: String, active: Bool = true) -> SessionWorkspace {
        SessionWorkspace(sessionID: id, workingDirectory: dir, isActive: active)
    }

    // MARK: - 正準化

    @Test func 末尾スラッシュの有無を同一視する() {
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo/")
                == WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo")
        )
    }

    @Test func ドットと親ディレクトリ参照を解決する() {
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/./repo")
                == WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo")
        )
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/sub/../repo")
                == WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo")
        )
    }

    @Test func シンボリックリンク経由のパスを実体と同一視する() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("phlox-collision-\(UUID().uuidString)", isDirectory: true)
        let real = base.appendingPathComponent("real", isDirectory: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(
            WorkspaceCollisionPolicy.canonicalPath(link.path)
                == WorkspaceCollisionPolicy.canonicalPath(real.path)
        )
    }

    @Test func 別ディレクトリは同一視しない() {
        #expect(
            WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo-a")
                != WorkspaceCollisionPolicy.canonicalPath("/tmp/phlox-ca/repo-b")
        )
    }

    // MARK: - 衝突集合

    @Test func 同一ディレクトリの2アクティブセッションは衝突として返る() {
        let a = sid(), b = sid()
        let result = WorkspaceCollisionPolicy.collisions(among: [
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo/"),
        ])
        #expect(result.count == 1)
        #expect(result.values.first == Set([a, b]))
    }

    @Test func 単独セッションは衝突に含めない() {
        let a = sid()
        let result = WorkspaceCollisionPolicy.collisions(among: [ws(a, "/tmp/phlox-ca/repo")])
        #expect(result.isEmpty)
    }

    @Test func 別ディレクトリのセッション同士は衝突しない() {
        let result = WorkspaceCollisionPolicy.collisions(among: [
            ws(sid(), "/tmp/phlox-ca/repo-a"),
            ws(sid(), "/tmp/phlox-ca/repo-b"),
        ])
        #expect(result.isEmpty)
    }

    @Test func 終了したセッションは衝突の当事者に数えない() {
        let a = sid(), b = sid()
        let result = WorkspaceCollisionPolicy.collisions(among: [
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo", active: false),
        ])
        #expect(result.isEmpty)
    }

    @Test func セッション3件が共有する場合は1エントリにまとまる() {
        let a = sid(), b = sid(), c = sid()
        let result = WorkspaceCollisionPolicy.collisions(among: [
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo"),
            ws(c, "/tmp/phlox-ca/repo"),
        ])
        #expect(result.count == 1)
        #expect(result.values.first == Set([a, b, c]))
    }

    @Test func 複数の衝突グループを別エントリとして返す() {
        let a = sid(), b = sid(), c = sid(), d = sid()
        let result = WorkspaceCollisionPolicy.collisions(among: [
            ws(a, "/tmp/phlox-ca/repo-a"),
            ws(b, "/tmp/phlox-ca/repo-a"),
            ws(c, "/tmp/phlox-ca/repo-b"),
            ws(d, "/tmp/phlox-ca/repo-b"),
        ])
        #expect(result.count == 2)
        #expect(Set(result.values) == Set([Set([a, b]), Set([c, d])]))
    }

    // MARK: - peers

    @Test func peersは自分自身を含まない() {
        let a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: a, among: [
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo"),
        ])
        #expect(peers == Set([b]))
    }

    @Test func 共有していないセッションのpeersは空() {
        let a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: a, among: [
            ws(a, "/tmp/phlox-ca/repo-a"),
            ws(b, "/tmp/phlox-ca/repo-b"),
        ])
        #expect(peers.isEmpty)
    }

    @Test func 存在しないセッションIDのpeersは空() {
        let a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: sid(), among: [
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo"),
        ])
        #expect(peers.isEmpty)
    }

    @Test func 自分が終了済みならpeersは空() {
        let a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: a, among: [
            ws(a, "/tmp/phlox-ca/repo", active: false),
            ws(b, "/tmp/phlox-ca/repo"),
        ])
        #expect(peers.isEmpty)
    }

    /// 上の「自分が終了済みならpeersは空」は、相手が 1 件だけだと衝突自体が成立しない
    /// （2 件以上でなければ collisions に載らない）ため、`peers` 側の「自分がアクティブか」の
    /// 判定を消しても green のままだった。アクティブな相手を 2 件置いて、その分岐を実際に固定する。
    @Test func 終了済みセッションは他のアクティブ2件が衝突していてもpeersを持たない() {
        let dead = sid(), a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: dead, among: [
            ws(dead, "/tmp/phlox-ca/repo", active: false),
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo"),
        ])
        #expect(peers.isEmpty, "終了済みセッションが他者の衝突を自分のものとして拾っている")
    }

    @Test func 終了済みセッションは他セッションのpeersに数えられない() {
        let dead = sid(), a = sid(), b = sid()
        let peers = WorkspaceCollisionPolicy.peers(of: a, among: [
            ws(dead, "/tmp/phlox-ca/repo", active: false),
            ws(a, "/tmp/phlox-ca/repo"),
            ws(b, "/tmp/phlox-ca/repo"),
        ])
        #expect(peers == Set([b]))
    }
}
