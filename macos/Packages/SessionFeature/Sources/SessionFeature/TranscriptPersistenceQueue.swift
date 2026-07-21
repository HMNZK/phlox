import Foundation
import os
import AgentDomain

// Hidden secret: transcript writes are serialized through one FIFO Task chain.
@MainActor
final class TranscriptPersistenceQueue {
    private final class ChainToken {}

    private let sessionID: SessionID
    private let store: any TranscriptStore
    private var task: Task<Void, Never>?
    /// Identity token for the latest enqueued chain link (Task is a struct; cannot compare by ===).
    private var latestToken: ChainToken?

    init(sessionID: SessionID, store: any TranscriptStore) {
        self.sessionID = sessionID
        self.store = store
    }

    func enqueueUpsert(_ items: [ChatItem]) {
        guard !items.isEmpty else { return }
        let sessionID = sessionID
        let store = store
        enqueue {
            do {
                try await store.upsertTranscriptItems(items, for: sessionID)
            } catch {
                let message = "Phlox: transcript persistence failed for \(sessionID): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
    }

    func enqueueReplace(_ items: [ChatItem]) {
        let sessionID = sessionID
        let store = store
        enqueue {
            do {
                try await store.replaceTranscript(for: sessionID, with: items)
            } catch {
                let message = "Phlox: transcript replace failed for \(sessionID): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
    }

    /// Drain until the FIFO chain is idle, including writes enqueued while awaiting.
    func waitForPendingWrites() async {
        while task != nil {
            let tokenAtStart = latestToken
            await task?.value
            if latestToken === tokenAtStart {
                task = nil
                latestToken = nil
                return
            }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let token = ChainToken()
        latestToken = token
        let previous = task
        task = Task {
            await previous?.value
            await work()
        }
    }
}

/// Leading-edge throttle for mid-turn transcript persistence.
/// First request flushes immediately; later requests within `interval` schedule a trailing flush
/// (or force an immediate flush when `eventThreshold` events accumulate since the last flush).
@MainActor
final class MidTurnPersistenceGate {
    typealias Clock = @MainActor () -> Date
    typealias Scheduler = @MainActor (_ delay: TimeInterval, _ token: UInt64) -> Void

    private let interval: TimeInterval
    private let eventThreshold: Int
    private let now: Clock
    private var schedule: Scheduler

    private var lastFlushAt: Date?
    private var eventsSinceFlush = 0
    private var generation: UInt64 = 0
    private var isFlushScheduled = false

    init(
        interval: TimeInterval = 1.0,
        eventThreshold: Int = 32,
        now: @escaping Clock = Date.init,
        schedule: @escaping Scheduler = { _, _ in }
    ) {
        precondition(interval > 0)
        precondition(eventThreshold > 0)
        self.interval = interval
        self.eventThreshold = eventThreshold
        self.now = now
        self.schedule = schedule
    }

    func setScheduler(_ schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    /// Returns `true` when the caller should perform an immediate flush.
    @discardableResult
    func requestFlush() -> Bool {
        eventsSinceFlush += 1
        let timestamp = now()
        if shouldFlushImmediately(at: timestamp) {
            cancelScheduled()
            markFlushed(at: timestamp)
            return true
        }
        scheduleTrailingIfNeeded(at: timestamp)
        return false
    }

    /// Returns `true` when a previously scheduled trailing flush should run.
    func fireScheduled(token: UInt64) -> Bool {
        guard token == generation, isFlushScheduled else { return false }
        isFlushScheduled = false
        markFlushed(at: now())
        return true
    }

    /// Reset throttle after an external flush (turn boundary / flushTranscriptNow).
    func noteExternalFlush() {
        cancelScheduled()
        markFlushed(at: now())
    }

    /// Cancel a pending trailing flush without recording a flush timestamp change beyond generation bump.
    func cancelPending() {
        cancelScheduled()
    }

    private func shouldFlushImmediately(at timestamp: Date) -> Bool {
        guard let lastFlushAt else { return true }
        if eventsSinceFlush >= eventThreshold {
            return true
        }
        return timestamp.timeIntervalSince(lastFlushAt) >= interval
    }

    private func scheduleTrailingIfNeeded(at timestamp: Date) {
        guard let lastFlushAt else { return }
        guard !isFlushScheduled else { return }
        let elapsed = timestamp.timeIntervalSince(lastFlushAt)
        let delay = max(0, interval - elapsed)
        isFlushScheduled = true
        schedule(delay, generation)
    }

    private func cancelScheduled() {
        generation &+= 1
        isFlushScheduled = false
    }

    private func markFlushed(at timestamp: Date) {
        lastFlushAt = timestamp
        eventsSinceFlush = 0
    }
}

/// Termination-path race: return when either `task` completes or `timeout` elapses.
///
/// Unlike `withTaskGroup`, this does **not** await the losing side after the winner resumes.
/// On timeout the flush Task may keep running (process exit reclaims it); reply is not blocked
/// by a stalled non-throwing `Task.value` await inside the FIFO write chain.
public enum TerminationFlushRace {
    public static func race(
        timeout: Duration,
        against task: Task<Void, Never>
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finished = OSAllocatedUnfairLock(initialState: false)
            let resumeOnce: @Sendable () -> Void = {
                let shouldResume = finished.withLock { state -> Bool in
                    if state { return false }
                    state = true
                    return true
                }
                if shouldResume {
                    continuation.resume()
                }
            }

            // Unstructured: abandoned after resume; must not be a TaskGroup child.
            Task {
                await task.value
                resumeOnce()
            }
            Task {
                try? await Task.sleep(for: timeout)
                resumeOnce()
            }
        }
    }

    /// Start every body as its own child Task (concurrent), then race overall completion
    /// against `timeout`. A stalled body must not prevent sibling bodies from starting.
    ///
    /// Uses unstructured child Tasks (not `withTaskGroup`) so that after timeout wins,
    /// callers do not get stuck on TaskGroup's implicit await of remaining children.
    @MainActor
    public static func raceAllParallel(
        timeout: Duration,
        bodies: [() async -> Void]
    ) async {
        let flushTask = Task { @MainActor in
            let children = bodies.map { body in
                Task { @MainActor in
                    await body()
                }
            }
            for child in children {
                await child.value
            }
        }
        await race(timeout: timeout, against: flushTask)
    }
}
