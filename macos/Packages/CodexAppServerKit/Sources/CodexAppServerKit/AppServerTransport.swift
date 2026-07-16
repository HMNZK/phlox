import Foundation

public protocol AppServerTransport: Sendable {
    var receivedLines: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
}

public enum ProcessTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case processLaunchFailed(String)
    case stdinClosed
}

public final class ProcessTransport: AppServerTransport, @unchecked Sendable {
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
    private var continuation: AsyncStream<Data>.Continuation?
    private var isFinished = false
    private var stdoutReaderQueue: DispatchQueue?
    private var stderrReaderQueue: DispatchQueue?
    private var readGroup: DispatchGroup?

    public let receivedLines: AsyncStream<Data>

    public init(
        command: String = "codex",
        arguments: [String] = ["app-server"],
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
                throw ProcessTransportError.alreadyStarted
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

            // stdout / stderr を専用キュー2本で並行にドレインする。stderr を読み続けないと、
            // 子が 64KiB を超える stderr を出したときに write でブロックし stdout が止まる（I8）。
            let stdoutReaderQueue = DispatchQueue(label: "CodexAppServerKit.ProcessTransport.stdout")
            let stderrReaderQueue = DispatchQueue(label: "CodexAppServerKit.ProcessTransport.stderr")
            let readGroup = DispatchGroup()
            readGroup.enter()
            readGroup.enter()

            // 両 reader が EOF に達してから finish する。terminationHandler で即 finish すると、
            // 終了直前に書かれた stdout 応答を読み切る前にストリームが閉じ取りこぼす（I9）。
            process.terminationHandler = { [weak self] _ in
                self?.finishWhenReaderIsDone()
            }

            do {
                try process.run()
            } catch {
                readGroup.leave()
                readGroup.leave()
                throw ProcessTransportError.processLaunchFailed(String(describing: error))
            }

            self.process = process
            self.stdinPipe = stdinPipe
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.stdoutReaderQueue = stdoutReaderQueue
            self.stderrReaderQueue = stderrReaderQueue
            self.readGroup = readGroup

            // 親が保持する write 端を閉じ、子の終了で reader が確実に EOF を受け取れるようにする。
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
            stderrReaderQueue.async {
                defer { readGroup.leave() }
                let handle = stderrPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    // stderr は捨てるが、ブロック回避のため読み続けなければならない。
                }
            }
        }
    }

    public func send(_ data: Data) async throws {
        let handle = try lock.withLock {
            guard let stdinPipe else { throw ProcessTransportError.notStarted }
            return stdinPipe.fileHandleForWriting
        }

        do {
            try handle.write(contentsOf: data)
        } catch {
            throw ProcessTransportError.stdinClosed
        }
    }

    public func close() async {
        lock.withLock { self.process }?.terminate()
        finishWhenReaderIsDone()
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

    private func finish() {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true

            // 両 reader 完了後でも、パイプに残った末尾データを確実に読み切ってから閉じる。
            if let handle = stdoutPipe?.fileHandleForReading {
                let trailing = handle.readDataToEndOfFile()
                if !trailing.isEmpty {
                    pendingOutput.append(trailing)
                }
                try? handle.close()
            }

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

extension ProcessTransport {
    public static func codexAppServer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL? = nil
    ) throws -> ProcessTransport {
        let transport = ProcessTransport(
            command: "codex",
            arguments: ["app-server"],
            environment: environment,
            workingDirectory: workingDirectory
        )
        try transport.start()
        return transport
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
