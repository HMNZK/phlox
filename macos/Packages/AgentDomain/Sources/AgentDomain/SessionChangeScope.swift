import Foundation

/// 変更一覧（Changes）が何を対象にしているか（task-3 契約）。
///
/// 競合製品は「セッション＝worktree」なので worktree の diff がそのままセッションの変更になるが、
/// Phlox は複数セッションが同じ作業ツリーを共有しうる。共有時は**変更をセッションへ帰属させられない**。
/// 帰属できないものを帰属できたように見せないため、その区別を値として持つ。
public enum SessionChangeScope: Equatable, Sendable {
    /// 表示対象なし（セッション未選択・作業ディレクトリ不明・git リポジトリ外）。
    case unavailable
    /// このセッションが単独で占有する作業ツリー。変更はこのセッションに帰属する。
    case isolated(repositoryRoot: String)
    /// 他のアクティブセッションと共有している作業ツリー。帰属は保証できない。
    /// `peerCount` は自分以外の共有セッション数。
    case shared(repositoryRoot: String, peerCount: Int)
}

public extension SessionChangeScope {
    /// 変更一覧に表示すべきリポジトリのルート。表示対象が無ければ `nil`。
    var repositoryRoot: String? {
        switch self {
        case .unavailable: nil
        case let .isolated(root): root
        case let .shared(root, _): root
        }
    }

    /// 変更をこのセッションに帰属させてよいか。false のとき UI は帰属不能を明示する。
    var attributesChangesToSession: Bool {
        if case .isolated = self { return true }
        return false
    }
}

/// 選択中セッションから、変更一覧の対象スコープを導く（task-3 契約）。
///
/// 受け入れテスト `AcceptanceSessionChangeScopeTests` が凍結する。
/// **スタブ実装＝task-3 が本実装する。**
public enum SessionChangeScopeResolver {
    /// - Parameters:
    ///   - selectedSessionID: 選択中のセッション。`nil` なら `.unavailable`。
    ///   - workspaces: アクティブ判定つきの全セッションの作業ディレクトリ。
    ///     共有判定は `WorkspaceCollisionPolicy.peers` に委ねる（規則の正本を 2 箇所に持たない）。
    ///   - repositoryRootProvider: 作業ディレクトリ → git リポジトリのルート。
    ///     リポジトリ外なら `nil` を返す（`git rev-parse --show-toplevel` 相当）。
    public static func resolve(
        selectedSessionID: SessionID?,
        workspaces: [SessionWorkspace],
        repositoryRootProvider: (String) -> String?
    ) -> SessionChangeScope {
        .unavailable
    }
}
