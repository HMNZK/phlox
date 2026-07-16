// task-3 白箱テスト（実装役が追加）
#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import AgentDomain

private func testPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("phlox-whitebox-\(UUID().uuidString)"))
}

@Test func copyConcealed_doesNotBumpChangeCountBetweenStringAndConcealedWrites() {
    let pasteboard = testPasteboard()
    let before = pasteboard.changeCount

    let returned = SecurePasteboard.copyConcealed("tok-white", to: pasteboard)

    // declareTypes は1回だけ changeCount を進める。string/concealedType への setString は
    // 同一サイクル内なので、changeCount の増分は1のみであるべき（別 clearContents を挟んでいない証拠）。
    #expect(returned == before + 1)
    #expect(pasteboard.changeCount == returned)
    #expect(pasteboard.string(forType: SecurePasteboard.concealedType) == "tok-white")
}

@Test func clearIfUnchanged_returnsFalse_whenNothingWasEverCopied() {
    let pasteboard = testPasteboard()

    let cleared = SecurePasteboard.clearIfUnchanged(pasteboard, expectedChangeCount: -1)

    #expect(cleared == false)
}

@Test func scheduleAutoClear_doesNotClear_whenChangeCountAlreadyMismatched() async throws {
    let pasteboard = testPasteboard()
    let changeCount = SecurePasteboard.copyConcealed("tok-mismatch", to: pasteboard)

    // 予約前に別内容へ上書き（照合失敗を模擬）
    pasteboard.clearContents()
    pasteboard.setString("someone else's data", forType: .string)

    SecurePasteboard.scheduleAutoClear(
        after: 0.05,
        pasteboard: pasteboard,
        expectedChangeCount: changeCount
    )
    try await Task.sleep(nanoseconds: 300_000_000)

    #expect(pasteboard.string(forType: .string) == "someone else's data")
}
#endif
