import Testing
import Foundation
import CoreGraphics
@testable import SessionFeature

/// task-2（タイル内クリックで即選択）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// AppKit の実イベントは単体テストで作れないため、判定と発火を純粋な型へ切り出して凍結する。
/// 「タイルの矩形内の左マウスダウンで、未選択なら選択する。選択済みなら何もしない」が契約。
@Suite("PaneTile click selection acceptance")
@MainActor
struct PaneTileClickSelectionAcceptanceTests {

    private let tile = CGRect(x: 100, y: 200, width: 400, height: 300)

    @Test
    func pointInsideUnfocusedTileSelects() {
        #expect(PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 350),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    @Test
    func pointInsideAlreadyFocusedTileDoesNotSelectAgain() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 350),
            tileFrameInWindow: tile,
            isFocused: true
        ))
    }

    @Test
    func pointOutsideTileDoesNotSelect() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 99, y: 350),
            tileFrameInWindow: tile,
            isFocused: false
        ))
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 300, y: 501),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    @Test
    func pointOnLeadingEdgeBelongsToTheTile() {
        #expect(PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 100, y: 200),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    /// 隣接するタイルの共有辺で二重に選択が走らないこと（右端・下端は自分のものではない）。
    @Test
    func pointOnTrailingEdgeBelongsToTheNeighbour() {
        #expect(!PaneTileClickSelectionPolicy.shouldSelect(
            pointInWindow: CGPoint(x: 500, y: 500),
            tileFrameInWindow: tile,
            isFocused: false
        ))
    }

    @Test
    func selectorFiresOnceForAClickInsideAnUnfocusedTile() {
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { self.tile },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        selector.handleMouseDown(pointInWindow: CGPoint(x: 120, y: 220))

        #expect(selections == 1)
    }

    @Test
    func selectorIgnoresClicksOutsideTheTile() {
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { self.tile },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        selector.handleMouseDown(pointInWindow: CGPoint(x: 10, y: 20))

        #expect(selections == 0)
    }

    @Test
    func selectorIgnoresClicksWhenTheTileIsAlreadyFocused() {
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { self.tile },
            isFocused: { true },
            onSelect: { selections += 1 }
        )

        selector.handleMouseDown(pointInWindow: CGPoint(x: 120, y: 220))

        #expect(selections == 0)
    }

    /// 矩形がまだ確定していない（レイアウト前）タイルは選択しない。
    @Test
    func selectorIgnoresClicksBeforeTheFrameIsKnown() {
        var selections = 0
        let selector = PaneTileClickSelector(
            tileFrameInWindow: { nil },
            isFocused: { false },
            onSelect: { selections += 1 }
        )

        selector.handleMouseDown(pointInWindow: CGPoint(x: 120, y: 220))

        #expect(selections == 0)
    }
}
