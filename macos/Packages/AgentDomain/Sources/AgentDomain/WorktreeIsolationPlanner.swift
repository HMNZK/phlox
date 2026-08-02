import Foundation

/// worktree 隔離を試みたが実施できなかった理由（task-2 契約）。
///
/// いずれの場合も**起動は中止する**。隔離できないまま共有ディレクトリで起動すると、
/// 隔離を有効にした意図（他セッションと踏み合わない）が黙って失われるため。
public enum WorktreeIsolationFailure: Equatable, Sendable {
    /// プロジェクトのディレクトリが git リポジトリではない。
    case notAGitRepository(path: String)
    /// 生成しようとしたブランチ名が既に存在する。
    case branchAlreadyExists(String)
    /// worktree を置こうとしたパスが既に使われている。
    case worktreePathOccupied(String)
}

/// spawn 時に worktree 隔離をどう扱うかの決定（task-2 契約）。
public enum WorktreeIsolationOutcome: Equatable, Sendable {
    /// 隔離しない。従来どおりの作業ディレクトリで起動する。
    case disabled
    /// この worktree を作って作業ディレクトリにする。
    case create(worktreePath: String, branchName: String)
    /// 起動を中止する。
    case abort(WorktreeIsolationFailure)
}

/// セッションごとの git worktree 隔離の計画（task-2 契約）。
///
/// 受け入れテスト `AcceptanceWorktreeIsolationTests` が凍結する。
/// **スタブ実装＝task-2 が本実装する。**
///
/// 副作用（`git worktree add` の実行・ディレクトリ作成）はここでは行わない。
/// 「何をすべきか」だけを純関数で決め、実行は `SessionSpawnService` 側が担う。
/// これにより、外部プロセスを起動せずに決定ロジックを検証できる。
public enum WorktreeIsolationPlanner {
    /// - Parameters:
    ///   - project: 対象プロジェクト。`nil`（プロジェクト未所属のセッション）は常に `.disabled`。
    ///   - sessionID: 起動するセッション。ブランチ名・worktree パスの一意性の根拠になる。
    ///   - sessionWorkspaceDirectory: `AppEnvironment.sessionWorkspaceDirectory(for:)` が返すパス。
    ///     worktree はここに作る。
    ///   - isGitRepository: `project.directoryPath` が git リポジトリか（呼び出し側が実測して渡す）。
    ///   - existingBranchNames: 既存のローカルブランチ名。
    ///   - worktreePathExists: `sessionWorkspaceDirectory` が既に存在するか。
    public static func plan(
        project: Project?,
        sessionID: SessionID,
        sessionWorkspaceDirectory: String,
        isGitRepository: Bool,
        existingBranchNames: Set<String>,
        worktreePathExists: Bool
    ) -> WorktreeIsolationOutcome {
        .disabled
    }

    /// セッションに割り当てるブランチ名。衝突を避けるため `SessionID` を含める。
    public static func branchName(for sessionID: SessionID) -> String {
        ""
    }
}
