import Foundation
import Testing
@testable import AppBootstrap

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Duration] = []
    private var calls = 0
    func sleep(_ duration: Duration) { lock.withLock { waits.append(duration) } }
    func attempt() { lock.withLock { calls += 1 } }
    var recordedWaits: [Duration] { lock.withLock { waits } }
    var attempts: Int { lock.withLock { calls } }
}

@Suite struct HostUpdateRetryTests {
    @Test func retriesUntilTheUpdateIsNoLongerDeferred() async {
        let recorder = Recorder()
        let count = await HostUpdateRetry.run(
            sleep: { recorder.sleep($0) },
            attempt: { recorder.attempt(); return recorder.attempts < 3 })
        #expect(count == 3)
        #expect(recorder.attempts == 3)
    }

    @Test func stopsAtTheMaximumNumberOfAttemptsWhileStillDeferred() async {
        let recorder = Recorder()
        let count = await HostUpdateRetry.run(
            sleep: { recorder.sleep($0) },
            attempt: { recorder.attempt(); return true })
        #expect(count == HostUpdateRetry.maximumAttempts)
        #expect(recorder.attempts == HostUpdateRetry.maximumAttempts)
    }

    @Test func aCallerCannotRaiseTheLimitOrShortenTheIntervalBelowTheFloor() async {
        let recorder = Recorder()
        let count = await HostUpdateRetry.run(
            interval: .milliseconds(1), maxAttempts: 10_000,
            sleep: { recorder.sleep($0) },
            attempt: { recorder.attempt(); return true })
        #expect(count == HostUpdateRetry.maximumAttempts)
        #expect(recorder.recordedWaits.allSatisfy { $0 >= HostUpdateRetry.minimumInterval })
        #expect(recorder.recordedWaits.count == HostUpdateRetry.maximumAttempts)
    }

    @Test func waitsBeforeTheFirstAttemptSoItNeverHammersImmediately() async {
        let recorder = Recorder()
        await HostUpdateRetry.run(
            maxAttempts: 1, sleep: { recorder.sleep($0) }, attempt: { recorder.attempt(); return true })
        #expect(recorder.recordedWaits == [HostUpdateRetry.defaultInterval])
        #expect(recorder.attempts == 1)
    }

    @Test func cancellationStopsWithoutCallingAttemptAgain() async {
        let recorder = Recorder()
        let task = Task {
            await HostUpdateRetry.run(
                sleep: { _ in throw CancellationError() },
                attempt: { recorder.attempt(); return true })
        }
        task.cancel()
        let count = await task.value
        #expect(count == 0)
        #expect(recorder.attempts == 0)
    }

    @Test func zeroOrNegativeMaximumRunsNothing() async {
        let recorder = Recorder()
        let count = await HostUpdateRetry.run(
            maxAttempts: 0, sleep: { recorder.sleep($0) }, attempt: { recorder.attempt(); return true })
        #expect(count == 0)
        #expect(recorder.recordedWaits.isEmpty)
    }
}

/// 更新を要求するのは画面の版がホストより新しいときだけ（古い画面がホストを古い版へ戻さない）。
@Suite struct HostBuildOrderTests {
    @Test func onlyANewerBuildRequestsTheUpdate() {
        #expect(HostBuildOrder.isNewer("58", than: "57"))
        #expect(!HostBuildOrder.isNewer("57", than: "57"))
        #expect(!HostBuildOrder.isNewer("56", than: "57"))
    }

    @Test func comparesNumbersNotText() {
        #expect(HostBuildOrder.isNewer("10", than: "9"))
        #expect(!HostBuildOrder.isNewer("9", than: "10"))
        #expect(HostBuildOrder.isNewer("1.10", than: "1.9"))
    }

    @Test func missingComponentsCountAsZero() {
        #expect(!HostBuildOrder.isNewer("57.0", than: "57"))
        #expect(!HostBuildOrder.isNewer("57", than: "57.0"))
        #expect(HostBuildOrder.isNewer("57.0.1", than: "57"))
        #expect(!HostBuildOrder.isNewer("57", than: "57.0.1"))
    }

    @Test(arguments: ["", "abc", "57a", "57.", ".57", "+58", "-1", " 58", "５８"])
    func versionsThatAreNotNumbersNeverRequestTheUpdate(_ invalid: String) {
        #expect(!HostBuildOrder.isNewer(invalid, than: "57"))
        #expect(!HostBuildOrder.isNewer("9999", than: invalid))
    }
}
