import Foundation
import StructuredChatKit

public actor CursorChatClient: StructuredAgentClient {
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

    private let command: String
    private let workingDirectory: URL?
    private let environment: [String: String]
    private let preApprovalPolicy: PreApprovalPolicy?
    private let runner: any OneShotProcessRunning

    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    public nonisolated let events: AsyncStream<NormalizedChatEvent>

    private var resumeSessionId: String?
    private var isClosed = false
    private var currentModel: String?
    private var currentMode: String?

    // In-flight one-shot run handle so interrupt() can cancel it (which terminates
    // the cursor-agent process). `turnGeneration` invalidates a turn's events:
    // interrupt() bumps it, so a superseded turn (whose run may already be
    // returning) suppresses its own result instead of polluting a newer turn.
    private var inFlightRun: Task<OneShotProcessResult, Error>?
    private var turnGeneration: Int = 0

    // Monotonic per-turn ordinal used to salt text-derived itemIds so they do not
    // collide across turns. The first turn (ordinal 0) uses no salt to preserve the
    // existing bare "reasoning"/"assistant-0" itemIds; later turns get a prefix.
    private var turnOrdinal: Int = 0

    // Backstop only: normal long Cursor turns should finish well before this,
    // but a non-exiting cursor-agent must not leave the session Thinking forever.
    public static let defaultOneShotTimeout: TimeInterval = 300

    public init(
        command: String = "cursor-agent",
        workingDirectory: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        model: String? = nil,
        mode: String? = nil,
        preApprovalPolicy: PreApprovalPolicy? = nil,
        runner: any OneShotProcessRunning = OneShotProcessRunner(timeout: CursorChatClient.defaultOneShotTimeout)
    ) {
        self.command = command
        self.workingDirectory = workingDirectory.map { URL(fileURLWithPath: $0) }
        self.environment = environment
        self.currentModel = model
        self.currentMode = mode
        self.preApprovalPolicy = preApprovalPolicy
        self.runner = runner

        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream(bufferingPolicy: .unbounded) { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!
    }

    /// Replaces the per-turn model/mode with the given snapshot. Callers pass the
    /// complete desired state each time: a `nil` argument clears that flag (so the
    /// next spawn omits `--model` / `--mode`), which is how the mode menu returns
    /// to the default. The next `turnStart` one-shot spawn reflects it (no respawn).
    public func updateSettings(model: String?, mode: String?) async {
        currentModel = model
        currentMode = mode
    }

    public func start() async {}

    public func turnStart(_ input: [ChatInput]) async throws {
        guard !isClosed else { return }

        // Snapshot settings at turn entry (before the approval await) so a
        // reentrant updateSettings cannot change the args mid-turn.
        let modelSnapshot = currentModel
        let modeSnapshot = currentMode

        if input.contains(where: { item in
            if case .image = item { return true }
            return false
        }) {
            eventContinuation.yield(.warning(message: "画像添付は Claude のみ対応"))
        }
        let prompt = Self.promptText(from: input)
        eventContinuation.yield(.turnStarted)

        let isPreApproved: Bool
        if let preApprovalPolicy {
            let request = PreApprovalRequest(summary: prompt, workingDirectory: workingDirectory?.path)
            switch await preApprovalPolicy(request) {
            case .approve:
                isPreApproved = true
            case .deny(let reason):
                eventContinuation.yield(.error(
                    message: "Cursor turn blocked by approval policy: \(reason.isEmpty ? "denied" : reason)"
                ))
                return
            }
        } else {
            isPreApproved = false
        }

        var arguments = ["-p", prompt, "--output-format", "stream-json"]
        if let modelSnapshot {
            arguments.append(contentsOf: ["--model", modelSnapshot])
        }
        if let modeSnapshot {
            arguments.append(contentsOf: ["--mode", modeSnapshot])
        }
        if isPreApproved {
            arguments.append("-f")
        }
        if let resumeSessionId {
            arguments.append(contentsOf: ["--resume", resumeSessionId])
        }

        // Launch the one-shot inside a child Task whose handle we own so that
        // interrupt() can cancel it (terminating the underlying process). The
        // generation is claimed synchronously here — everything from this point to
        // the `await` below runs without suspension on the actor, so no reentrant
        // interrupt()/turnStart can interleave between claiming `myGeneration` and
        // storing the handle.
        turnGeneration += 1
        let myGeneration = turnGeneration
        let mySalt = turnOrdinal
        turnOrdinal += 1
        // Overtaking-turn guard: cancel a still-running superseded run (terminating
        // its cursor-agent process) BEFORE registering the new one, so an overtaken
        // turn's process cannot keep running in the background (up to 300s). This is
        // idempotent with interrupt()'s cancel (cancelling twice is a no-op) and, by
        // running in this non-suspending section, cannot cancel the new run.
        inFlightRun?.cancel()
        let runTask = Task<OneShotProcessResult, Error> { [runner, command, arguments, environment, workingDirectory] in
            try await runner.run(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        }
        inFlightRun = runTask

        let result: OneShotProcessResult
        do {
            result = try await runTask.value
        } catch {
            // Superseded by interrupt()/a newer turn while awaiting: swallow the
            // (cancellation or failure) error. interrupt() already emitted
            // .turnInterrupted and a newer turn owns the stream.
            guard isCurrentTurn(myGeneration) else { return }
            inFlightRun = nil
            eventContinuation.yield(.error(message: "cursor-agent failed: \(error.localizedDescription)"))
            return
        }

        // A concurrent interrupt() (or newer turn) may have superseded this turn
        // even though the run finished on its own. Suppress its events entirely.
        // Past this guard there is no suspension point, so the whole result is
        // processed atomically on the actor and cannot interleave with interrupt().
        guard isCurrentTurn(myGeneration) else { return }
        inFlightRun = nil

        if result.exitCode != 0 {
            eventContinuation.yield(.error(message: Self.exitErrorMessage(from: result)))
            return
        }

        // exit0 + stderr is NOT fatal: cursor-agent can write diagnostics to stderr
        // while still succeeding. Surface it as a non-fatal warning and keep parsing
        // stdout instead of discarding the whole turn (fatal stderr is exit≠0 only).
        if !result.errorLines.isEmpty {
            eventContinuation.yield(.warning(message: "cursor-agent wrote to stderr: \(Self.linesText(result.errorLines))"))
        }

        var parser = CursorStreamJSONParser(turnSalt: mySalt == 0 ? nil : String(mySalt))
        var sawTurnCompleted = false

        for line in result.outputLines {
            do {
                let events = try parser.ingest(line: line)
                for event in events {
                    if case .turnCompleted = event {
                        sawTurnCompleted = true
                    }
                    eventContinuation.yield(event)
                }
                if let sessionId = parser.nativeSessionId {
                    resumeSessionId = sessionId
                }
            } catch {
                eventContinuation.yield(.error(message: "Failed to parse cursor stream-json: \(error)"))
                return
            }
        }

        if let sessionId = parser.nativeSessionId {
            resumeSessionId = sessionId
        }

        // Only emit the generic fallback when NO result line was seen at all. A
        // non-success result already surfaced its own error via the parser, so
        // suppress the redundant "completed without result/success" here.
        if !sawTurnCompleted && !parser.sawResult {
            eventContinuation.yield(.error(message: "cursor-agent completed without result/success"))
        }
    }

    /// A turn is current only while its generation is still the latest and the
    /// client is open. interrupt()/close() bump/close to invalidate stale turns.
    private func isCurrentTurn(_ generation: Int) -> Bool {
        generation == turnGeneration && !isClosed
    }

    public func resume(sessionRef: String) async throws {
        resumeSessionId = sessionRef
    }

    /// 会話文脈をリセットする。cursor-agent は one-shot spawn 型なので、保持している
    /// resumeSessionId をクリアするだけで次ターンから `--resume` が外れ、新規会話になる。
    public func resetConversation() async {
        resumeSessionId = nil
    }

    public func interrupt() async throws {
        // Invalidate the in-flight turn (its result, if already returning, is
        // suppressed by the generation guard), cancel its run Task — which
        // terminates the cursor-agent process — then surface the interruption.
        // resumeSessionId is intentionally preserved for the next turn's --resume.
        turnGeneration += 1
        inFlightRun?.cancel()
        inFlightRun = nil
        eventContinuation.yield(.turnInterrupted(nativeSessionId: resumeSessionId))
    }

    public func close() async {
        isClosed = true
        inFlightRun?.cancel()
        inFlightRun = nil
        eventContinuation.finish()
    }

    private static func promptText(from input: [ChatInput]) -> String {
        input.compactMap { item in
            if case .text(let text) = item { text } else { nil }
        }
        .joined(separator: "\n")
    }

    private static func exitErrorMessage(from result: OneShotProcessResult) -> String {
        let stderr = linesText(result.errorLines)
        if stderr.isEmpty {
            return "cursor-agent exited with code \(result.exitCode)"
        }
        return "cursor-agent exited with code \(result.exitCode): \(stderr)"
    }

    private static func linesText(_ lines: [Data]) -> String {
        lines.map { String(data: $0, encoding: .utf8) ?? "" }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
