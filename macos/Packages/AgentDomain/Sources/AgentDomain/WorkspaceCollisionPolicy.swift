import Foundation

/// 衝突判定へ渡す、セッション 1 件分の作業ディレクトリ情報。
///
/// UI 層・spawn 層のどちらからも組み立てられるよう、`SessionID` と生パスだけを持つ
/// 純粋な値型にしてある（View や ViewModel に依存させない）。
public struct SessionWorkspace: Hashable, Sendable {
    public let sessionID: SessionID
    /// セッションが実際に動く作業ディレクトリ（`AgentLaunchPlan.workingDirectory` 相当の生パス）。
    public let workingDirectory: String
    /// 稼働中か。終了済みセッションは衝突の当事者から外す。
    public let isActive: Bool

    public init(sessionID: SessionID, workingDirectory: String, isActive: Bool) {
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.isActive = isActive
    }
}

/// 複数のアクティブセッションが同じ作業ディレクトリを共有しているかの判定（task-1 契約）。
///
/// 受け入れテスト `AcceptanceWorkspaceCollisionPolicyTests` が凍結する。
/// **スタブ実装＝task-1 が本実装する。**
///
/// 背景: ユーザーが追加した既存リポジトリ（`Project.isManagedDirectory == false`）では
/// `SessionSpawnService.shouldTrackOwnedWorkspace` が false を返し、そのプロジェクトの
/// 全セッションが同じ作業ツリーを共有する。検知も警告も無いため、並列実行時に
/// 互いのファイルを踏み合っても気付けない。
public enum WorkspaceCollisionPolicy {
    /// シンボリックリンク・`.` / `..`・重複スラッシュ・末尾スラッシュを解決した正準パス。
    ///
    /// 大文字小文字は**畳まない**。APFS は既定で大小無視だが case-sensitive ボリュームも
    /// 選べるため、無条件に畳むと別ディレクトリを同一と誤判定する。
    public static func canonicalPath(_ path: String) -> String {
        path
    }

    /// アクティブなセッションのうち、作業ディレクトリを共有している集合。
    ///
    /// - Returns: 正準パス → そのパスを共有するセッション集合。**2 件以上のものだけ**を含む。
    public static func collisions(among workspaces: [SessionWorkspace]) -> [String: Set<SessionID>] {
        [:]
    }

    /// 指定セッションが作業ディレクトリを共有している相手（自分自身は含まない）。
    public static func peers(of sessionID: SessionID, among workspaces: [SessionWorkspace]) -> Set<SessionID> {
        []
    }
}
