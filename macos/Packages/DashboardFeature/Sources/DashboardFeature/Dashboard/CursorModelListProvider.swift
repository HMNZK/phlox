import Foundation
import AgentDomain
import CodexAppServerKit
import SessionFeature

// 隠している秘密: cursor-agent models の起動・stdout パース・ChatSessionViewModel への provider 化。

enum CursorModelListProvider {
    static func persistedSettings(from lastUsed: LastUsedChatSettings?) -> CodexAppServerSessionSettings? {
        guard let lastUsed else { return nil }
        return CodexAppServerSessionSettings(
            selectedModel: lastUsed.model,
            selectedEffort: lastUsed.effort,
            selectedPermissionProfile: nil,
            isPlanMode: false
        )
    }

    /// `cursor-agent models` の stdout を実行して返す実行体。成功時は stdout、
    /// 失敗（非0終了・起動不可・例外）時は `nil` を返す（throw しない）。
    /// テストではモックへ差し替え、実 `cursor-agent` を単体テストで起動しない。
    typealias Runner = @Sendable (
        _ command: String,
        _ arguments: [String],
        _ env: [String: String],
        _ workingDirectory: String?
    ) async -> String?

    /// Cursor セッションのときだけ `spawnAgentModelsProvider` を生成する。
    /// Claude/Codex では `nil`（task-10 のデフォルト挙動に委ねる）。
    /// 取得失敗・空出力は throw せず空配列を返し、ChatSessionViewModel 側の fallback に委ねる。
    nonisolated static func makeSpawnAgentModelsProvider(
        ref: AgentRef,
        command: String,
        env: [String: String],
        workingDirectory: String?,
        runner: @escaping Runner = CursorModelListProvider.runCursorModelList
    ) -> ChatSessionViewModel.SpawnAgentModelsProvider? {
        guard ref == .builtin(.cursor) else { return nil }
        return {
            guard let stdout = await runner(command, ["models"], env, workingDirectory) else {
                return []
            }
            return CursorModelListProvider.parseCursorModelList(stdout)
        }
    }

    /// `cursor-agent models` の出力をパースして model ID 配列を返す純関数。
    /// 各行は `<modelId> - <表示名>`。ヘッダ `Available models`・空行・区切り(` - `)無しの
    /// 不正行は除外し、model ID は行頭〜最初の ` - ` までを取り出す。
    nonisolated static func parseCursorModelList(_ raw: String) -> [String] {
        var ids: [String] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "Available models" { continue }
            guard let separator = line.range(of: " - ") else { continue }
            let id = String(line[line.startIndex..<separator.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if id.isEmpty { continue }
            ids.append(id)
        }
        return ids
    }

    /// production 用の実行体。`command arguments...` を起動し stdout を返す。
    /// 非0終了・起動失敗・例外は `nil`。実 `cursor-agent` を起動するためテストからは呼ばない。
    nonisolated static func runCursorModelList(
        command: String,
        arguments: [String],
        env: [String: String],
        workingDirectory: String?
    ) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.environment = env.isEmpty ? nil : env
                if let workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                }
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension DashboardViewModel {
    typealias CursorModelListRunner = CursorModelListProvider.Runner

    static func persistedSettings(from lastUsed: LastUsedChatSettings?) -> CodexAppServerSessionSettings? {
        CursorModelListProvider.persistedSettings(from: lastUsed)
    }

    nonisolated static func makeSpawnAgentModelsProvider(
        ref: AgentRef,
        command: String,
        env: [String: String],
        workingDirectory: String?,
        runner: @escaping CursorModelListRunner = CursorModelListProvider.runCursorModelList
    ) -> ChatSessionViewModel.SpawnAgentModelsProvider? {
        CursorModelListProvider.makeSpawnAgentModelsProvider(
            ref: ref,
            command: command,
            env: env,
            workingDirectory: workingDirectory,
            runner: runner
        )
    }

    nonisolated static func parseCursorModelList(_ raw: String) -> [String] {
        CursorModelListProvider.parseCursorModelList(raw)
    }

    nonisolated static func runCursorModelList(
        command: String,
        arguments: [String],
        env: [String: String],
        workingDirectory: String?
    ) async -> String? {
        await CursorModelListProvider.runCursorModelList(
            command: command,
            arguments: arguments,
            env: env,
            workingDirectory: workingDirectory
        )
    }
}
