import Foundation
import Testing
@testable import AppBootstrap

@Suite struct SignalSafeBoxTests {
    @Test func valueReturnsInitialValue() {
        let box = SignalSafeBox<Int?>(nil)
        #expect(box.value == nil)
    }

    @Test func setUpdatesValue() {
        let box = SignalSafeBox<Int?>(nil)
        box.set(42)
        #expect(box.value == 42)
    }

    @Test func setCanClearBackToNil() {
        let box = SignalSafeBox<Int?>(7)
        box.set(nil)
        #expect(box.value == nil)
    }

    @Test func lastWriteWinsAfterMultipleSets() {
        let box = SignalSafeBox<Int?>(nil)
        box.set(1)
        box.set(2)
        box.set(3)
        #expect(box.value == 3)
    }

    /// 並行に読み書きしてもクラッシュせず、最後の書き込みのどれかが観測されることを確認する
    /// （データ競合がロックで直列化されている）。
    @Test func concurrentReadsAndWritesAreSerialized() async {
        let box = SignalSafeBox<Int?>(0)

        await withTaskGroup(of: Void.self) { group in
            for i in 1...128 {
                group.addTask { box.set(i) }
                group.addTask { _ = box.value }
            }
        }

        // 直列化されていれば、最終値は書き込んだ集合 1...128 のいずれか（破損値ではない）。
        let final = box.value
        #expect(final != nil)
        #expect((1...128).contains(final!))
    }
}
