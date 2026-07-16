import XCTest
import DesignSystemIOS
@testable import Features

// DP-4-5 検証。カンプ⑤の文言・件数表示を View 層で保証する（中央アラート・単段確認）。
final class DeleteConfirmationViewTests: XCTestCase {

    func testTitleMatchesCamp() {
        XCTAssertEqual(DeleteConfirmationCopy.title, "セッションを削除しますか？")
    }

    func testCascadeBodyMentionsDescendantCount() {
        let body = DeleteConfirmationCopy.body(cascadeCount: 3)
        XCTAssertTrue(body.contains("子孫 3 件"))
        XCTAssertTrue(body.contains("Mac 側で削除されます"))
        XCTAssertTrue(body.contains("元に戻せません"))
    }

    func testZeroCascadeBodyOmitsDescendants() {
        let body = DeleteConfirmationCopy.body(cascadeCount: 0)
        XCTAssertFalse(body.contains("子孫"))
        XCTAssertTrue(body.contains("Mac 側で削除されます"))
    }

    func testDeleteButtonLabelIncludesTotalCount() {
        XCTAssertEqual(DeleteConfirmationCopy.deleteButtonLabel(totalCount: 4), "削除（4件）")
        XCTAssertEqual(DeleteConfirmationCopy.deleteButtonLabel(totalCount: 1), "削除（1件）")
    }

    func testBackdropOverlayOpacityMatchesCampBrightness() {
        XCTAssertEqual(DeleteConfirmationMetrics.backdropBrightness, 0.45, accuracy: 0.001)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropOverlayOpacity, 0.55, accuracy: 0.001)
    }

    func testBackdropMetricsUseDSColorModalBackdropToken() {
        XCTAssertEqual(DeleteConfirmationMetrics.backdropBrightness, DSColor.campModalBackdropBrightness)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropOverlayOpacity, DSColor.campModalBackdropOpacity)
    }
}
