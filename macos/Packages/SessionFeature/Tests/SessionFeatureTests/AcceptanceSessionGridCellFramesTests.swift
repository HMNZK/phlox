// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — k×k 盤のセル矩形計算と結合領域矩形（内部 spacing を内包）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面（未実装の間はコンパイル赤＝red 状態）:
// - sessionGridCellFrames(size:bounds:spacing:) -> [CGRect]
// - sessionGridRegionRect(region:size:bounds:spacing:) -> CGRect

import CoreGraphics
import Testing
@testable import SessionFeature

@Suite("SessionGridCellFrames acceptance (task-2)")
struct AcceptanceSessionGridCellFramesTests {
    private let eps: CGFloat = 0.001

    // MARK: - セル矩形（等分割・行/列の整列）

    @Test func cellFrames_countIsSquare() {
        #expect(sessionGridCellFrames(size: 2, bounds: CGSize(width: 100, height: 100), spacing: 10).count == 4)
        #expect(sessionGridCellFrames(size: 3, bounds: CGSize(width: 100, height: 100), spacing: 10).count == 9)
        #expect(sessionGridCellFrames(size: 1, bounds: CGSize(width: 100, height: 100), spacing: 10).count == 1)
    }

    @Test func cellFrames_equalDivisionWithSpacing() {
        // 各セル幅 = (100 - 10) / 2 = 45。row-major で cell0=左上, cell1=右上, cell2=左下, cell3=右下。
        let frames = sessionGridCellFrames(size: 2, bounds: CGSize(width: 100, height: 100), spacing: 10)
        #expect(abs(frames[0].width - 45) < eps)
        #expect(abs(frames[0].height - 45) < eps)
        #expect(abs(frames[0].minX - 0) < eps)
        #expect(abs(frames[0].minY - 0) < eps)
        #expect(abs(frames[1].minX - 55) < eps)
        #expect(abs(frames[1].minY - 0) < eps)
        #expect(abs(frames[2].minX - 0) < eps)
        #expect(abs(frames[2].minY - 55) < eps)
        #expect(abs(frames[3].minX - 55) < eps)
        #expect(abs(frames[3].minY - 55) < eps)
    }

    @Test func cellFrames_widthsSumToBoundsAndRowsColumnsAlign() {
        let frames = sessionGridCellFrames(size: 3, bounds: CGSize(width: 300, height: 300), spacing: 8)
        // 行0の 3 セル幅合計 + 2*spacing == bounds.width
        let rowSum = frames[0].width + frames[1].width + frames[2].width + 2 * 8
        #expect(abs(rowSum - 300) < eps)
        // 同一列は同じ x / width（cell0 と cell3 と cell6）
        #expect(abs(frames[0].minX - frames[3].minX) < eps)
        #expect(abs(frames[0].width - frames[6].width) < eps)
        // 同一行は同じ y / height（cell0 と cell1 と cell2）
        #expect(abs(frames[0].minY - frames[2].minY) < eps)
        #expect(abs(frames[0].height - frames[1].height) < eps)
    }

    @Test func cellFrames_size1FillsBounds() {
        let frames = sessionGridCellFrames(size: 1, bounds: CGSize(width: 80, height: 60), spacing: 10)
        #expect(abs(frames[0].width - 80) < eps)
        #expect(abs(frames[0].height - 60) < eps)
        #expect(abs(frames[0].minX - 0) < eps)
        #expect(abs(frames[0].minY - 0) < eps)
    }

    // MARK: - 結合領域の矩形（1×1 はセルと一致・span は内部 spacing を内包）

    @Test func regionRect_singleMatchesCell() {
        let bounds = CGSize(width: 100, height: 100)
        let frames = sessionGridCellFrames(size: 2, bounds: bounds, spacing: 10)
        let region = SessionGridArrangement.Region(anchor: 1, rowSpan: 1, colSpan: 1)
        let rect = sessionGridRegionRect(region: region, size: 2, bounds: bounds, spacing: 10)
        #expect(abs(rect.minX - frames[1].minX) < eps)
        #expect(abs(rect.minY - frames[1].minY) < eps)
        #expect(abs(rect.width - frames[1].width) < eps)
        #expect(abs(rect.height - frames[1].height) < eps)
    }

    @Test func regionRect_horizontalSpanIncludesInteriorSpacing() {
        // colSpan=2 の辺長 = 2*45 + 10 = 100（内部 spacing を内包）。
        let bounds = CGSize(width: 100, height: 100)
        let region = SessionGridArrangement.Region(anchor: 0, rowSpan: 1, colSpan: 2)
        let rect = sessionGridRegionRect(region: region, size: 2, bounds: bounds, spacing: 10)
        #expect(abs(rect.minX - 0) < eps)
        #expect(abs(rect.minY - 0) < eps)
        #expect(abs(rect.width - 100) < eps)
        #expect(abs(rect.height - 45) < eps)
    }

    @Test func regionRect_verticalSpanIncludesInteriorSpacing() {
        let bounds = CGSize(width: 100, height: 100)
        let region = SessionGridArrangement.Region(anchor: 0, rowSpan: 2, colSpan: 1)
        let rect = sessionGridRegionRect(region: region, size: 2, bounds: bounds, spacing: 10)
        #expect(abs(rect.width - 45) < eps)
        #expect(abs(rect.height - 100) < eps)
    }

    @Test func regionRect_fullSpanCoversBounds() {
        let bounds = CGSize(width: 120, height: 90)
        let region = SessionGridArrangement.Region(anchor: 0, rowSpan: 2, colSpan: 2)
        let rect = sessionGridRegionRect(region: region, size: 2, bounds: bounds, spacing: 6)
        #expect(abs(rect.width - 120) < eps)
        #expect(abs(rect.height - 90) < eps)
    }
}
