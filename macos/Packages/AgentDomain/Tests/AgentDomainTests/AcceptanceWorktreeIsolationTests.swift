// 契約の正本: tasks/task-2.md — セッションごとの git worktree 隔離（オプトイン）。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約の核心は 2 つ:
//  (1) 既定（フラグ未設定＝旧 projects.json）は従来どおり。挙動を 1 行も変えない。
//  (2) 隔離できないときは **起動を中止する**。共有ディレクトリへ黙って落とさない
//      （ゲート①でユーザーが「起動を中止する」を選択。decision-log.md 参照）。

import Foundation
import Testing
@testable import AgentDomain

@Suite("Acceptance: worktree 隔離（task-2）")
struct AcceptanceWorktreeIsolationTests {
    private func makeProject(worktreeIsolationEnabled: Bool?) -> Project {
        Project(
            name: "sample",
            directoryPath: "/tmp/phlox-wt/repo",
            createdAt: Date(timeIntervalSince1970: 0),
            isManagedDirectory: false,
            worktreeIsolationEnabled: worktreeIsolationEnabled
        )
    }

    private let workspaceDir = "/tmp/phlox-wt/workspace/session"

    // MARK: - 旧スキーマ互換（R1: これを壊すとユーザーのプロジェクト一覧が消える）

    @Test func 旧スキーマのJSONがデコードでき隔離は無効になる() throws {
        // worktreeIsolationEnabled キーを持たない、実際に保存されている形の JSON。
        let json = """
        {
          "id": { "rawValue": "3F2504E0-4F89-11D3-9A0C-0305E82C3301" },
          "name": "legacy",
          "directoryPath": "/tmp/phlox-wt/legacy",
          "createdAt": 0,
          "isManagedDirectory": false
        }
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.worktreeIsolationEnabled == nil)
        #expect(project.usesWorktreeIsolation == false)
        #expect(project.name == "legacy")
    }

    @Test func 隔離フラグをつけた場合もエンコードとデコードで往復する() throws {
        let original = makeProject(worktreeIsolationEnabled: true)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Project.self, from: data)
        #expect(restored.usesWorktreeIsolation)
        #expect(restored == original)
    }

    // MARK: - 既定（off）は従来どおり

    @Test func フラグ未設定なら隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: nil),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    @Test func フラグがfalseなら隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: false),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    @Test func プロジェクト未所属のセッションは隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: nil,
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    // MARK: - on の正常系

    @Test func フラグがtrueでgitリポジトリなら専用worktreeを作る() {
        let sessionID = SessionID()
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        guard case let .create(worktreePath, branchName) = outcome else {
            Issue.record("期待は .create だが \(outcome) だった")
            return
        }
        #expect(worktreePath == workspaceDir)
        #expect(branchName == WorktreeIsolationPlanner.branchName(for: sessionID))
        #expect(!branchName.isEmpty)
    }

    @Test func ブランチ名はセッションごとに異なる() {
        let a = WorktreeIsolationPlanner.branchName(for: SessionID())
        let b = WorktreeIsolationPlanner.branchName(for: SessionID())
        #expect(a != b)
    }

    @Test func ブランチ名はgitのrefnameとして使える文字だけを含む() {
        let name = WorktreeIsolationPlanner.branchName(for: SessionID())
        #expect(!name.isEmpty)
        // git check-ref-format が拒否する代表的な文字・並びを含まないこと。
        for forbidden in [" ", "~", "^", ":", "?", "*", "[", "\\", "..", "@{", "//"] {
            #expect(!name.contains(forbidden), "ブランチ名に \(forbidden) が含まれている: \(name)")
        }
        #expect(!name.hasPrefix("/"))
        #expect(!name.hasSuffix("/"))
        #expect(!name.hasSuffix(".lock"))
    }

    // MARK: - on の失敗系（すべて中止。フォールバックしない）

    @Test func gitリポジトリでなければ起動を中止する() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: false,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .abort(.notAGitRepository(path: "/tmp/phlox-wt/repo")))
    }

    @Test func 同名ブランチが既にあれば起動を中止する() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [branch],
            worktreePathExists: false
        )
        #expect(outcome == .abort(.branchAlreadyExists(branch)))
    }

    @Test func worktreeパスが既に使われていれば起動を中止する() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: true
        )
        #expect(outcome == .abort(.worktreePathOccupied(workspaceDir)))
    }

    @Test func 失敗時に従来の共有ディレクトリへフォールバックしない() {
        // 隔離できない条件をすべて同時に与えても、.disabled（＝従来挙動で起動）にはならない。
        for (isRepo, branches, pathExists) in [
            (false, Set<String>(), false),
            (true, Set(["dummy"]), true),
            (false, Set<String>(), true),
        ] {
            let sessionID = SessionID()
            var branchSet = branches
            if branchSet.contains("dummy") {
                branchSet = [WorktreeIsolationPlanner.branchName(for: sessionID)]
            }
            let outcome = WorktreeIsolationPlanner.plan(
                project: makeProject(worktreeIsolationEnabled: true),
                sessionID: sessionID,
                sessionWorkspaceDirectory: workspaceDir,
                isGitRepository: isRepo,
                existingBranchNames: branchSet,
                worktreePathExists: pathExists
            )
            #expect(outcome != .disabled, "隔離失敗時に従来挙動へフォールバックしている: \(outcome)")
            if case .create = outcome {
                Issue.record("隔離できない条件なのに .create を返した: \(outcome)")
            }
        }
    }
}
