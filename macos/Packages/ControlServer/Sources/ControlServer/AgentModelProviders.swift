import AgentDomain
import Darwin
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

    /// Extracts the product name from `/model`'s `Current model:` line, e.g.
    /// ``Current model: `Opus 5 (1M context)` (effort: xhigh)`` → `Opus 5 (1M context)`.
    /// The CLI wraps the name in Markdown backticks; they are stripped so the picker
    /// shows the bare product name.
    /// The alias list itself carries no version, so asking the CLI what a given alias
    /// resolves to is the only way to label a picker without hardcoding model versions.
    /// The trailing `(effort: …)` is the session's reasoning setting, not part of the name.
    public static func parseCurrentModelName(resultText: String) -> String? {
        guard let line = resultText.split(separator: "\n").first(where: { $0.contains("Current model:") }),
              let labelRange = line.range(of: "Current model:")
        else { return nil }
        var name = line[labelRange.upperBound...]
        if let effortRange = name.range(of: "(effort:", options: [.backwards, .caseInsensitive]) {
            name = name[..<effortRange.lowerBound]
        }
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "`")))
        return trimmed.isEmpty ? nil : trimmed
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
            let command = resolveCommand(for: kind)
            let aliases = ClaudeModelListParser.parse(
                resultText: try await claudeModelReport(command: command, alias: nil)
            )
            guard !aliases.isEmpty else { throw ProviderError.invalidOutput }
            let available = Set(aliases)
            let pickerModels = AgentModelCatalog.builtinModels(for: .claudeCode)
                .filter { available.contains($0.id) }
            guard !pickerModels.isEmpty else { throw ProviderError.invalidOutput }
            return await claudeOptions(command: command, pickerModels: pickerModels)

        case .cursor:
            let output = try await commandRunner(resolveCommand(for: kind), ["models"])
            let ids = CursorModelListParser.parse(output)
            guard !ids.isEmpty else { throw ProviderError.invalidOutput }
            return AgentModelCatalog.builtinModels(for: .cursor)

        case .codex:
            return try await runCodexModelList(command: resolveCommand(for: kind))
        }
    }

    private func option(_ id: String) -> ControlModelOption {
        ControlModelOption(id: id, displayName: id)
    }

    /// Runs `/model` and returns the CLI's report text. Without `--model` it reports the
    /// current selection plus the alias list; with `--model <alias>` it reports what that
    /// alias resolves to for this invocation only (the persisted selection is untouched).
    private func claudeModelReport(command: String, alias: String?) async throws -> String {
        let selection = alias.map { ["--model", $0] } ?? []
        let output = try await commandRunner(
            command,
            ["--bare"] + selection + ["-p", "/model", "--output-format", "json"]
        )
        guard let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let result = object["result"] as? String
        else { throw ProviderError.invalidOutput }
        return result
    }

    /// Resolves the five entries shown by Claude's interactive `/model` picker. Lookups run
    /// concurrently; a failed lookup keeps the dated built-in label rather than dropping a row.
    private func claudeOptions(command: String, pickerModels: [ControlModelOption]) async -> [ControlModelOption] {
        await withTaskGroup(of: (offset: Int, option: ControlModelOption).self) { group in
            for (offset, option) in pickerModels.enumerated() {
                group.addTask {
                    let report = try? await claudeModelReport(command: command, alias: option.id)
                    guard let name = report.flatMap({ ClaudeModelListParser.parseCurrentModelName(resultText: $0) }) else {
                        return (offset, option)
                    }
                    let displayName = option.id == "default" ? option.displayName : name
                    return (offset, ControlModelOption(id: option.id, displayName: displayName))
                }
            }
            var items: [(offset: Int, option: ControlModelOption)] = []
            for await item in group { items.append(item) }
            return items.sorted { $0.offset < $1.offset }.map(\.option)
        }
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

    private static func prepareModelWorkingDirectory(environment: [String: String]) throws -> URL {
        var locatorEnvironment = environment
        if locatorEnvironment["PHLOX_DATA_DIR"]?.isEmpty != false {
            locatorEnvironment["PHLOX_DATA_DIR"] = ProcessInfo.processInfo.environment["PHLOX_DATA_DIR"]
        }
        let directory = try AppSupportLocator.appSupportDirectoryURL(environment: locatorEnvironment)
            .appendingPathComponent("model-catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func runCommand(
        _ command: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    func posixError(_ code: Int32) -> NSError {
                        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                    }
                    func check(_ code: Int32) throws {
                        if code != 0 { throw posixError(code) }
                    }
                    let executable = URL(fileURLWithPath: command).path
                    let directory = try Self.prepareModelWorkingDirectory(environment: environment)
                    // Foundation rejects missing/non-executable paths before spawning; failures
                    // such as a missing shebang interpreter instead retain their POSIX error.
                    guard FileManager.default.isExecutableFile(atPath: executable) else {
                        throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                                      userInfo: [NSFilePathErrorKey: executable])
                    }

                    let inheritInput = fcntl(STDIN_FILENO, F_GETFD) != -1
                    if !inheritInput && errno != EBADF { try check(errno) }
                    var descriptors: [Int32] = []
                    defer { for fd in descriptors where fd >= 0 { Darwin.close(fd) } }
                    for _ in 0..<2 {
                        var pair: [Int32] = [-1, -1]
                        guard pipe(&pair) == 0 else { throw posixError(errno) }
                        defer { for fd in pair { Darwin.close(fd) } }
                        // Keep sources above stdio even if the host has closed fd 0, 1 or 2.
                        for fd in pair {
                            let copy = fcntl(fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                            guard copy >= 0 else { throw posixError(errno) }
                            descriptors.append(copy)
                        }
                    }
                    for index in [0, 2] {
                        let flags = fcntl(descriptors[index], F_GETFL)
                        guard flags >= 0 else { throw posixError(errno) }
                        if fcntl(descriptors[index], F_SETFL, flags | O_NONBLOCK) == -1 { try check(errno) }
                    }

                    var actions: posix_spawn_file_actions_t?
                    try check(posix_spawn_file_actions_init(&actions))
                    defer { posix_spawn_file_actions_destroy(&actions) }
                    try check(posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO))
                    try check(posix_spawn_file_actions_adddup2(&actions, descriptors[3], STDERR_FILENO))
                    if inheritInput { try check(posix_spawn_file_actions_addinherit_np(&actions, STDIN_FILENO)) }
                    try check(directory.path.withCString { posix_spawn_file_actions_addchdir_np(&actions, $0) })
                    var attributes: posix_spawnattr_t?
                    try check(posix_spawnattr_init(&attributes))
                    defer { posix_spawnattr_destroy(&attributes) }
                    var defaults = sigset_t()
                    sigfillset(&defaults)
                    try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
                    var mask = sigset_t()
                    sigemptyset(&mask)
                    try check(posix_spawnattr_setsigmask(&attributes, &mask))
                    try check(posix_spawnattr_setflags(&attributes, Int16(
                        POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
                    )))
                    var argv = ([executable] + arguments).map { strdup($0) }
                    var envp = environment.map { strdup("\($0.key)=\($0.value)") }
                    defer { for pointer in argv + envp { free(pointer) } }
                    guard (argv + envp).allSatisfy({ $0 != nil }) else {
                        throw posixError(ENOMEM)
                    }
                    argv.append(nil)
                    envp.append(nil)
                    var pid: pid_t = 0
                    try check(posix_spawn(&pid, executable, &actions, &attributes, &argv, &envp))

                    // This worker is the only waiter and signal sender. Until it reaps, the
                    // child (including a zombie) reserves its PID; Foundation never owns it.
                    var unreaped = true
                    var status: Int32 = 0
                    func reap(_ options: Int32) throws {
                        guard unreaped else { return }
                        var result: pid_t
                        repeat { result = waitpid(pid, &status, options) } while result == -1 && errno == EINTR
                        if result == pid { unreaped = false }
                        if result == -1 {
                            let code = errno
                            if code == ECHILD { unreaped = false }
                            try check(code)
                        }
                    }
                    do {
                        for index in [1, 3] {
                            let fd = descriptors[index]
                            descriptors[index] = -1
                            if Darwin.close(fd) == -1 { try check(errno) }
                        }
                        let deadline = DispatchTime.now() + timeout
                        var readers = [0, 2].map { pollfd(fd: descriptors[$0], events: Int16(POLLIN), revents: 0) }
                        var output = [Data(), Data()]
                        var buffer = [UInt8](repeating: 0, count: 65536)
                        while true {
                            try reap(WNOHANG)
                            // EOF alone is insufficient: the child can close both pipes and
                            // later exit unsuccessfully. Conversely, descendants can hold EOF open.
                            if !unreaped && readers.allSatisfy({ $0.fd == -1 }) {
                                guard status == 0 else {
                                    throw ProviderError.commandFailed(String(decoding: output[1], as: UTF8.self))
                                }
                                return String(decoding: output[0], as: UTF8.self)
                            }
                            guard DispatchTime.now() < deadline else { throw ProviderError.timedOut }
                            // Bound each read so a continuously busy pipe cannot starve its peer
                            // or the deadline. poll also waits when both EOFs precede child exit.
                            // ponytail: one worker per CLI; use event sources if fan-out grows.
                            let ready = poll(&readers, nfds_t(readers.count), 10)
                            if ready == -1 {
                                if errno == EINTR { continue }
                                try check(errno)
                            }
                            for index in readers.indices where readers[index].fd >= 0 && readers[index].revents != 0 {
                                let count = Darwin.read(readers[index].fd, &buffer, buffer.count)
                                if count > 0 { output[index].append(contentsOf: buffer.prefix(count)) }
                                else if count == 0 { readers[index].fd = -1 }
                                else if errno != EINTR && errno != EAGAIN { try check(errno) }
                            }
                        }
                    } catch {
                        try reap(WNOHANG)
                        if unreaped {
                            // No TERM grace/timer is needed for this read-only request. SIGKILL
                            // also handles TERM-ignoring children; never signal a group or a reaped PID.
                            if Darwin.kill(pid, SIGKILL) == -1 && errno != ESRCH { try check(errno) }
                            try reap(0)
                        }
                        throw error
                    }
                })
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
                    process.currentDirectoryURL = try Self.prepareModelWorkingDirectory(environment: environment)
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
