// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 監査所見: 全権トークンを NSPasteboard へ無防備コピー（ConcealedType/自動クリアなし, CWE-522）。
// SecurePasteboard（AgentDomain）が ConcealedType 併記＋changeCount 照合クリアを提供すること。
#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import AgentDomain

private func acceptancePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("phlox-acceptance-\(UUID().uuidString)"))
}

@Test func acceptance_copyConcealed_writesStringAndConcealedType() {
    let pasteboard = acceptancePasteboard()

    let changeCount = SecurePasteboard.copyConcealed("tok-123", to: pasteboard)

    #expect(pasteboard.string(forType: .string) == "tok-123")
    #expect(pasteboard.types?.contains(SecurePasteboard.concealedType) == true)
    #expect(changeCount == pasteboard.changeCount)
}

@Test func acceptance_clearIfUnchanged_clearsWhenCountMatches() {
    let pasteboard = acceptancePasteboard()
    let changeCount = SecurePasteboard.copyConcealed("tok-abc", to: pasteboard)

    let cleared = SecurePasteboard.clearIfUnchanged(pasteboard, expectedChangeCount: changeCount)

    #expect(cleared == true)
    #expect(pasteboard.string(forType: .string) == nil)
}

@Test func acceptance_clearIfUnchanged_keepsForeignContent() {
    let pasteboard = acceptancePasteboard()
    let changeCount = SecurePasteboard.copyConcealed("tok-x", to: pasteboard)

    // ユーザーがその後に別の内容をコピーした状況を模擬
    pasteboard.clearContents()
    pasteboard.setString("user data", forType: .string)

    let cleared = SecurePasteboard.clearIfUnchanged(pasteboard, expectedChangeCount: changeCount)

    #expect(cleared == false)
    #expect(pasteboard.string(forType: .string) == "user data")
}

@Test func acceptance_scheduleAutoClear_clearsAfterDelayWhenUnchanged() async throws {
    let pasteboard = acceptancePasteboard()
    let changeCount = SecurePasteboard.copyConcealed("tok-auto", to: pasteboard)

    SecurePasteboard.scheduleAutoClear(
        after: 0.1,
        pasteboard: pasteboard,
        expectedChangeCount: changeCount
    )
    try await Task.sleep(nanoseconds: 500_000_000)

    #expect(pasteboard.string(forType: .string) == nil)
}
#endif
