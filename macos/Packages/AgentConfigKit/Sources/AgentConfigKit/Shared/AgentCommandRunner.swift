import Foundation

/// エージェント CLI（`claude` / `codex` / `cursor-agent`）を1回実行した結果。
public struct AgentCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }

    /// 失敗時に画面へ出す文言。stderr が空なら stdout を使う。
    public var failureMessage: String {
        let stderr = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        return "終了コード \(exitCode) で失敗しました。"
    }
}

public enum AgentCommandError: Error, LocalizedError, Equatable {
    /// CLI の実行ファイルが見つからない（引数はコマンド名）。
    case executableNotFound(String)
    case launchFailed(String, String)
    case failed(AgentCommandResult)
    case unreadableOutput(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let tool):
            return "\(tool) コマンドが見つかりません。"
        case .launchFailed(let tool, let reason):
            return "\(tool) の起動に失敗しました: \(reason)"
        case .failed(let result):
            return result.failureMessage
        case .unreadableOutput(let tool):
            return "\(tool) の出力を解釈できませんでした。"
        }
    }
}

/// エージェント CLI を実行する口。テストではダミー実装に差し替える。
public protocol AgentCommandRunning: Sendable {
    func run(_ arguments: [String]) async throws -> AgentCommandResult
}

public enum AgentCommandOutput {
    /// stdout の先頭に進捗行などが混ざっても JSON 本体だけ取り出す。
    /// 最初の `[` か `{` から末尾までを JSON とみなす。
    public static func jsonPayload(from output: String) -> Data? {
        guard let start = output.firstIndex(where: { $0 == "[" || $0 == "{" }) else { return nil }
        let payload = String(output[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : Data(payload.utf8)
    }
}

/// 実際に CLI プロセスを起動する実装。
public struct AgentProcessCommandRunner: AgentCommandRunning {
    private let toolName: String
    private let executablePath: String
    private let pathEnvironment: String
    private let workingDirectory: URL?

    public init(
        toolName: String,
        executablePath: String,
        pathEnvironment: String,
        workingDirectory: URL? = nil
    ) {
        self.toolName = toolName
        self.executablePath = executablePath
        self.pathEnvironment = pathEnvironment
        self.workingDirectory = workingDirectory
    }

    public func run(_ arguments: [String]) async throws -> AgentCommandResult {
        let toolName = toolName
        let executablePath = executablePath
        let pathEnvironment = pathEnvironment
        let workingDirectory = workingDirectory

        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                throw AgentCommandError.executableNotFound(toolName)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = pathEnvironment
            // 対話 UI を出させない（TTY 判定に頼る CLI があるため明示する）。
            environment["CI"] = "1"
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw AgentCommandError.launchFailed(toolName, error.localizedDescription)
            }

            // waitUntilExit より前に読み切る（パイプ満杯で子が固まるのを防ぐ）。
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return AgentCommandResult(
                exitCode: process.terminationStatus,
                standardOutput: String(data: outData, encoding: .utf8) ?? "",
                standardError: String(data: errData, encoding: .utf8) ?? ""
            )
        }.value
    }
}
