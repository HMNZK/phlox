import Foundation
import Testing
@testable import AppBootstrap

@Suite struct ShutdownDeadlineTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var codes: [Int32] = []
        let fired = DispatchSemaphore(value: 0)

        func record(_ code: Int32) {
            lock.lock(); codes.append(code); lock.unlock()
            fired.signal()
        }

        var recorded: [Int32] {
            lock.lock(); defer { lock.unlock() }
            return codes
        }
    }

    private func makeDeadline(_ timeout: Duration, _ recorder: Recorder) -> ShutdownDeadline {
        ShutdownDeadline(
            timeout: timeout,
            queue: DispatchQueue(label: "test.shutdown-deadline"),
            exit: { recorder.record($0) }
        )
    }

    @Test func firesExitWithGivenCodeAfterTimeout() {
        let recorder = Recorder()
        makeDeadline(.milliseconds(50), recorder).arm(exitCode: 7)

        #expect(recorder.fired.wait(timeout: .now() + 5) == .success)
        #expect(recorder.recorded == [7])
    }

    @Test func doesNotFireBeforeTimeout() {
        let recorder = Recorder()
        makeDeadline(.seconds(60), recorder).arm(exitCode: 0)

        #expect(recorder.fired.wait(timeout: .now() + 0.2) == .timedOut)
        #expect(recorder.recorded.isEmpty)
    }

    @Test func armingTwiceFiresOnceWithFirstCode() {
        let recorder = Recorder()
        let deadline = makeDeadline(.milliseconds(50), recorder)
        deadline.arm(exitCode: 0)
        deadline.arm(exitCode: 1)

        #expect(recorder.fired.wait(timeout: .now() + 5) == .success)
        #expect(recorder.fired.wait(timeout: .now() + 0.3) == .timedOut)
        #expect(recorder.recorded == [0])
    }
}
