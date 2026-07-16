import Foundation

/// Codex セッション用の CWD 配下 `.codex/hooks.json` を生成・復元する。
/// command は dispatcher + kind のみ（Codex hook サブプロセスは親 env を継承する）。
public enum CodexHooksManager {
    public typealias Installation = HookInstallation
    public typealias InstallResult = HookFileInstallResult

    public static let backupFileName = HookFileInstaller.backupFileName

    public static func hooksFileURL(in workingDirectory: URL) -> URL {
        workingDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    /// hooks.json の各 command 文字列（dispatcher + kind。env 前置なし）。
    /// dispatcher は単一引用符で囲む。ビルド元パスがスペースを含む場合（worktree 等）に
    /// シェルがスペースで分割して失敗するのを防ぐため。
    public static func hookCommand(dispatcherPath: String, kind: String) -> String {
        "'\(dispatcherPath)' \(kind)"
    }

    /// Codex 用 hooks 設定の JSON オブジェクト（PreToolUse / PostToolUse / UserPromptSubmit / Stop）。
    public static func hooksSettings(dispatcherPath: String) -> [String: Any] {
        func eventCommand(_ kind: String) -> String {
            hookCommand(dispatcherPath: dispatcherPath, kind: kind)
        }

        func hookEntry(command: String) -> [[String: Any]] {
            [["matcher": "", "hooks": [["type": "command", "command": command]]]]
        }

        return [
            "hooks": [
                "Stop": hookEntry(command: eventCommand("stop")),
                "PreToolUse": hookEntry(command: eventCommand("preToolUse")),
                "PostToolUse": hookEntry(command: eventCommand("postToolUse")),
                "UserPromptSubmit": hookEntry(command: eventCommand("userPromptSubmit")),
            ]
        ]
    }

    /// ユーザー既存の `hooks.json` は上書きせずスキップする。アプリ設置済みの場合のみ上書きする。
    @discardableResult
    public static func install(
        workingDirectory: URL,
        dispatcherPath: String,
        fileManager: FileManager = .default
    ) throws -> InstallResult {
        let settings = hooksSettings(dispatcherPath: dispatcherPath)
        return try HookFileInstaller.install(
            directoryName: ".codex",
            settings: settings,
            dispatcherPath: dispatcherPath,
            in: workingDirectory,
            fileManager: fileManager
        )
    }

    /// 本アプリが生成した `hooks.json` のみ削除する（ユーザー既存ファイルは触らない）。
    public static func cleanup(
        _ installation: Installation,
        fileManager: FileManager = .default
    ) throws {
        try HookFileInstaller.cleanup(installation, fileManager: fileManager)
    }
}
