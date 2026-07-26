import Foundation

/// `PhloxAPI.listSessions()` を `interval` 間隔でポーリングし、`SessionsState` を配信する actor（E3-5）。
///
/// 到達性が `.online` のときのみ API を叩く。オフライン時は `.offline` を流し API を呼ばない。
/// 購読 `Task` がキャンセルされるとポーリングを止め、ストリームを正常終了する（リークなし）。
/// `scenePhase` 連動の停止/再開は App が購読の張り直しで制御する。
public actor SessionRepository: SessionRepositoryProtocol {
    public static let defaultUnknownTimeout: Duration = .seconds(20)

    private let api: PhloxAPI
    private let reachability: ReachabilityMonitoring
    private let unknownTimeout: Duration

    public init(
        api: PhloxAPI,
        reachability: ReachabilityMonitoring,
        unknownTimeout: Duration = SessionRepository.defaultUnknownTimeout
    ) {
        self.api = api
        self.reachability = reachability
        self.unknownTimeout = unknownTimeout
    }

    public func refresh() async throws {
        _ = try await api.listSessions()
    }

    public nonisolated func sessionStream(interval: Duration) -> AsyncStream<SessionsState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                await self?.poll(interval: interval, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func poll(interval: Duration, continuation: AsyncStream<SessionsState>.Continuation) async {
        continuation.yield(.loading)
        let unknownDeadline = ContinuousClock.now + unknownTimeout
        while !Task.isCancelled {
            await emitOnce(unknownDeadline: unknownDeadline, continuation: continuation)
            do {
                try await Task.sleep(for: interval)
            } catch {
                break // キャンセル
            }
        }
        continuation.finish()
    }

    private func emitOnce(
        unknownDeadline: ContinuousClock.Instant,
        continuation: AsyncStream<SessionsState>.Continuation
    ) async {
        var reachable = await reachability.current
        if reachable == .unknown {
            await reachability.refresh()
            guard !Task.isCancelled else { return }
            reachable = await reachability.current
            if reachable == .unknown {
                if ContinuousClock.now >= unknownDeadline {
                    continuation.yield(.offline)
                }
                return
            }
        }

        guard reachable == .online else {
            continuation.yield(.offline)
            return
        }
        do {
            let sessions = try await api.listSessions()
            continuation.yield(sessions.isEmpty ? .empty : .loaded(sessions))
        } catch let error as PhloxError {
            continuation.yield(.error(error))
        } catch {
            continuation.yield(.error(.transport(WrappedError(error))))
        }
    }
}
