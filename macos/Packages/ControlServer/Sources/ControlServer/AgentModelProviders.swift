import AgentDomain
import Foundation

/// Keeps CLI results out of the model-picker request path. Failed fetches are deliberately
/// not cached so the periodic background refresh can recover without restarting the application.
public actor CachingAgentModelProvider: AgentModelListProviding {
    private let source: any AgentModelListProviding
    private let ttl: TimeInterval
    private var entries: [AgentKind: (models: [ControlModelOption], fetchedAt: Date)] = [:]

    public init(source: any AgentModelListProviding, ttl: TimeInterval = 300) {
        self.source = source
        self.ttl = ttl
    }

    public func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        if let entry = entries[kind], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.models
        }
        let models = try await source.fetchModels(for: kind)
        entries[kind] = (models, Date())
        return models
    }
}

public enum ClaudeModelListParser {
    /// Extracts the comma-separated aliases in Claude's documented `/model` response.
    /// `default`, `opusplan`, and `[1m]` aliases are deliberately passed through: this
    /// output is the CLI's own offered set, and rejecting an unfamiliar alias would make
    /// a selectable model silently ineffective. The final prose alternative is excluded.
    public static func parse(resultText: String) -> [String] {
        guard let availableRange = resultText.range(of: "Available:"),
              let aliasesRange = resultText[availableRange.upperBound...].range(
                of: ", or a full model ID",
                options: [.caseInsensitive]
              )
        else { return [] }
        return resultText[availableRange.upperBound..<aliasesRange.lowerBound]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Parses the `cursor-agent models` text format. Keeping this pure parser separate from
/// process execution lets tests freeze the real CLI format while the provider owns I/O.
public enum CursorModelListParser {
    public static func parse(_ output: String) -> [String] {
        output.split(separator: "\n").compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != "Available models", let dash = text.range(of: " - ") else { return nil }
            let id = String(text[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
    }
}

/// The live source runs only from `AgentModelCatalog.refresh()` on a utility queue. Its
/// output is later exposed through a synchronous snapshot so request handlers never wait
/// for a subprocess.
public struct LiveAgentModelProvider: AgentModelListProviding {
    public let environment: [String: String]
    public let commands: [AgentKind: String]
    public let timeout: TimeInterval
    private let commandRunner: @Sendable (String, [String]) async throws -> String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commands: [AgentKind: String] = [:],
        timeout: TimeInterval = 8
    ) {
        let childEnvironment = Self.childEnvironment(base: environment)
        self.init(
            childEnvironment: childEnvironment,
            commands: commands,
            timeout: timeout,
            commandRunner: { command, arguments in
                try await Self.runCommand(command, arguments: arguments, environment: childEnvironment, timeout: timeout)
            }
        )
    }

    init(
        environment: [String: String],
        commands: [AgentKind: String] = [:],
        timeout: TimeInterval = 8,
        commandRunner: @escaping @Sendable (String, [String]) async throws -> String
    ) {
        self.init(childEnvironment: Self.childEnvironment(base: environment), commands: commands, timeout: timeout, commandRunner: commandRunner)
    }

    private init(
        childEnvironment: [String: String],
        commands: [AgentKind: String],
        timeout: TimeInterval,
        commandRunner: @escaping @Sendable (String, [String]) async throws -> String
    ) {
        self.environment = childEnvironment
        self.commands = commands
        self.timeout = timeout
        self.commandRunner = commandRunner
    }

    /// Build the deliberately small environment inherited by CLI children. `cursor-agent`
    /// is a `set -u` shell wrapper and requires HOME; USER and LANG retain normal identity
    /// and locale behaviour while PATH resolves binaries from a GUI-launched application.
    public static func childEnvironment(base: [String: String]) -> [String: String] {
        var child = base
        child["HOME"] = child["HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? NSHomeDirectory()
        child["USER"] = child["USER"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ProcessInfo.processInfo.environment["USER"]
            ?? NSUserName()
        child["LANG"] = child["LANG"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ProcessInfo.processInfo.environment["LANG"]
            ?? "en_US.UTF-8"
        return child
    }

    public func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        switch kind {
        case .claudeCode:
            let output = try await commandRunner(
                resolveCommand(for: kind),
                ["--bare", "-p", "/model", "--output-format", "json"]
            )
            guard let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                  let result = object["result"] as? String
            else { throw ProviderError.invalidOutput }
            let aliases = ClaudeModelListParser.parse(resultText: result)
            guard !aliases.isEmpty else { throw ProviderError.invalidOutput }
            return aliases.map(option)

        case .cursor:
            let output = try await commandRunner(resolveCommand(for: kind), ["models"])
            let ids = CursorModelListParser.parse(output)
            guard !ids.isEmpty else { throw ProviderError.invalidOutput }
            return ids.map(option)

        case .codex:
            return try await runCodexModelList(command: resolveCommand(for: kind))
        }
    }

    private func option(_ id: String) -> ControlModelOption {
        let names = ["opus": "Opus 4.8", "sonnet": "Sonnet 5", "fable": "Fable 5", "haiku": "Haiku 4.5"]
        return ControlModelOption(id: id, displayName: names[id] ?? id)
    }

    private func resolveCommand(for kind: AgentKind) -> String {
        if let configured = commands[kind], FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let name: String = switch kind {
        case .claudeCode: "claude"
        case .cursor: "cursor-agent"
        case .codex: "codex"
        }
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = pathEntries.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            + ["\(home)/.local/bin/\(name)", "\(home)/.npm-global/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? name
    }

    private static func runCommand(
        _ command: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.environment = environment
                let stdout = Pipe()
                process.standardOutput = stdout
                let stderr = Pipe()
                process.standardError = stderr
                let gate = CompletionGate<String>(continuation)
                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).async {
                        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        process.waitUntilExit()
                        gate.resume(process.terminationStatus == 0 ? .success(output) : .failure(ProviderError.commandFailed(errorOutput)))
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning { process.terminate() }
                        gate.resume(.failure(ProviderError.timedOut))
                    }
                } catch {
                    gate.resume(.failure(error))
                }
            }
        }
    }

    /// app-server is intentionally long-lived. Read JSON-RPC lines until `model/list`'s
    /// response arrives, then terminate it; waiting for EOF first would always hit timeout.
    private func runCodexModelList(command: String) async throws -> [ControlModelOption] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = ["app-server"]
                process.environment = environment
                let stdin = Pipe()
                let stdout = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                let gate = CompletionGate<[ControlModelOption]>(continuation)
                do {
                    try process.run()
                    let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"Phlox","version":"1"}}}"#
                    let list = #"{"id":2,"method":"model/list","params":{}}"#
                    try stdin.fileHandleForWriting.write(contentsOf: Data("\(initialize)\n\(list)\n".utf8))
                    DispatchQueue.global(qos: .utility).async {
                        while true {
                            let data = stdout.fileHandleForReading.availableData
                            guard !data.isEmpty else {
                                gate.resume(.failure(ProviderError.commandFailed("codex app-server closed stdout before model/list response")))
                                return
                            }
                            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                                      (object["id"] as? NSNumber)?.intValue == 2,
                                      let result = object["result"] as? [String: Any],
                                      let data = result["data"] as? [[String: Any]]
                                else { continue }
                                let models = data.compactMap { item -> ControlModelOption? in
                                    guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                                    return option(id)
                                }
                                if process.isRunning { process.terminate() }
                                gate.resume(models.isEmpty ? .failure(ProviderError.invalidOutput) : .success(models))
                                return
                            }
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning { process.terminate() }
                        gate.resume(.failure(ProviderError.timedOut))
                    }
                } catch {
                    gate.resume(.failure(error))
                }
            }
        }
    }

    private enum ProviderError: LocalizedError {
        case invalidOutput
        case commandFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidOutput: "CLI returned no usable model list"
            case let .commandFailed(stderr): "CLI exited unsuccessfully: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .timedOut: "CLI model-list request timed out"
            }
        }
    }
}

private final class CompletionGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Value, Error>

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: sending Result<Value, any Error>) {
        lock.withLock {
            guard !completed else { return }
            completed = true
            continuation.resume(with: result)
        }
    }
}
