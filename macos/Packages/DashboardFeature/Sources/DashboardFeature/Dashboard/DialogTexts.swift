import AgentDomain
import DesignSystem
import Foundation

// 09 確認ダイアログとアラート: 見出しと本文の文言。表示言語で引くため、見出し（String が要る）は AppLocalizedString を通す。

/// D1: セッションを起動できなかったとき。
enum SpawnFailureDialogText {
    static func title(agentName: String, locale: Locale) -> String {
        String(format: AppLocalizedString.string("%@ を起動できませんでした", locale: locale), agentName)
    }

    /// 実行ファイルが見つからないときだけ、次の手として「エージェント管理を開く」を出す。
    static func opensAgentConsole(for error: Error) -> Bool {
        switch error as? AgentSpawnError {
        case .binaryNotFound, .customBinaryNotFound: true
        default: false
        }
    }

    static func agentName(for ref: AgentRef) -> String {
        switch ref {
        case .builtin(let kind): kind.displayName
        case .custom(let id): id
        }
    }
}

/// D2: セッション終了時の後始末で残ったもの。`WorkspaceCleanupWarning.title/message` は既存テストが固定しているので触らない。
enum CleanupWarningDialogText {
    static func title(_ warning: WorkspaceCleanupWarning, locale: Locale) -> String {
        AppLocalizedString.string(warning.title, locale: locale)
    }

    static func message(_ warning: WorkspaceCleanupWarning, locale: Locale) -> String {
        let ended = AppLocalizedString.string("セッションは終了しています。", locale: locale)
        switch warning {
        case .worktreeRetained:
            return ended + AppLocalizedString.string("worktree を削除できなかったため、次の場所に残しています。", locale: locale)
        case .branchRetained:
            return ended + AppLocalizedString.string("worktree は削除しましたが、次のブランチを削除できませんでした。", locale: locale)
        }
    }

    /// 本文の下に等幅で出す、残ったものの場所。
    static func detail(_ warning: WorkspaceCleanupWarning) -> String {
        switch warning {
        case .worktreeRetained(let path): (path as NSString).abbreviatingWithTildeInPath
        case .branchRetained(let branchName): branchName
        }
    }

    /// 「Finder で表示」で開く場所。ブランチは Finder で見られないので出さない。
    static func revealPath(_ warning: WorkspaceCleanupWarning) -> String? {
        if case .worktreeRetained(let path) = warning { return path }
        return nil
    }
}

/// D3: セッションの削除。巻き込まれる子セッションを名前と状態で並べる。
enum SessionDeletionDialogText {
    /// 一覧に並べる子セッションの上限。超えた分は件数だけ書く。
    static let listLimit = 6

    static func title(sessionName: String, childCount: Int, locale: Locale) -> String {
        if childCount > 0 {
            return String(format: AppLocalizedString.string("「%@」と子セッション %lld 件を削除しますか?", locale: locale), sessionName, childCount)
        }
        return String(format: AppLocalizedString.string("「%@」を削除しますか?", locale: locale), sessionName)
    }

    /// children: 子セッションの「名前 · 状態」。dirtyFiles: 保存していないファイル名。
    static func message(children: [String], dirtyFiles: [String], locale: Locale) -> String {
        var lines = [AppLocalizedString.string("実行中のエージェントは停止します。会話とターミナルの内容は元に戻せません。", locale: locale)]
        if !children.isEmpty {
            lines.append(children.prefix(listLimit).map { "・" + $0 }.joined(separator: "\n"))
            if children.count > listLimit {
                lines.append(String(format: AppLocalizedString.string("ほか %lld 件", locale: locale), children.count - listLimit))
            }
        }
        if !dirtyFiles.isEmpty {
            lines.append(String(format: AppLocalizedString.string("保存していないファイル（%@）の変更も失われます。", locale: locale), dirtyFiles.joined(separator: "、")))
        }
        lines.append(AppLocalizedString.string("プロジェクトのフォルダとファイルは削除されません。", locale: locale))
        return lines.joined(separator: "\n\n")
    }
}

/// D4: 文言は `ProjectDeletionDialogText`（テストで固定）と同じ。表示言語が日本語以外なら訳を引く。
extension ProjectDeletionDialogText {
    static func title(descendantCount: Int, locale: Locale) -> String {
        descendantCount > 0
            ? String(format: AppLocalizedString.string("このプロジェクトの削除で子孫%lld件も削除されますか?", locale: locale), descendantCount)
            : AppLocalizedString.string("このプロジェクトを削除しますか?", locale: locale)
    }

    static func message(descendantCount: Int, locale: Locale) -> String {
        descendantCount > 0
            ? String(format: AppLocalizedString.string("配下のセッションはすべて停止されます。この一覧に表示されていない子孫セッション%lld件も併せて削除されます。フォルダ自体は削除されません。", locale: locale), descendantCount)
            : AppLocalizedString.string("配下のセッションはすべて停止されます。フォルダ自体は削除されません。", locale: locale)
    }

    /// 固定の本文に続けて、消えるセッションの件数と取り返せないことを書く（09 D4）。
    static func irreversibleNote(sessionCount: Int, locale: Locale) -> String {
        String(format: AppLocalizedString.string("セッション %lld 件の会話とターミナルの内容は元に戻せません。", locale: locale), sessionCount)
    }
}
