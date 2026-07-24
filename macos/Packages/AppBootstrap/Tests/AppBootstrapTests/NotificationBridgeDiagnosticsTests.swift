import Foundation
import OSLog
import Testing
import AgentDomain
@testable import AppBootstrap

// task-4 の APNs 可観測化（サイレント no-op の診断可能化）の回帰テスト（PM 著）。
// sender 未設定（鍵未設定）で通知イベントが握りつぶされるとき、原因を特定できる
// 診断ログ（イベント種別・sessionId・理由）が通常経路から必ず出ることを凍結する。
@Suite struct NotificationBridgeDiagnosticsTests {

    @Test func nilSenderNotifyEmitsDiagnosticLogWithEventAndSession() async throws {
        let store = InMemoryDeviceTokenStore()
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: nil)
        let marker = "diag-session-\(UUID().uuidString.prefix(8))"

        await bridge.notify(.sessionCompleted(sessionId: marker, sessionName: "Diag"))

        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        let position = logStore.position(date: Date().addingTimeInterval(-30))
        let entries = try logStore.getEntries(at: position)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "com.phlox.Phlox" && $0.category == "APNs" }
        let hit = try #require(
            entries.first { $0.composedMessage.contains(marker) },
            "sender 未設定の notify で sessionId を含む診断ログが出ること（サイレント no-op の禁止）"
        )
        #expect(hit.composedMessage.contains("event="), "ログにイベント種別が含まれること")
        #expect(
            hit.composedMessage.contains("sender unavailable") || hit.composedMessage.contains("鍵未設定"),
            "ログに原因（鍵未設定＝sender unavailable）が含まれること"
        )
    }
}
