import Foundation
import XCTest
@testable import PhloxCore

final class Wave4SharedSessionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "Wave4SharedSessionStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testWriteThenReadRoundTripsEmptySummaries() throws {
        let store = SharedSessionStore(userDefaults: defaults)

        try store.write([])

        XCTAssertEqual(try store.read(), [])
    }

    func testWriteThenReadRoundTripsMultipleSummaries() throws {
        let store = SharedSessionStore(userDefaults: defaults)
        let summaries = [
            SharedSessionSummary(
                id: "session-finished",
                statusLabel: "Finished",
                title: "Add mobile widget",
                detail: "No Changes",
                updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
            ),
            SharedSessionSummary(
                id: "session-waiting",
                statusLabel: "Waiting",
                title: "Review changes",
                detail: "Approval required",
                updatedAt: Date(timeIntervalSince1970: 1_750_000_100)
            ),
        ]

        try store.write(summaries)

        XCTAssertEqual(try store.read(), summaries)
    }

    func testEncodeThenDecodeIsPureRoundTrip() throws {
        let summaries = [
            SharedSessionSummary(
                id: "session-running",
                statusLabel: "Running",
                title: "Build simulator",
                detail: "In progress",
                updatedAt: Date(timeIntervalSince1970: 1_750_000_200)
            ),
        ]

        let data = try SharedSessionStore.encode(summaries)

        XCTAssertEqual(try SharedSessionStore.decode(data), summaries)
    }
}
