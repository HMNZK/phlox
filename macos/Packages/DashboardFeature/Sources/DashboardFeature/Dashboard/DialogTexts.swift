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
/// 見出しは C 型の規則どおり起きたことを言い切る（09 D2「一時ファイルを片付けられませんでした」の形）。
enum CleanupWarningDialogText {
    static func title(_ warning: WorkspaceCleanupWarning, locale: Locale) -> String {
        switch warning {
        case .worktreeRetained: AppLocalizedString.string("worktree を片付けられませんでした", locale: locale)
        case .branchRetained: AppLocalizedString.string("ブランチを片付けられませんでした", locale: locale)
        }
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

    static func message(locale: Locale) -> String {
        AppLocalizedString.string("実行中のエージェントは停止します。会話とターミナルの内容は元に戻せません。", locale: locale)
    }

    /// 巻き込まれる子セッションの表の行（名前と「Cx · 実行中」）。上限を超えた分は「ほか n 件」の 1 行にする。
    static func rows(children: [(name: String, meta: String)], locale: Locale) -> [DSDialogList.Row] {
        var rows = children.prefix(listLimit).enumerated().map { DSDialogList.Row(id: $0.offset, title: $0.element.name, meta: $0.element.meta) }
        if children.count > listLimit {
            rows.append(DSDialogList.Row(
                id: listLimit,
                title: String(format: AppLocalizedString.string("ほか %lld 件", locale: locale), children.count - listLimit),
                meta: ""
            ))
        }
        return rows
    }

    /// 表の下の注記。保存していないファイルがあれば先に書き、最後は「フォルダとファイルは削除されません」。
    static func note(dirtyFiles: [String], locale: Locale) -> String {
        var lines: [String] = []
        if !dirtyFiles.isEmpty {
            lines.append(String(format: AppLocalizedString.string("保存していないファイル（%@）の変更も失われます。", locale: locale), dirtyFiles.joined(separator: "、")))
        }
        lines.append(AppLocalizedString.string("プロジェクトのフォルダとファイルは削除されません。", locale: locale))
        return lines.joined(separator: "\n")
    }
}

/// D4: 文言は `ProjectDeletionDialogText`（テストで固定）と同じ。表示言語が日本語以外なら訳を引く。
extension ProjectDeletionDialogText {
    static func title(projectName: String, locale: Locale) -> String {
        String(format: AppLocalizedString.string("プロジェクト「%@」を削除しますか?", locale: locale), projectName)
    }

    static func message(sessionCount: Int, childCount: Int, otherProjectChildCount: Int = 0, locale: Locale) -> String {
        let (format, args) = messageFormat(sessionCount: sessionCount, childCount: childCount, otherProjectChildCount: otherProjectChildCount)
        return String(format: AppLocalizedString.string(format, locale: locale), arguments: args)
    }

    static func note(folderPath: String, locale: Locale) -> String {
        String(format: AppLocalizedString.string("フォルダ「%@」とその中のファイルは削除されません。", locale: locale), folderPath)
    }
}
