import Foundation
import XCTest
import PhloxCore
import DesignSystemIOS

final class SessionGlanceProjectionTests: XCTestCase {
    func testSharedSessionWriterPreservesInputOrder() throws {
        let suite = "SessionGlanceProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedSessionStore(userDefaults: defaults)
        let writer = SharedSessionWriter(store: store)
        let sessions = [
            Session(
                id: "mac-first",
                name: "First",
                agent: .claudeCode,
                status: .running,
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            Session(
                id: "mac-second",
                name: "Second",
                agent: .claudeCode,
                status: .running,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
        ]

        try writer.write(sessions: sessions)

        XCTAssertEqual(try store.read().map(\.id), ["mac-first", "mac-second"])
    }


    func testProjectionUsesSharedRulesAndMetadata() {
        let cases: [(SessionStatus, Bool, Bool, SessionGlanceState)] = [
            (.starting, false, false, .starting), (.idle, false, false, .idle),
            (.running, false, false, .running), (.running, true, false, .stalled),
            (.awaitingApproval(prompt: "許可しますか"), false, false, .approval), (.awaitingUserQuestion, false, false, .question),
            (.completed(exitCode: 0), false, false, .done), (.completed(exitCode: 1), false, false, .done),
            (.idle, false, true, .doneUnread), (.completed(exitCode: 0), false, true, .doneUnread),
            (.error(message: "失敗"), false, false, .error),
        ]
        for (status, stalled, unread, expected) in cases {
            let session = Session(id: "s", name: "名前", agent: .claudeCode, status: status,
                                  subtitle: "古い補足", projectName: "phlox", isStalled: stalled,
                                  hasUnseenCompletion: unread, updatedAt: Date(timeIntervalSince1970: 1))
            let summary = SharedSessionWriter.summary(for: session)
            XCTAssertEqual(summary.glanceState, expected)
            XCTAssertEqual(summary.statusLabel, expected.label)
            XCTAssertEqual(summary.detail, expected == .error ? "失敗" : "phlox")
        }
    }

    func testCursorDoesNotExportApproval() {
        let session = Session(id: "cursor", name: "Cursor", agent: .cursor, status: .awaitingApproval(prompt: "許可しますか"), updatedAt: Date())
        XCTAssertEqual(SharedSessionWriter.summary(for: session).glanceState, .idle)
    }
}
