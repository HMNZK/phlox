import Foundation
import Testing
@testable import AppBootstrap

@Suite struct CleanupGuardTests {
    @Test func firstBeginCleanupGrantsStartRight() {
        let guardian = CleanupGuard()
        #expect(guardian.beginCleanup() == true)
    }

    @Test func secondBeginCleanupIsDenied() {
        let guardian = CleanupGuard()
        _ = guardian.beginCleanup()
        #expect(guardian.beginCleanup() == false)
    }

    @Test func hasBegunIsFalseBeforeFirstCall() {
        let guardian = CleanupGuard()
        #expect(guardian.hasBegun == false)
    }

    @Test func hasBegunBecomesTrueAfterFirstCall() {
        let guardian = CleanupGuard()
        _ = guardian.beginCleanup()
        #expect(guardian.hasBegun == true)
    }

    @Test func runOnceInvokesClosureOnFirstCall() {
        let guardian = CleanupGuard()
        var invocations = 0
        guardian.runOnce { invocations += 1 }
        #expect(invocations == 1)
    }

    @Test func runOnceDoesNotInvokeClosureOnSecondCall() {
        let guardian = CleanupGuard()
        var invocations = 0
        guardian.runOnce { invocations += 1 }
        guardian.runOnce { invocations += 1 }
        #expect(invocations == 1)
    }

    @Test func runOnceReturnsTrueOnlyForTheFirstCall() {
        let guardian = CleanupGuard()
        let first = guardian.runOnce { }
        let second = guardian.runOnce { }
        #expect(first == true)
        #expect(second == false)
    }

    /// シグナルハンドラの DispatchQueue と MainActor が同時に終了処理を要求しても、
    /// クリーンアップ本体は 1 回だけ走ることを担保する（並行アクセス下の高々 1 回）。
    @Test func concurrentRunOnceInvokesClosureExactlyOnce() async {
        let guardian = CleanupGuard()
        let counter = InvocationCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    guardian.runOnce { counter.increment() }
                }
            }
        }

        #expect(counter.value == 1)
    }
}

/// 並行テスト用のスレッドセーフなカウンタ（共有可変状態をテスト内に閉じ込めるため）。
private final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
