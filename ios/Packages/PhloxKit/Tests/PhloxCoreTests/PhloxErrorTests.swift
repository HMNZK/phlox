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
            .unsupported,
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
        let presentation = PhloxError.rateLimited(retryAfter: 42).presentation
        XCTAssertTrue(presentation.nextStep.contains("42"))
        XCTAssertEqual(presentation.title, "Mac が混み合っています")
        XCTAssertTrue(presentation.isNeutral)
        XCTAssertEqual(presentation.technicalDetail, "HTTP 429 · Retry-After: 42")
    }

    func testF1ThroughF8UseCatalogCopyAndOrder() {
        assertCatalogCopy(
            PhloxError.unauthorized.presentation,
            title: "Mac に接続を断られました",
            cause: "この iPhone に保存した接続の鍵（トークン）が、Mac 側で使えなくなっています。",
            nextStep: "Mac で QR を表示し、読み取り直してください。",
            detail: "HTTP 401 Unauthorized",
            action: "QR で再接続"
        )
        assertCatalogCopy(
            PhloxError.unreachable.presentation,
            title: "Mac に届きません",
            cause: "Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。",
            nextStep: "Mac を起こし、Tailscale をオンにしてから再試行してください。",
            detail: "Mac から応答がありません",
            action: "再試行"
        )
        assertCatalogCopy(
            PhloxError.rateLimited(retryAfter: 12).presentation,
            title: "Mac が混み合っています",
            cause: "短い間に要求が集中したため、Mac が受け付けを止めています。",
            nextStep: "12 秒後に再試行できます。",
            detail: "HTTP 429 · Retry-After: 12",
            action: "再試行（12 秒）",
            isNeutral: true
        )
        assertCatalogCopy(
            PhloxError.server(status: 500, message: "Internal Server Error").presentation,
            title: "Mac の Phlox でエラーが起きました",
            cause: "要求を処理している途中で、Mac 側で問題が起きました。",
            nextStep: "少し待って再試行してください。続くときは Mac の Phlox を再起動してください。",
            detail: "HTTP 500 Internal Server Error",
            action: "再試行"
        )
        assertCatalogCopy(
            PhloxError.decoding(WrappedError(description: "key \"sessions\" not found")).presentation,
            title: "Mac の応答を読めません",
            cause: "iPhone と Mac の Phlox のバージョンが合っていないと起きます。",
            nextStep: "App Store と Mac の両方で Phlox を最新にしてください。",
            detail: "decode: key \"sessions\" not found",
            action: nil
        )
        assertCatalogCopy(
            PhloxError.transport(WrappedError(description: "NSURLErrorNetworkConnectionLost (-1005)")).presentation,
            title: "通信が途中で切れました",
            cause: "電波が弱いか、Wi‑Fi とモバイル通信が切り替わりました。",
            nextStep: "通信が落ち着いたら再試行してください。",
            detail: "NSURLErrorNetworkConnectionLost (-1005)",
            action: "再試行"
        )
        assertCatalogCopy(
            PhloxError.spawnRejected(reason: "workspace \"phlox\" is locked by another spawn").presentation,
            title: "セッションを作れませんでした",
            cause: "Mac がこの作成を受け付けませんでした。Mac にセッションは作られていません。",
            nextStep: "理由を確かめてから、もう一度送信してください。指示は入力欄に戻してあります。",
            detail: "workspace \"phlox\" is locked by another spawn",
            action: "送信"
        )
        assertCatalogCopy(
            PhloxError.notFound.presentation,
            title: "このセッションは見つかりません",
            cause: "Mac 側で削除されたか、終了して片付けられました。",
            nextStep: "一覧に戻って、ほかのセッションを開いてください。",
            detail: "HTTP 404",
            action: "一覧に戻る"
        )
    }

    func testSpawnRejectedSurfacesServerReason() {
        let presentation = PhloxError.spawnRejected(reason: "最大深度を超えています").presentation
        XCTAssertEqual(presentation.title, "セッションを作れませんでした")
        XCTAssertEqual(presentation.technicalDetail, "最大深度を超えています")
        XCTAssertTrue(presentation.nextStep.contains("入力欄に戻してあります"))
    }

    func testUnauthorizedOffersConnectionRecovery() {
        let presentation = PhloxError.unauthorized.presentation
        XCTAssertEqual(presentation.title, "Mac に接続を断られました")
        XCTAssertEqual(presentation.recoveryAction, "QR で再接続")
        XCTAssertEqual(presentation.technicalDetail, "HTTP 401 Unauthorized")
    }

    func testServerFailureUsesCatalogOrderAndMonospaceDetail() {
        let presentation = PhloxError.server(status: 500, message: "Internal Server Error").presentation
        XCTAssertEqual(presentation.title, "Mac の Phlox でエラーが起きました")
        XCTAssertTrue(presentation.cause.contains("要求を処理している途中"))
        XCTAssertTrue(presentation.nextStep.contains("少し待って再試行"))
        XCTAssertEqual(presentation.technicalDetail, "HTTP 500 Internal Server Error")
    }

    func testTransportFailureUsesCatalogCopy() {
        let presentation = PhloxError.transport(WrappedError(description: "NSURLErrorNetworkConnectionLost (-1005)")).presentation
        XCTAssertEqual(presentation.title, "通信が途中で切れました")
        XCTAssertTrue(presentation.cause.contains("Wi‑Fi とモバイル通信"))
        XCTAssertTrue(presentation.nextStep.contains("通信が落ち着いたら"))
        XCTAssertEqual(presentation.technicalDetail, "NSURLErrorNetworkConnectionLost (-1005)")
    }

    private func assertCatalogCopy(
        _ presentation: ErrorPresentation,
        title: String,
        cause: String,
        nextStep: String,
        detail: String?,
        action: String?,
        isNeutral: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(presentation.title, title, file: file, line: line)
        XCTAssertEqual(presentation.cause, cause, file: file, line: line)
        XCTAssertEqual(presentation.nextStep, nextStep, file: file, line: line)
        XCTAssertEqual(presentation.technicalDetail, detail, file: file, line: line)
        XCTAssertEqual(presentation.recoveryAction, action, file: file, line: line)
        XCTAssertEqual(presentation.isNeutral, isNeutral, file: file, line: line)
    }
}
