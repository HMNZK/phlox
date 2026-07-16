import Foundation
import StructuredChatKit

public enum ClaudeChatClientError: Error, Equatable, Sendable {
    case notStarted
    case transportClosed
    case usageRequestTimedOut
    case malformedUsageResponse
    case usageRequestFailed(String)
}

public actor ClaudeChatClient: StructuredAgentClient {
    enum SpawnSessionArgument: Equatable {
        case none
        case sessionId(String)
        case resume(String)
    }

    struct PendingResultError {
        var message: String
        var resumeSessionId: String?
    }

    struct InterruptedResultSuppression {
        var generation: Int
    }

    struct PendingUsageRequest {
        var continuation: CheckedContinuation<AgentRateLimitsSnapshot, Error>
        var generation: Int
        var timeoutTask: Task<Void, Never>?
    }

    public struct PreApprovalRequest: Equatable, Sendable {
        public let summary: String
        public let workingDirectory: String?

        public init(summary: String, workingDirectory: String?) {
            self.summary = summary
            self.workingDirectory = workingDirectory
        }
    }

    public enum PreApprovalDecision: Equatable, Sendable {
        case approve
        case deny(String)
    }

    public typealias PreApprovalPolicy = @Sendable (PreApprovalRequest) async -> PreApprovalDecision

    public typealias TransportFactory = @Sendable (
        _ command: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ workingDirectory: URL?
    ) -> any LineDelimitedTransport

    public static let defaultAllowedTools = [
        "Bash",
        "Read",
        "Glob",
        "Grep",
        "LS",
        "Edit",
        "Write",
        "MultiEdit",
    ]
    public static let preApprovedPermissionMode = "acceptEdits"

    let command: String
    let workingDirectory: URL?
    let environment: [String: String]
    let allowedTools: [String]
    let phloxSessionID: String?
    private let preApprovalPolicy: PreApprovalPolicy?
    let transportFactory: TransportFactory
    let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    public nonisolated let events: AsyncStream<NormalizedChatEvent>
    var transport: (any LineDelimitedTransport)?
    var receiveTask: Task<Void, Never>?
    var currentSessionId: String?
    var currentTurnOpen = false
    var generatedItemCounter = 0
    var toolUseItemIds: [String: String] = [:]
    var subAgentToolUseIds: Set<String> = []
    var backgroundSubAgentToolUseIds: Set<String> = []
    var emittedSubAgentStarts: Set<String> = []
    var currentModel: String?
    var currentPermissionMode: String?
    var currentEffort: String?
    private var settingsDirty = false
    /// Writes: initialized here; incremented only by `spawn(sessionArgument:)`
    /// after a new transport starts and before receive-loop generation capture.
    var spawnGeneration = 0
    var activeSpawnArgument: SpawnSessionArgument = .none
    var callerResumedSession = false
    var observedExistingConversation = false
    var currentTurnLine: Data?
    var pendingResultError: PendingResultError?
    /// Writes: initialized here; reset by `turnStart(_:)` before sending a turn;
    /// incremented only by `recordSelfHealAttemptIfTurnBound()`.
    var currentTurnHealCount = 0
    /// Writes: initialized here; cleared by `resetConversation()`,
    /// `spawn(sessionArgument:)`, and `handleResultEvent(_:generation:)` after
    /// absorption; armed only by `interrupt()` with the current `spawnGeneration`.
    var interruptedResultSuppression: InterruptedResultSuppression?
    var nextUsageRequestID = 1
    var pendingUsageRequests: [String: PendingUsageRequest] = [:]
    /// get_usage 応答待ちの内部タイムアウト（契約: 15 秒以下・テスト注入可能）。
    /// 実 CLI はターン処理中でも control_response を即応するが（2026-07-10 実測）、
    /// 重負荷時の余裕を見て既定 10 秒にする。
    var usageRequestTimeout: Duration = .seconds(10)

    /// テスト専用: get_usage の内部タイムアウトを注入する（actor 隔離のため setter を関数で公開）。
    func setUsageRequestTimeoutForTesting(_ timeout: Duration) {
        usageRequestTimeout = timeout
    }

    public init(
        command: String,
        workingDirectory: String?,
        environment: [String: String],
        permissionMode: String? = nil,
        model: String? = nil,
        allowedTools: [String] = [],
        phloxSessionID: String? = nil,
        preApprovalPolicy: PreApprovalPolicy? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory.map { URL(fileURLWithPath: $0) }
        self.environment = environment
        self.currentModel = model
        self.currentPermissionMode = Self.resolvedPermissionMode(permissionMode, preApprovalPolicy: preApprovalPolicy)
        self.allowedTools = Self.resolvedAllowedTools(allowedTools, preApprovalPolicy: preApprovalPolicy)
        self.phloxSessionID = Self.resolvePhloxSessionID(explicit: phloxSessionID, environment: environment)
        self.preApprovalPolicy = preApprovalPolicy
        self.transportFactory = { command, arguments, environment, workingDirectory in
            LineDelimitedProcessTransport(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        }
        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!
    }

    public init(
        command: String = "claude",
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        permissionMode: String? = nil,
        model: String? = nil,
        allowedTools: [String] = [],
        phloxSessionID: String? = nil,
        preApprovalPolicy: PreApprovalPolicy? = nil,
        transportFactory: @escaping TransportFactory
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.currentModel = model
        self.currentPermissionMode = Self.resolvedPermissionMode(permissionMode, preApprovalPolicy: preApprovalPolicy)
        self.allowedTools = Self.resolvedAllowedTools(allowedTools, preApprovalPolicy: preApprovalPolicy)
        self.phloxSessionID = Self.resolvePhloxSessionID(explicit: phloxSessionID, environment: environment)
        self.preApprovalPolicy = preApprovalPolicy
        self.transportFactory = transportFactory
        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!
    }

    deinit {
        receiveTask?.cancel()
        eventContinuation.finish()
    }

    public func start() async {
        guard transport == nil else {
            eventContinuation.yield(.warning(message: "Claude chat client is already started"))
            return
        }

        do {
            try await spawn(sessionArgument: initialSessionArgument())
        } catch {
            eventContinuation.yield(.error(message: "Failed to start Claude: \(error)"))
        }
    }

    /// Replaces the model/permission-mode with the given snapshot. Callers pass
    /// the complete desired state each time: a `nil` argument clears that flag
    /// (so the next spawn omits `--model` / `--permission-mode`), which is how a
    /// menu returns to the built-in default. Because Claude is a long-lived `-p`
    /// process whose flags are fixed at spawn time, this records the values and
    /// marks them dirty; the next idle `turnStart` applies them via a
    /// resume-preserving respawn.
    /// NOTE: to keep the auto-approve tool grant (see resolvedPermissionMode),
    /// callers that want `acceptEdits` must pass it explicitly here.
    /// The two-argument form leaves `effort` unchanged; use the three-argument
    /// overload when effort should be set or cleared (nil removes `--effort`).
    public func updateSettings(model: String?, permissionMode: String?) async {
        currentModel = model
        currentPermissionMode = permissionMode
        settingsDirty = true
    }

    public func updateSettings(model: String?, permissionMode: String?, effort: String?) async {
        currentModel = model
        currentPermissionMode = permissionMode
        currentEffort = effort
        settingsDirty = true
    }

    public func turnStart(_ input: [ChatInput]) async throws {
        if transport == nil {
            do {
                try await spawn(sessionArgument: settingsRespawnSessionArgument())
                settingsDirty = false
            } catch {
                eventContinuation.yield(.error(message: "Failed to restart Claude transport: \(error)"))
            }
        }

        guard transport != nil else {
            throw ClaudeChatClientError.notStarted
        }

        // Apply pending settings before the approval await (reentrancy-safe) and
        // only when no turn is in-flight; a resume-preserving respawn re-runs
        // buildArguments with the new model/permission-mode while keeping context.
        if settingsDirty, !currentTurnOpen {
            do {
                try await spawn(sessionArgument: settingsRespawnSessionArgument())
                settingsDirty = false
            } catch {
                eventContinuation.yield(.error(message: "Failed to apply Claude settings: \(error)"))
            }
        }

        guard let transport else {
            throw ClaudeChatClientError.notStarted
        }
        // The process may already have spawn-time tool permissions; the approval
        // boundary is this submit gate. Denied turns return before transport.send.
        if let denial = await preApprovalDenial(for: input) {
            eventContinuation.yield(.error(message: "Claude turn blocked by approval policy: \(denial)"))
            return
        }

        let content: [[String: Any]] = input.map { item in
            switch item {
            case .text(let text):
                ["type": "text", "text": text]
            case .image(let data, let mediaType):
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": data.base64EncodedString(),
                    ],
                ]
            }
        }
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": content,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        var line = Data(data)
        line.append(0x0A)

        currentTurnHealCount = 0
        eventContinuation.yield(.turnStarted)
        do {
            try await transport.send(line)
            currentTurnOpen = true
            currentTurnLine = line
        } catch {
            currentTurnOpen = false
            eventContinuation.yield(.error(message: "Failed to send Claude user turn: \(error)"))
            throw error
        }
    }

    public func resume(sessionRef: String) async throws {
        try await spawn(sessionArgument: .resume(sessionRef))
        callerResumedSession = true
    }

    /// 会話文脈をリセットする。Claude は長寿命 `-p` プロセスで会話状態がプロセスに束縛されるため、
    /// 現在の transport を閉じ、`--resume` を付けない新規 spawn（`.none`）へ切り替える。
    /// これにより CLI は新しい session id で仕切り直す。旧会話 id や自己修復・保留エラーの
    /// 状態も破棄し、以後の設定 respawn が旧会話へ `--resume` しないようにする。
    public func resetConversation() async {
        currentTurnOpen = false
        currentTurnLine = nil
        pendingResultError = nil
        interruptedResultSuppression = nil
        currentSessionId = nil
        observedExistingConversation = false
        callerResumedSession = false
        settingsDirty = false
        do {
            try await spawn(sessionArgument: .none)
        } catch {
            eventContinuation.yield(.error(message: "Failed to reset Claude conversation: \(error)"))
        }
    }

    public func interrupt() async throws {
        guard let transport else { return }
        let shouldSuppressInterruptedResult = currentTurnOpen
        currentTurnOpen = false
        currentTurnLine = nil
        yieldPendingResultErrorIfNeeded()
        if shouldSuppressInterruptedResult {
            interruptedResultSuppression = InterruptedResultSuppression(
                generation: spawnGeneration
            )
        }
        await transport.interrupt()
        eventContinuation.yield(.turnInterrupted(nativeSessionId: currentSessionId))
    }

    public func close() async {
        receiveTask?.cancel()
        receiveTask = nil
        failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
        yieldPendingResultErrorIfNeeded()
        currentTurnOpen = false
        currentTurnLine = nil
        await transport?.close()
        transport = nil
        // await close() の suspension 窓で登録された pending の取りこぼし防止
        // （spawn() と同じ理由。stage2 レビュー MUST）。
        failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
        eventContinuation.finish()
    }

    private func preApprovalDenial(for input: [ChatInput]) async -> String? {
        guard let preApprovalPolicy else { return nil }
        let request = PreApprovalRequest(
            summary: Self.promptText(from: input),
            workingDirectory: workingDirectory?.path
        )
        switch await preApprovalPolicy(request) {
        case .approve:
            return nil
        case .deny(let reason):
            return reason.isEmpty ? "denied" : reason
        }
    }

    private static func resolvedPermissionMode(
        _ permissionMode: String?,
        preApprovalPolicy: PreApprovalPolicy?
    ) -> String? {
        guard preApprovalPolicy != nil else { return permissionMode }
        // Claude's stream-json `-p` process keeps tool permissions fixed for its lifetime.
        // With a policy installed, safety lives at the submit gate above: denied turns are
        // never sent to the process, while approved turns can use the spawn-time tools.
        return permissionMode ?? preApprovedPermissionMode
    }

    private static func resolvedAllowedTools(
        _ allowedTools: [String],
        preApprovalPolicy: PreApprovalPolicy?
    ) -> [String] {
        guard preApprovalPolicy != nil, allowedTools.isEmpty else { return allowedTools }
        return defaultAllowedTools
    }

    private static func promptText(from input: [ChatInput]) -> String {
        input.compactMap { item in
            if case .text(let text) = item { text } else { nil }
        }
        .joined(separator: "\n")
    }

    private static func resolvePhloxSessionID(
        explicit: String?,
        environment: [String: String]
    ) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let value = environment["PHLOX_SESSION_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

}
