import XCTest
@testable import PhloxCore

// E3-2 検証。PhloxError の Equatable/Sendable と、全ケースの ErrorPresentation 変換（非空）を検証する。
final class PhloxErrorTests: XCTestCase {

    func testErrorsAreEquatable() {
        XCTAssertEqual(PhloxError.unauthorized, .unauthorized)
        XCTAssertEqual(PhloxError.rateLimited(retryAfter: 5), .rateLimited(retryAfter: 5))
        XCTAssertNotEqual(PhloxError.rateLimited(retryAfter: 5), .rateLimited(retryAfter: 6))
        XCTAssertEqual(PhloxError.server(status: 500, message: "x"), .server(status: 500, message: "x"))
        XCTAssertNotEqual(PhloxError.unauthorized, .unreachable)
    }

    func testWrappedErrorCapturesDescription() {
        struct Boom: Error {}
        let wrapped = WrappedError(Boom())
        XCTAssertFalse(wrapped.description.isEmpty)
        XCTAssertEqual(PhloxError.decoding(wrapped), .decoding(wrapped))
    }

    func testAllPresentationsHaveNonEmptyTitleAndMessage() {
        let cases: [PhloxError] = [
            .unauthorized,
            .unreachable,
            .rateLimited(retryAfter: 10),
            .spawnRejected(reason: "depth exceeded"),
            .notFound,
            .server(status: 503, message: nil),
            .decoding(WrappedError(description: "bad json")),
            .transport(WrappedError(description: "lost")),
        ]
        for error in cases {
            let p = error.presentation
            XCTAssertFalse(p.title.isEmpty, "title empty for \(error)")
            XCTAssertFalse(p.message.isEmpty, "message empty for \(error)")
        }
    }

    func testRateLimitedPresentationIncludesRetrySeconds() {
        XCTAssertTrue(PhloxError.rateLimited(retryAfter: 42).presentation.message.contains("42"))
    }

    func testSpawnRejectedSurfacesServerReason() {
        XCTAssertEqual(PhloxError.spawnRejected(reason: "最大深度を超えています").presentation.message, "最大深度を超えています")
    }

    func testUnauthorizedOffersConnectionRecovery() {
        XCTAssertEqual(PhloxError.unauthorized.presentation.recoveryAction, "接続設定を開く")
    }
}
