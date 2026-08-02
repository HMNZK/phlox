// 契約の正本: tasks/task-3.md — 変更一覧をセッションスコープにする。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 現状: 変更一覧は `WorkingTreeService(repositoryRoot: project.directoryURL)` でプロジェクト単位に
// 固定されており（DashboardView.updateEditorPanelProject）、どのセッションの変更かを判別できない。
// 契約: 選択セッションの作業ディレクトリを基準にし、他セッションと共有していて帰属を保証できない
// 場合は、それを **値として区別して返す**（帰属できないものを帰属できたように見せない）。
//
// 注: 共有判定は WorkspaceCollisionPolicy（task-1）に委ねる契約なので、
// 本スイートは task-1 の実装完了を前提に green になる。

import Foundation
import Testing
@testable import AgentDomain

@Suite("Acceptance: SessionChangeScope（task-3）")
struct AcceptanceSessionChangeScopeTests {
    private func ws(_ id: SessionID, _ dir: String, active: Bool = true) -> SessionWorkspace {
        SessionWorkspace(sessionID: id, workingDirectory: dir, isActive: active)
    }

    /// 与えたパスがすべて同じリポジトリのサブディレクトリである、という前提の provider。
    private func rootProvider(_ root: String) -> (String) -> String? {
        { path in path.hasPrefix(root) ? root : nil }
    }

    // MARK: - 表示対象なし

    @Test func セッション未選択なら対象なし() {
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: nil,
            workspaces: [ws(SessionID(), "/tmp/phlox-scope/repo")],
            repositoryRootProvider: rootProvider("/tmp/phlox-scope/repo")
        )
        #expect(scope == .unavailable)
        #expect(scope.repositoryRoot == nil)
        #expect(!scope.attributesChangesToSession)
    }

    @Test func 一覧に無いセッションを選んでいたら対象なし() {
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: SessionID(),
            workspaces: [ws(SessionID(), "/tmp/phlox-scope/repo")],
            repositoryRootProvider: rootProvider("/tmp/phlox-scope/repo")
        )
        #expect(scope == .unavailable)
    }

    @Test func gitリポジトリ外の作業ディレクトリなら対象なし() {
        let a = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [ws(a, "/tmp/phlox-scope/not-a-repo")],
            repositoryRootProvider: { _ in nil }
        )
        #expect(scope == .unavailable)
    }

    // MARK: - 単独占有（帰属できる）

    @Test func 単独占有ならセッションへ帰属する() {
        let a = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [
                ws(a, "/tmp/phlox-scope/wt-a"),
                ws(SessionID(), "/tmp/phlox-scope/wt-b"),
            ],
            repositoryRootProvider: { path in path }
        )
        #expect(scope == .isolated(repositoryRoot: "/tmp/phlox-scope/wt-a"))
        #expect(scope.attributesChangesToSession)
        #expect(scope.repositoryRoot == "/tmp/phlox-scope/wt-a")
    }

    @Test func リポジトリルートは作業ディレクトリそのものではなくproviderの返す値を使う() {
        let a = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [ws(a, "/tmp/phlox-scope/repo/packages/sub")],
            repositoryRootProvider: rootProvider("/tmp/phlox-scope/repo")
        )
        #expect(scope == .isolated(repositoryRoot: "/tmp/phlox-scope/repo"))
    }

    // MARK: - 共有（帰属できない）

    @Test func 他セッションと共有していれば帰属不能として返す() {
        let a = SessionID(), b = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [
                ws(a, "/tmp/phlox-scope/repo"),
                ws(b, "/tmp/phlox-scope/repo"),
            ],
            repositoryRootProvider: { path in path }
        )
        #expect(scope == .shared(repositoryRoot: "/tmp/phlox-scope/repo", peerCount: 1))
        #expect(!scope.attributesChangesToSession)
        // 帰属できなくても、表示対象のリポジトリ自体は返す（現行機能を後退させない）。
        #expect(scope.repositoryRoot == "/tmp/phlox-scope/repo")
    }

    @Test func 共有相手が2件ならpeerCountは2() {
        let a = SessionID(), b = SessionID(), c = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [
                ws(a, "/tmp/phlox-scope/repo"),
                ws(b, "/tmp/phlox-scope/repo"),
                ws(c, "/tmp/phlox-scope/repo"),
            ],
            repositoryRootProvider: { path in path }
        )
        #expect(scope == .shared(repositoryRoot: "/tmp/phlox-scope/repo", peerCount: 2))
    }

    @Test func 終了済みセッションは共有相手に数えない() {
        let a = SessionID(), b = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [
                ws(a, "/tmp/phlox-scope/repo"),
                ws(b, "/tmp/phlox-scope/repo", active: false),
            ],
            repositoryRootProvider: { path in path }
        )
        #expect(scope == .isolated(repositoryRoot: "/tmp/phlox-scope/repo"))
    }

    @Test func 末尾スラッシュ違いでも共有として扱う() {
        let a = SessionID(), b = SessionID()
        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: a,
            workspaces: [
                ws(a, "/tmp/phlox-scope/repo"),
                ws(b, "/tmp/phlox-scope/repo/"),
            ],
            repositoryRootProvider: { path in path }
        )
        #expect(!scope.attributesChangesToSession, "末尾スラッシュ違いを別ディレクトリと誤判定している")
    }
}
