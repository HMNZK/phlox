import Foundation

public protocol LineDelimitedTransport: Sendable {
    var receivedLines: AsyncStream<Data> { get }

    func start() throws
    func send(_ data: Data) async throws
    func interrupt() async
    func close() async
    func stderrTail() async -> String?
}

public extension LineDelimitedTransport {
    func stderrTail() async -> String? {
        nil
    }
}

public enum LineDelimitedProcessTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case processLaunchFailed(String)
    case stdinClosed
}

public final class LineDelimitedProcessTransport: LineDelimitedTransport, @unchecked Sendable {
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private let workingDirectory: URL?
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var pendingOutput = Data()
    private var capturedStderr = Data()
    private var continuation: AsyncStream<Data>.Continuation?
    private var isFinished = false
    private var stdoutReaderQueue: DispatchQueue?
    private var stderrReaderQueue: DispatchQueue?
    private var readGroup: DispatchGroup?
    private let stderrTailLimit = 64 * 1024

    public let receivedLines: AsyncStream<Data>

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory

        var captured: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    public func start() throws {
        try lock.withLock {
            if process != nil {
                throw LineDelimitedProcessTransportError.alreadyStarted
            }

            let process = Process()
            process.executableURL = resolveExecutableURL(command)
            process.arguments = command.contains("/") ? arguments : [command] + arguments
            process.environment = environment
            process.currentDirectoryURL = workingDirectory

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutReaderQueue = DispatchQueue(label: "StructuredChatKit.LineDelimitedProcessTransport.stdout")
            let stderrReaderQueue = DispatchQueue(label: "StructuredChatKit.LineDelimitedProcessTransport.stderr")
            let readGroup = DispatchGroup()
            readGroup.enter()
            readGroup.enter()

            process.terminationHandler = { [weak self] _ in
                self?.finishWhenReaderIsDone()
            }

            do {
                try process.run()
            } catch {
                readGroup.leave()
                readGroup.leave()
                throw LineDelimitedProcessTransportError.processLaunchFailed(String(describing: error))
            }

            self.process = process
            self.stdinPipe = stdinPipe
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.stdoutReaderQueue = stdoutReaderQueue
            self.stderrReaderQueue = stderrReaderQueue
            self.readGroup = readGroup

            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            stdoutReaderQueue.async { [weak self] in
                defer { readGroup.leave() }
                let handle = stdoutPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    self?.appendOutput(data)
                }
            }
            stderrReaderQueue.async { [weak self] in
                defer { readGroup.leave() }
                let handle = stderrPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    self?.appendStderr(data)
                }
            }
        }
    }

    public func send(_ data: Data) async throws {
        let handle = try lock.withLock {
            guard let stdinPipe else { throw LineDelimitedProcessTransportError.notStarted }
            return stdinPipe.fileHandleForWriting
        }

        do {
            try handle.write(contentsOf: data)
        } catch {
            throw LineDelimitedProcessTransportError.stdinClosed
        }
    }

    public func interrupt() async {
        let process = lock.withLock { self.process }
        process?.interrupt()
    }

    public func close() async {
        lock.withLock { self.process }?.terminate()
        finishWhenReaderIsDone()
    }

    public func stderrTail() async -> String? {
        lock.withLock {
            guard !capturedStderr.isEmpty else { return nil }
            return String(decoding: capturedStderr, as: UTF8.self)
        }
    }

    private func finishWhenReaderIsDone() {
        let group = lock.withLock { readGroup }
        guard let group else {
            finish()
            return
        }
        group.notify(queue: .global()) { [weak self] in
            self?.finish()
        }
    }

    private func appendOutput(_ data: Data) {
        lock.withLock {
            guard !isFinished else { return }
            pendingOutput.append(data)
            emitCompleteLinesFromPendingOutput()
        }
    }

    private func appendStderr(_ data: Data) {
        lock.withLock {
            guard !isFinished else { return }
            capturedStderr.append(data)
            if capturedStderr.count > stderrTailLimit {
                capturedStderr.removeFirst(capturedStderr.count - stderrTailLimit)
            }
        }
    }

    private func finish() {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true

            if let handle = stdoutPipe?.fileHandleForReading {
                let trailing = handle.readDataToEndOfFile()
                if !trailing.isEmpty {
                    pendingOutput.append(trailing)
                }
                try? handle.close()
            }
            try? stdoutPipe?.fileHandleForWriting.close()

            emitCompleteLinesFromPendingOutput()
            if !pendingOutput.isEmpty {
                continuation?.yield(pendingOutput)
                pendingOutput.removeAll()
            }
            continuation?.finish()
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
            stderrPipe = nil
            stdoutReaderQueue = nil
            stderrReaderQueue = nil
            readGroup = nil
        }
    }

    private func emitCompleteLinesFromPendingOutput() {
        while let newline = pendingOutput.firstIndex(of: 0x0A) {
            let line = pendingOutput[..<newline]
            if !line.isEmpty {
                continuation?.yield(Data(line))
            }
            pendingOutput.removeSubrange(...newline)
        }
    }

    private func resolveExecutableURL(_ command: String) -> URL {
        if command.contains("/") {
            return URL(fileURLWithPath: command)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
