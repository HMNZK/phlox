import Foundation
import AgentDomain
import CodexAppServerKit
import SessionFeature

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

    typealias Runner = @Sendable (_ command: String, _ arguments: [String], _ env: [String: String], _ workingDirectory: String?) async -> String?

    nonisolated static func makeSpawnAgentModelsProvider(
        ref: AgentRef,
        command: String,
        env: [String: String],
        workingDirectory: String?,
        runner: @escaping Runner = CursorModelListProvider.runCursorModelList
    ) -> ChatSessionViewModel.SpawnAgentModelsProvider? {
        guard ref == .builtin(.cursor) else { return nil }
        return {
            guard let stdout = await runner(command, ["models"], env, workingDirectory) else { return [] }
            return CursorModelListProvider.parseCursorModelList(stdout)
        }
    }

    nonisolated static func parseCursorModelList(_ raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "Available models", let separator = line.range(of: " - ") else { return nil }
            let id = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
    }

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
                if let workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory) }
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
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
        CursorModelListProvider.makeSpawnAgentModelsProvider(ref: ref, command: command, env: env, workingDirectory: workingDirectory, runner: runner)
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
        await CursorModelListProvider.runCursorModelList(command: command, arguments: arguments, env: env, workingDirectory: workingDirectory)
    }

}
