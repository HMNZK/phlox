import Foundation
import AgentDomain

/// Cursor セッション用の CWD 配下 `.cursor/hooks.json` を生成・復元する。
/// command は dispatcher + kind のみ（Cursor hook サブプロセスは親 env を継承する）。
public enum CursorHooksManager {
    public typealias Installation = HookInstallation
    public typealias InstallResult = HookFileInstallResult

    public static let backupFileName = HookFileInstaller.backupFileName

    public static func hooksFileURL(in workingDirectory: URL) -> URL {
        workingDirectory
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    /// hooks.json の各 command 文字列（dispatcher + kind。env 前置なし）。
    /// dispatcher は単一引用符で囲む。ビルド元パスがスペースを含む場合（worktree 等）に
    /// シェルがスペースで分割して失敗するのを防ぐため。
    public static func hookCommand(dispatcherPath: String, kind: String) -> String {
        "'\(dispatcherPath)' \(kind)"
    }

    /// Cursor 用 hooks 設定の JSON オブジェクト（version 1 + beforeShellExecution 等）。
    public static func hooksSettings(dispatcherPath: String) -> [String: Any] {
        func eventCommand(_ kind: String) -> String {
            hookCommand(dispatcherPath: dispatcherPath, kind: kind)
        }

        return [
            "version": 1,
            "hooks": [
                "beforeShellExecution": [["command": eventCommand("preToolUse")]],
                "afterShellExecution": [["command": eventCommand("postToolUse")]],
                "beforeSubmitPrompt": [["command": eventCommand("userPromptSubmit")]],
                "stop": [["command": eventCommand("stop")]],
            ],
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
            directoryName: ".cursor",
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
