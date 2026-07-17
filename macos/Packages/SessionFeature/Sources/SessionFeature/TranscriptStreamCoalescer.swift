import Foundation

/// Streaming delta の時間窓バッファ。時刻と予約処理を注入でき、UI 状態には依存しない。
@MainActor
final class TranscriptStreamCoalescer {
    enum DeltaKind: Equatable {
        case agent
        case reasoning
        case command
    }

    struct PendingDelta: Equatable {
        let itemId: String
        let kind: DeltaKind
        let delta: String
        let receivedAt: Date
    }

    struct Batch: Equatable {
        let deltas: [PendingDelta]
        let rawEvents: [String]
        let latestEventAt: Date
    }

    typealias Clock = @MainActor () -> Date
    typealias Scheduler = @MainActor (_ delay: TimeInterval, _ token: UInt64) -> Void

    private let flushInterval: TimeInterval
    private let now: Clock
    private var schedule: Scheduler
    private var generation: UInt64 = 0
    private var isFlushScheduled = false
    private var pendingDeltas: [PendingDelta] = []
    private var pendingRawEvents: [String] = []
    private var latestEventAt: Date?

    init(
        flushInterval: TimeInterval = 0.05,
        now: @escaping Clock = Date.init,
        schedule: @escaping Scheduler = { _, _ in }
    ) {
        precondition(flushInterval > 0 && flushInterval <= 0.1)
        self.flushInterval = flushInterval
        self.now = now
        self.schedule = schedule
    }

    func setScheduler(_ schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    func enqueue(itemId: String, kind: DeltaKind, delta: String, rawEvent: String) {
        let receivedAt = now()
        pendingDeltas.append(PendingDelta(
            itemId: itemId,
            kind: kind,
            delta: delta,
            receivedAt: receivedAt
        ))
        pendingRawEvents.append(rawEvent)
        latestEventAt = receivedAt

        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        schedule(flushInterval, generation)
    }

    func flushScheduled(token: UInt64) -> Batch? {
        guard token == generation, isFlushScheduled else { return nil }
        isFlushScheduled = false
        return takeBatch()
    }

    /// 非 delta イベントの順序バリア。既存の予約 token を世代更新で無効化する。
    func flushBarrier() -> Batch? {
        generation &+= 1
        isFlushScheduled = false
        return takeBatch()
    }

    /// transcript の再構築・破棄時に、旧状態向けの delta と予約 flush を無効化する。
    @discardableResult
    func invalidate() -> Batch? {
        generation &+= 1
        isFlushScheduled = false
        return takeBatch()
    }

    private func takeBatch() -> Batch? {
        guard let latestEventAt else { return nil }
        let batch = Batch(
            deltas: pendingDeltas,
            rawEvents: pendingRawEvents,
            latestEventAt: latestEventAt
        )
        pendingDeltas.removeAll(keepingCapacity: true)
        pendingRawEvents.removeAll(keepingCapacity: true)
        self.latestEventAt = nil
        return batch
    }
}
