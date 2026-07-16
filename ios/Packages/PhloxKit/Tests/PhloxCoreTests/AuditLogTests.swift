import XCTest
@testable import PhloxCore

// E3-6 検証。4 操作の記録・新しい順取得・send 本文非保持（要約長のみ）・ファイル永続化を検証する。
final class AuditLogTests: XCTestCase {

    // MARK: - InMemoryAuditLog

    func testRecordsFourOperationsAndRetrieves() async {
        let log = InMemoryAuditLog()
        await log.record(.spawn(sessionID: "s1", agentKind: .claudeCode))
        await log.record(.send(sessionID: "s1", summaryLength: 42))
        await log.record(.approve(approvalID: "a1", decision: .accept))
        await log.record(.remove(sessionID: "s1", cascadeCount: 3))

        let entries = await log.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 4)
        // 新しい順。
        XCTAssertEqual(entries.map(\.operation), ["remove", "approve", "send", "spawn"])
    }

    func testRecentEntriesRespectsLimit() async {
        let log = InMemoryAuditLog()
        await log.record(.authFailed)
        await log.record(.authFailed)
        await log.record(.authFailed)
        let entries = await log.recentEntries(limit: 2)
        XCTAssertEqual(entries.count, 2)
    }

    func testSendEntryDoesNotContainBody() async {
        let log = InMemoryAuditLog()
        let secretBody = "削除してくださいという秘密の本文"
        await log.record(.send(sessionID: "s1", summaryLength: secretBody.count))

        let entry = await log.recentEntries(limit: 1).first
        XCTAssertEqual(entry?.operation, "send")
        XCTAssertEqual(entry?.detail, "len=\(secretBody.count)")
        XCTAssertFalse(entry?.detail.contains("秘密") ?? true, "本文が混入してはならない")
    }

    func testEntryMappingForEachOperation() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(AuditEntry(.spawn(sessionID: "s", agentKind: .codex), at: now).detail, "codex")
        XCTAssertEqual(AuditEntry(.approve(approvalID: "a", decision: .decline), at: now).detail, "a:decline")
        XCTAssertEqual(AuditEntry(.remove(sessionID: "s", cascadeCount: 5), at: now).detail, "cascade=5")
        XCTAssertEqual(AuditEntry(.authFailed, at: now).operation, "authFailed")
    }

    // MARK: - FileAuditLog（一時ファイル・永続化）

    func testFileAuditLogPersistsAcrossInstances() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-audit-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let log1 = FileAuditLog(fileURL: tmp)
        await log1.record(.spawn(sessionID: "s1", agentKind: .cursor))
        await log1.record(.remove(sessionID: "s1", cascadeCount: 1))

        // 別インスタンスが同じファイルから復元する。
        let log2 = FileAuditLog(fileURL: tmp)
        let entries = await log2.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.operation, "remove")
    }
}
