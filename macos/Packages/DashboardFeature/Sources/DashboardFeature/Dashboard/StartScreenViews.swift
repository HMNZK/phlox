import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

// MARK: - 起動前の確認（F1・F4）

/// 新規セッションの起動要求。確認のあとに同じ内容で起動し直すために持つ。
struct NewSessionRequest: Equatable {
    let ref: AgentRef
    let projectID: ProjectID
    let backend: SessionBackend
}

/// 起動前・起動失敗時に出す確認（08 F1・F4）。
enum SpawnGuard: Identifiable {
    /// worktree を作れず起動を中止した。
    /// `existingWorktree` は 09 E4「既存の worktree を使う」で使える、このリポジトリの worktree の場所（無ければ nil）。
    case worktreeFailed(NewSessionRequest, agentName: String, log: String, existingWorktree: String?)

    var id: String {
        switch self {
        case .worktreeFailed: "worktreeFailed"
        }
    }
}

enum NewSessionCollisionGate {
    /// worktree の失敗として確認に出す内容。git の出力があればそれを、無ければ理由の文を出す。
    static func worktreeFailureLog(_ error: Error) -> String? {
        guard let error = error as? WorktreeIsolationSpawnError else { return nil }
        if case .worktreeCreationFailed(_, _, let detail) = error, !detail.isEmpty {
            return detail
        }
        return error.localizedDescription
    }

    /// git の出力が「そのブランチは既存の worktree で使われている」と言っていれば、その worktree の場所（09 E4「既存の worktree を使う」）。
    /// 出力から場所を確かめられないとき・その場所がいまこのリポジトリの作業ツリーとして働いていないときは nil（ボタンを出さない）。
    static func existingWorktree(in log: String, repository: URL) async -> String? {
        let pattern = #"(?:already checked out at|already used by worktree at) '([^']+)'"#
        guard let match = log.range(of: pattern, options: .regularExpression) else { return nil }
        let quoted = log[match].split(separator: "'", omittingEmptySubsequences: false)
        guard quoted.count >= 2 else { return nil }
        let path = (String(quoted[quoted.count - 2]) as NSString).expandingTildeInPath
        guard await WorktreeIsolationGit.isWorkingTree(URL(fileURLWithPath: path, isDirectory: true), of: repository) else {
            return nil
        }
        return path
    }
}

struct SpawnGuardSheet: View {
    let spawnGuard: SpawnGuard
    let onCancel: () -> Void
    /// 起動する。true = worktree で分ける、false = 分けない。
    let onLaunch: (Bool) -> Void
    /// 既存の worktree（パス）で起動する。
    let onUseWorktree: (String) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        switch spawnGuard {
        case .worktreeFailed(_, _, let log, let existingWorktree):
            // 09 E4: お知らせの型。「閉じる」が既定、次の手の「隔離なしで起動」を先に置く。
            DSDialog(
                .notice,
                title: title,
                message: message,
                buttons: [DSDialogButton("隔離なしで起動") { onLaunch(false) }]
                    + (existingWorktree.map { path in
                        [DSDialogButton("既存の worktree を使う") { onUseWorktree(path) }]
                    } ?? [])
                    + [DSDialogButton("閉じる", role: .primary, action: onCancel)],
                onCancel: onCancel
            ) {
                DSDialogLog(log)
            }
        }
    }

    private var title: String {
        switch spawnGuard {
        case .worktreeFailed:
            AppLocalizedString.string("worktree を作成できなかったため、起動を中止しました", locale: locale)
        }
    }

    private var message: String {
        switch spawnGuard {
        case .worktreeFailed(_, let agentName, _, _):
            String(format: AppLocalizedString.string("%@ の新しいセッションは起動していません。", locale: locale), agentName)
        }
    }

}
