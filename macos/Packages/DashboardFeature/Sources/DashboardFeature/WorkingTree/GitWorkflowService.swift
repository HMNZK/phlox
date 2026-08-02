import Foundation

/// commit / push / PR 作成の失敗理由（task-4 契約）。
///
/// **git の失敗出力を握りつぶさない**ことが契約の核心。`commandFailed` は実行した引数と
/// 出力（stdout+stderr）をそのまま保持し、UI がユーザーへ提示できるようにする。
public enum GitWorkflowError: Error, Equatable {
    case notARepository
    case noPathsSelected
    case emptyCommitMessage
    case noRemoteConfigured
    case gitHubCLIUnavailable
    case commandFailed(arguments: [String], output: String)
}

/// ワーキングツリーの変更を commit / push し、PR を作る（task-4 契約）。
///
/// 受け入れテスト `AcceptanceGitWorkflowTests` が凍結する。
/// **スタブ実装＝task-4 が本実装する。**
///
/// 読み取り専用の `WorkingTreeService` と対になる書き込み側。読み取りと書き込みを
/// 別サービスに分けているのは、`WorkingTreeService` が `--no-optional-locks` 前提の
/// 読み取り専用コマンドだけを扱う設計（ADR 0150）を保つため。
public actor GitWorkflowService {
    private let repositoryRoot: URL
    private let gitHubCLIPath: String?

    /// - Parameters:
    ///   - repositoryRoot: 対象リポジトリのルート。
    ///   - gitHubCLIPath: `gh` の絶対パス。`nil` なら PATH から探索する。
    ///     テストで不在時の挙動を決定的に再現するために注入可能にしてある。
    public init(repositoryRoot: URL, gitHubCLIPath: String? = nil) {
        self.repositoryRoot = repositoryRoot
        self.gitHubCLIPath = gitHubCLIPath
    }

    /// 指定したパスだけをステージしてコミットする。
    ///
    /// - Returns: 作成されたコミットの SHA。
    /// - Throws: `.noPathsSelected`（paths が空）/ `.emptyCommitMessage`（空白のみを含む）/
    ///   `.notARepository` / `.commandFailed`。
    /// - Note: **選択していないパスの変更はワーキングツリーに残る**（全ステージしない）。
    public func commit(paths: [String], message: String) async throws -> String {
        throw GitWorkflowError.notARepository
    }

    /// 設定済みリモート名の一覧。
    public func remoteNames() async -> [String] {
        []
    }

    /// 現在のブランチを push する。リモート未設定なら `.noRemoteConfigured`。
    public func push() async throws {
        throw GitWorkflowError.noRemoteConfigured
    }

    /// `gh` が利用可能か。
    public func isGitHubCLIAvailable() async -> Bool {
        false
    }

    /// PR を作成し、その URL を返す。`gh` が無ければ `.gitHubCLIUnavailable`。
    public func createPullRequest(title: String, body: String) async throws -> String {
        throw GitWorkflowError.gitHubCLIUnavailable
    }
}
