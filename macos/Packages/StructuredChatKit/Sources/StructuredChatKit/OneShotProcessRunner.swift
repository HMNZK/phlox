import Foundation
import Darwin

public struct OneShotProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var outputLines: [Data]
    public var errorLines: [Data]

    public init(exitCode: Int32, outputLines: [Data], errorLines: [Data] = []) {
        self.exitCode = exitCode
        self.outputLines = outputLines
        self.errorLines = errorLines
    }
}

public protocol OneShotProcessRunning: Sendable {
    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) async throws -> OneShotProcessResult
}

public struct OneShotProcessTimeoutError: Error, Equatable, LocalizedError, Sendable {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    public var errorDescription: String? {
        "one-shot process timed out after \(timeout) seconds"
    }
}

public struct OneShotProcessRunner: OneShotProcessRunning {
    private let timeout: TimeInterval?

    public init(timeout: TimeInterval? = nil) {
        self.timeout = timeout
    }

    public func run(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL? = nil
    ) async throws -> OneShotProcessResult {
        // Honor cancellation that arrived before we even launch a process.
        try Task.checkCancellation()
        let cancelBox = OneShotCancelBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let continuationBox = OneShotContinuationBox(continuation)
            let process = Process()
            process.executableURL = command.contains("/") ? URL(fileURLWithPath: command) : URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command.contains("/") ? arguments : [command] + arguments
            process.environment = environment
            process.currentDirectoryURL = workingDirectory

            let output = Pipe()
            let standardErrorPipe = Pipe()
            let outputCollector = OutputCollector()
            let errorCollector = OutputCollector()
            process.standardOutput = output
            process.standardError = standardErrorPipe
            let outputReaderQueue = DispatchQueue(label: "StructuredChatKit.OneShotProcessRunner.stdout")
            let errorReaderQueue = DispatchQueue(label: "StructuredChatKit.OneShotProcessRunner.stderr")
            let readGroup = DispatchGroup()
            readGroup.enter()
            readGroup.enter()
            let timeoutCancellation: OneShotTimeoutCancellation?
            let timeoutOutcome: OneShotTimeoutOutcome?
            let timeoutDeadline = timeout.map { DispatchTime.now() + $0 }
            if let timeout {
                let outcome = OneShotTimeoutOutcome()
                timeoutOutcome = outcome
                let timeoutWorkItem = DispatchWorkItem { [process, continuationBox] in
                    guard outcome.claimTimeout(kill: { Self.killProcessIfRunning(process) }) else { return }
                    continuationBox.resume(throwing: OneShotProcessTimeoutError(timeout: timeout))
                }
                timeoutCancellation = OneShotTimeoutCancellation(timeoutWorkItem)
            } else {
                timeoutOutcome = nil
                timeoutCancellation = nil
            }

            process.terminationHandler = { process in
                if timeoutOutcome?.claimTermination() ?? true {
                    timeoutCancellation?.cancel()
                }
                readGroup.notify(queue: .global()) {
                    try? output.fileHandleForReading.close()
                    try? output.fileHandleForWriting.close()
                    try? standardErrorPipe.fileHandleForReading.close()
                    try? standardErrorPipe.fileHandleForWriting.close()
                    let outputData = outputCollector.data()
                    let errorData = errorCollector.data()
                    continuationBox.resume(returning: OneShotProcessResult(
                        exitCode: process.terminationStatus,
                        outputLines: Self.splitLines(outputData),
                        errorLines: Self.splitLines(errorData)
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                readGroup.leave()
                readGroup.leave()
                try? output.fileHandleForReading.close()
                try? output.fileHandleForWriting.close()
                try? standardErrorPipe.fileHandleForReading.close()
                try? standardErrorPipe.fileHandleForWriting.close()
                continuationBox.resume(throwing: error)
                return
            }

            try? output.fileHandleForWriting.close()
            try? standardErrorPipe.fileHandleForWriting.close()

            // Register the live process for structured cancellation. If the task
            // cancellation handler already fired (before the process existed), the
            // box reports it here and we kill immediately so no live process leaks.
            if cancelBox.register(process) {
                Self.killProcessIfRunning(process)
            }

            if let timeoutCancellation, let timeoutDeadline {
                DispatchQueue.global().asyncAfter(deadline: timeoutDeadline, execute: timeoutCancellation.workItem)
            }
            outputReaderQueue.async {
                defer { readGroup.leave() }
                let handle = output.fileHandleForReading
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    outputCollector.append(data)
                }
            }
            errorReaderQueue.async {
                defer { readGroup.leave() }
                let handle = standardErrorPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    errorCollector.append(data)
                }
            }
            }
        } onCancel: {
            // Terminate the underlying process on Task cancellation. The
            // terminationHandler then resumes the continuation with the killed
            // process's result; the continuation box guarantees a single resume.
            cancelBox.cancel()
        }
    }

    private static func splitLines(_ data: Data) -> [Data] {
        var remaining = data
        var lines: [Data] = []
        while let newline = remaining.firstIndex(of: 0x0A) {
            let line = remaining[..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            remaining.removeSubrange(...newline)
        }
        if !remaining.isEmpty {
            lines.append(remaining)
        }
        return lines
    }

    fileprivate static func killProcessIfRunning(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard pid > 0 else { return }

        // SIGKILL on the parent closes its stdio FDs; cursor-agent's child zsh
        // then observes EOF and exits on its own. Foundation Process does not
        // make the child a process-group leader, so the process-group kill often
        // misses with ESRCH; keep it as best-effort coverage for matching groups.
        _ = Darwin.kill(pid, SIGKILL)
        if pid != Darwin.getpgrp() {
            _ = Darwin.kill(-pid, SIGKILL)
        }
    }
}

final class OneShotTimeoutOutcome: @unchecked Sendable {
    private enum Outcome {
        case pending
        case terminated
        case timedOut
    }

    private let lock = NSLock()
    private var outcome = Outcome.pending

    func claimTermination() -> Bool {
        lock.withLock {
            guard outcome == .pending else { return false }
            outcome = .terminated
            return true
        }
    }

    func claimTimeout(kill: () -> Void) -> Bool {
        lock.withLock {
            guard outcome == .pending else { return false }
            outcome = .timedOut
            kill()
            return true
        }
    }
}

private final class OneShotTimeoutCancellation: @unchecked Sendable {
    let workItem: DispatchWorkItem

    init(_ workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

/// Bridges structured Task cancellation to the underlying `Process`. The task
/// cancellation handler and the process-launch path race, so both go through the
/// lock: whichever observes the other's flag first performs the single kill.
private final class OneShotCancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Records the launched process. Returns `true` if cancellation already
    /// arrived while the process did not yet exist, meaning the caller must kill
    /// it now (the cancellation handler could not).
    func register(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return cancelled
        }
    }

    /// Invoked from the Task cancellation handler. Marks cancellation and kills
    /// the process if it has already been registered.
    func cancel() {
        let toKill: Process? = lock.withLock {
            cancelled = true
            return process
        }
        if let toKill {
            OneShotProcessRunner.killProcessIfRunning(toKill)
        }
    }
}

private final class OneShotContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<OneShotProcessResult, Error>

    init(_ continuation: CheckedContinuation<OneShotProcessResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: OneShotProcessResult) {
        guard markResumed() else { return }
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        guard markResumed() else { return }
        continuation.resume(throwing: error)
    }

    private func markResumed() -> Bool {
        lock.withLock {
            guard !didResume else { return false }
            didResume = true
            return true
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            buffer.append(data)
        }
    }

    func data() -> Data {
        lock.withLock {
            buffer
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
