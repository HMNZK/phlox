import AgentDomain
import Foundation
import PTYKit

/// パネルから独立して動作するユーザー用シェルのライフサイクルを管理する。
@MainActor
public final class UserTerminalController {
    public private(set) var isRunning = false
    public private(set) var sessionID: SessionID?

    // PTYKit の出力ストリームと同じ上限を relay 側にも設け、購読者が停止しても
    // コントローラ内のストリームが無制限に蓄積しないようにする。
    private static let outputBufferLimit = 2048

    private let pty: any PTYManagerProtocol
    private let shellPath: String
    private let workingDirectory: String
    private let environment: [String: String]

    private var outputTasks: [UInt64: Task<Void, Never>] = [:]
    // 購読者はセッション再起動をまたいで保持し、明示的な shutdown でのみ finish する。
    private var outputSubscribers: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var exitTask: Task<Void, Never>?
    private var startInProgress = false
    private var startWaiters: [CheckedContinuation<StartOutcome, Error>] = []
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownRequested = false
    private var spawnGeneration: UInt64 = 0
    /// 表示器から最後に要求されたサイズ。PTY の fd がまだ使えない起動前・起動中も
    /// 保持し、spawn の初期サイズまたは spawn 完了直後の resize に使う。
    private var requestedSize: PTYInitialSize?

    private enum StartOutcome {
        case started
        case stoppedByShutdown
    }

    private enum UserTerminalControllerError: Error {
        case notRunning
    }

    public init(
        pty: any PTYManagerProtocol,
        shellPath: String,
        workingDirectory: String,
        environment: [String: String]
    ) {
        self.pty = pty
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    public func ensureStarted() async throws {
        while true {
            if isRunning {
                return
            }

            if startInProgress {
                let outcome = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<StartOutcome, Error>) in
                    startWaiters.append(continuation)
                }
                if case .stoppedByShutdown = outcome {
                    return
                }
                continue
            }

            startInProgress = true
            do {
                var outcome = try await startSession()

                // startSession() の await 復帰直後に shutdown() が割り込む可能性が
                // あるため、ここでも要求を確認してから待機者を再開する。
                if shutdownRequested, case .started = outcome {
                    await stopCurrentSession()
                    outcome = .stoppedByShutdown
                }

                startInProgress = false
                resumeStartWaiters(with: .success(outcome))

                if case .stoppedByShutdown = outcome {
                    shutdownRequested = false
                    resumeShutdownWaiters()
                    return
                }
                return
            } catch {
                startInProgress = false
                shutdownRequested = false
                resumeStartWaiters(with: .failure(error))
                resumeShutdownWaiters()
                throw error
            }
        }
    }

    public func send(_ input: String) async throws {
        guard isRunning, let sessionID else {
            throw UserTerminalControllerError.notRunning
        }
        try await pty.write(Data(input.utf8), to: sessionID)
    }

    /// 表示器の列数・行数を記憶し、起動済みなら現在の PTY へも伝える。
    public func resize(cols: UInt16, rows: UInt16) async throws {
        let size = PTYInitialSize(cols: cols, rows: rows)
        requestedSize = size

        guard isRunning, let sessionID else {
            return
        }
        try await pty.resize(sessionID, cols: cols, rows: rows)
    }

    /// 購読者ごとにストリームを作り、PTY 出力を各購読者へ複製して届ける。
    /// 再購読時は過去の出力を再送せず、購読開始後の出力だけを受け取る。
    public func makeOutputStream() -> AsyncStream<Data> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.outputBufferLimit)
        )
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeOutputSubscriber(subscriberID)
            }
        }
        outputSubscribers[subscriberID] = continuation
        return stream
    }

    public func shutdown() async {
        if startInProgress {
            shutdownRequested = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                shutdownWaiters.append(continuation)
            }
            return
        }

        await stopCurrentSession()
    }

    private func startSession() async throws -> StartOutcome {
        exitTask?.cancel()
        exitTask = nil
        sessionID = nil
        isRunning = false

        // 自然終了後の旧 relay が PTY の残出力を配り終えるまで待ってから世代を
        // 進める。PTY は exit code を流す前に output stream を finish するため、
        // この待機は有限である。明示 shutdown では relay が既に cancel・除去されている。
        let pendingRelays = Array(outputTasks.values)
        for relay in pendingRelays {
            _ = await relay.value
        }

        let initialSize = requestedSize
        let id = try await pty.spawn(
            command: shellPath,
            args: [],
            env: environment,
            id: nil,
            initialSize: initialSize,
            workingDirectory: workingDirectory
        )

        // spawn の await 中に新しいサイズが来た場合、fd が有効になってから最新値を
        // 反映する。起動前に使った initialSize と同じ値なら resize は不要である。
        var appliedSize = initialSize
        do {
            while let latestSize = requestedSize, latestSize != appliedSize {
                try await pty.resize(id, cols: latestSize.cols, rows: latestSize.rows)
                appliedSize = latestSize
            }
        } catch {
            await pty.kill(id)
            throw error
        }

        let outputStream = pty.outputStream(for: id)
        let exitStream = pty.exitStream(for: id)

        spawnGeneration &+= 1
        let generation = spawnGeneration
        self.sessionID = id
        isRunning = true
        startOutputObservation(
            stream: outputStream,
            generation: generation
        )
        startExitObservation(
            stream: exitStream,
            sessionID: id,
            generation: generation
        )

        if shutdownRequested {
            await stopCurrentSession()
            return .stoppedByShutdown
        }
        return .started
    }

    private func startOutputObservation(
        stream: AsyncStream<Data>,
        generation: UInt64
    ) {
        let task = Task { @MainActor [weak self] in
            defer {
                self?.outputTasks.removeValue(forKey: generation)
            }

            for await data in stream {
                guard let self,
                      self.spawnGeneration == generation else {
                    return
                }
                self.broadcastOutput(data)
            }
        }
        outputTasks[generation] = task
    }

    private func startExitObservation(
        stream: AsyncStream<Int32>,
        sessionID: SessionID,
        generation: UInt64
    ) {
        exitTask?.cancel()
        exitTask = Task { @MainActor [weak self] in
            var receivedExitCode = false
            for await _ in stream {
                guard let self,
                      self.spawnGeneration == generation,
                      self.sessionID == sessionID else {
                    return
                }
                receivedExitCode = true
                self.markCurrentSessionExited()
                return
            }

            guard let self,
                  self.spawnGeneration == generation,
                  self.sessionID == sessionID else {
                return
            }
            self.markCurrentSessionExited()

            // PTYManager は終了コードを 1 要素流してからストリームを閉じる契約だが、
            // テスト用実装や将来の transport が「要素なしで finish」する場合も、
            // 出力リレーを未完了のまま残してはいけない。次の ensureStarted() は
            // 前世代の残出力を待つため、この状態を放置すると永久に再起動できない。
            // 終了コードを受け取った通常経路では、PTYKit が output stream を finish
            // するまでリレーを待つ（終了直前の残出力を捨てない）。
            if !receivedExitCode {
                outputTasks[generation]?.cancel()
            }
        }
    }

    private func markCurrentSessionExited() {
        isRunning = false
        sessionID = nil
    }

    private func stopCurrentSession() async {
        let id = sessionID
        let shouldKill = isRunning

        exitTask?.cancel()
        exitTask = nil
        let tasks = Array(outputTasks.values)
        outputTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
        isRunning = false
        sessionID = nil

        if shouldKill, let id {
            await pty.kill(id)
        }
        finishOutputSubscribers()
    }

    private func resumeStartWaiters(with result: Result<StartOutcome, Error>) {
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success(let outcome):
                waiter.resume(returning: outcome)
            case .failure(let error):
                waiter.resume(throwing: error)
            }
        }
    }

    private func resumeShutdownWaiters() {
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func broadcastOutput(_ data: Data) {
        for continuation in outputSubscribers.values {
            continuation.yield(data)
        }
    }

    private func removeOutputSubscriber(_ subscriberID: UUID) {
        outputSubscribers.removeValue(forKey: subscriberID)
    }

    private func finishOutputSubscribers() {
        let subscribers = outputSubscribers.values
        outputSubscribers.removeAll()
        for continuation in subscribers {
            continuation.finish()
        }
    }
}
