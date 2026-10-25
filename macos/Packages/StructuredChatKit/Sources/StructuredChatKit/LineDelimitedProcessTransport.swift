import Foundation
import Darwin

public protocol LineDelimitedTransport: Sendable {
    var receivedLines: AsyncStream<Data> { get }

    func start() throws
    func send(_ data: Data) async throws
    func interrupt() async
    func close() async
    func stderrTail() async -> String?
    /// プロセスが自分で終了したときの終了コード（シグナル終了は 128 + シグナル番号）。動作中・未起動は nil。
    func terminationStatus() async -> Int32?
}

public extension LineDelimitedTransport {
    func stderrTail() async -> String? {
        nil
    }

    func terminationStatus() async -> Int32? {
        nil
    }
}

public enum LineDelimitedProcessTransportError: LocalizedError, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case processLaunchFailed(String)
    case stdinClosed

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted: "The agent process has already started."
        case .notStarted: "The agent process has not started."
        case .processLaunchFailed(let reason): "The agent process could not start: \(reason)"
        case .stdinClosed: "The agent's input channel has closed."
        }
    }
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
    private var exitStatus: Int32?
    private var continuation: AsyncStream<Data>.Continuation?
    private var isFinished = false
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var readGroup: DispatchGroup?
    private let stderrTailLimit = 64 * 1024
    private let maxLineBytes: Int
    private var lineLimitExceeded = false

    public let receivedLines: AsyncStream<Data>

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL? = nil,
        maxLineBytes: Int = 64 * 1024 * 1024
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.maxLineBytes = maxLineBytes

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

            let readQueue = DispatchQueue(label: "StructuredChatKit.LineDelimitedProcessTransport.read")
            let readGroup = DispatchGroup()
            readGroup.enter()
            readGroup.enter()

            process.terminationHandler = { [weak self] process in
                self?.recordExitStatus(of: process)
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
            self.readGroup = readGroup

            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            // stderr も読み続けないと、子が 64KiB を超える stderr を出したときに write でブロックする。
            stdoutSource = Self.makeReadSource(stdoutPipe.fileHandleForReading, queue: readQueue,
                onData: { [weak self] in self?.appendOutput($0) }, onEnd: { readGroup.leave() })
            stderrSource = Self.makeReadSource(stderrPipe.fileHandleForReading, queue: readQueue,
                onData: { [weak self] in self?.appendStderr($0) }, onEnd: { readGroup.leave() })
        }
    }

    /// データが届いたときだけ読み、EOF で cancel して onEnd を呼ぶ。読み取りごとに処理を終えるので、
    /// 読んだバッファはその場で解放される（`availableData` の無限ループは autorelease プールに溜め続けた。ADR 0220）。
    /// fd は閉じない（閉じるのは finish() だけ）。
    private static func makeReadSource(
        _ handle: FileHandle,
        queue: DispatchQueue,
        onData: @escaping @Sendable (Data) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) -> DispatchSourceRead {
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                onData(Data(buffer[0..<count]))
            } else if count < 0 && (errno == EINTR || errno == EAGAIN) {
                return
            } else {
                source.cancel()
            }
        }
        source.setCancelHandler(handler: onEnd)
        source.resume()
        return source
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
        let process = lock.withLock { self.process }
        process?.terminate()
        if let process {
            for _ in 0..<10 where process.isRunning {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break
                }
            }
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        finishWhenReaderIsDone()
    }

    public func stderrTail() async -> String? {
        lock.withLock {
            guard !capturedStderr.isEmpty else { return nil }
            return String(decoding: capturedStderr, as: UTF8.self)
        }
    }

    public func terminationStatus() async -> Int32? {
        lock.withLock { exitStatus }
    }

    private func recordExitStatus(of process: Process) {
        let status = process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus
            : process.terminationStatus
        lock.withLock { exitStatus = status }
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
            guard !isFinished, !lineLimitExceeded else { return }
            pendingOutput.append(data)
            emitCompleteLinesFromPendingOutput()
            if pendingOutput.count > maxLineBytes { stopForOversizedLine() }
        }
    }

    private func appendStderr(_ data: Data) {
        lock.withLock {
            guard !isFinished else { return }
            appendStderrTail(data)
        }
    }

    private func appendStderrTail(_ data: Data) {
        capturedStderr.append(data)
        if capturedStderr.count > stderrTailLimit {
            // removeFirst は切り出しになるだけで、先頭の領域を解放しない（追記のたびに裏の領域が伸び続ける）。
            let excess = capturedStderr.count - stderrTailLimit
            capturedStderr.removeSubrange(capturedStderr.startIndex..<capturedStderr.startIndex + excess)
        }
    }

    /// 改行の来ない行が上限を超えたら、理由を stderr 末尾に残して子を止める。
    /// 既存の「プロセス終了」エラーの経路で理由が表示される。lock 内で呼ぶ。
    private func stopForOversizedLine() {
        lineLimitExceeded = true
        pendingOutput.removeAll()
        appendStderrTail(Data("\nPhlox stopped the agent: an output line exceeded \(maxLineBytes) bytes without a newline.\n".utf8))
        if let pid = process?.processIdentifier, pid > 0 {
            _ = Darwin.kill(pid, SIGKILL)
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
            stdoutSource = nil
            stderrSource = nil
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
