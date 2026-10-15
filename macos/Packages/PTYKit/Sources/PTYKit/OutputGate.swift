import Dispatch
import os

/// spawn 単位の未消費量と read source の停止回数を同じロックで管理する。
final class OutputGate: Sendable {
    static let highWater = 1024 * 1024
    static let lowWater = 256 * 1024
    static let trickleIntervalMilliseconds = 100

    struct State: Sendable {
        var pendingBytes = 0
        var suspended = false
        var suspendEpoch: UInt64 = 0
        var abandoned = false
        var cancelled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let readSource: DispatchSourceRead

    init(readSource: DispatchSourceRead) {
        self.readSource = readSource
    }

    // テストは時間待ちだけでなく、この状態で停止・再開を観測する。
    var snapshot: State { state.withLock { $0 } }

    func record(_ count: Int) {
        state.withLock { state in
            guard !state.cancelled, !state.abandoned else { return }
            state.pendingBytes += count
            if !state.suspended, state.pendingBytes >= Self.highWater {
                state.suspended = true
                state.suspendEpoch += 1
                let epoch = state.suspendEpoch
                readSource.suspend()
                // macOS PTY は最後の close で約0.6秒待って未読出力を捨てる（実測）。
                // XNU tty_dev.c の ptsclose は t_timeout = 60、根拠のリンクは ADR 0212。
                // 100msごとに最大4KiB読み、末尾を保護する。停止中の増加は約40KiB/s。
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Self.trickleIntervalMilliseconds)) {
                    self.trickle(epoch: epoch)
                }
            }
        }
    }

    func trickle(epoch: UInt64) {
        state.withLock { state in
            guard state.suspended, state.suspendEpoch == epoch,
                  !state.cancelled, !state.abandoned else { return }
            state.suspended = false
            readSource.resume()
        }
    }

    func acknowledge(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { state in
            state.pendingBytes = max(0, state.pendingBytes - count)
            if state.suspended, state.pendingBytes <= Self.lowWater {
                state.suspended = false
                readSource.resume()
            }
        }
    }

    func abandon() {
        state.withLock { state in
            state.abandoned = true
            if state.suspended {
                state.suspended = false
                readSource.resume()
            }
        }
    }

    /// read source の取消は必ずここを通す。取消後は record が再停止させない。
    func cancel() {
        state.withLock { state in
            guard !state.cancelled else { return }
            state.cancelled = true
            if state.suspended {
                state.suspended = false
                readSource.resume()
            }
            readSource.cancel()
        }
    }
}
