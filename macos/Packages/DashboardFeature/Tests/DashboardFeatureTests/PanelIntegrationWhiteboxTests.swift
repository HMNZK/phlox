import CoreGraphics
import Foundation
import Testing
@testable import DashboardFeature

@Suite("Panel drawer layout white-box tests")
struct PanelIntegrationWhiteboxTests {
    @Test("ドロワー幅は最小幅より小さくならない")
    func drawerWidthHasMinimum() {
        #expect(PanelDrawerLayout.clamped(width: 120, availableWidth: 640) == PanelDrawerLayout.minimumWidth)
    }

    @Test("ドロワー幅は本文に割り当てられる幅を超えない")
    func drawerWidthIsClampedToAvailableSpace() {
        #expect(PanelDrawerLayout.clamped(width: 720, availableWidth: 480) == 480)
        #expect(PanelDrawerLayout.clamped(width: 360, availableWidth: 0) == 0)
    }

    @Test("左向きドラッグで幅を増やし、利用可能幅でクランプする")
    func dragProposalUsesTranslationWithoutMutatingLayoutDuringDrag() {
        #expect(PanelDrawerLayout.proposedWidth(startWidth: 420, translation: -80, availableWidth: 700) == 500)
        #expect(PanelDrawerLayout.proposedWidth(startWidth: 420, translation: -500, availableWidth: 600) == 600)
    }

    // レビュー HIGH-1 の再現: 表示幅（クランプ済み）と保存値（未クランプ）が食い違う
    // 状況で、ドラッグ開始幅に保存値を使うと最初の一定量の移動が無反応になることの証跡。
    // DashboardView は開始幅に `drawerWidth(windowWidth:)`（表示幅）を使うことでこれを回避する。
    @Test("保存値でドラッグを起点にすると、表示幅へ追いつくまで無反応になる")
    func startingDragFromStoredWidthIsUnresponsiveUntilItCatchesUpToDisplayedWidth() {
        let stored: CGFloat = 900
        let available: CGFloat = 358
        let displayed = PanelDrawerLayout.clamped(width: stored, availableWidth: available)
        #expect(displayed == 358)

        // 誤った配線（開始幅に保存値を渡す）: 500pt 動かしても幅は変わらない。
        #expect(
            PanelDrawerLayout.proposedWidth(startWidth: stored, translation: 500, availableWidth: available)
                == 358
        )

        // あるべき配線（開始幅に表示幅を渡す）: 動かした分だけ即座に追従する。
        #expect(
            PanelDrawerLayout.proposedWidth(startWidth: displayed, translation: 50, availableWidth: available)
                == 308
        )
    }

    // レビュー MEDIUM-1 の回帰ガード: Usage 等トップバーへ渡す幅はウィンドウ全幅基準で、
    // ドロワー幅を差し引いていないこと。将来 `windowWidth:` にドロワー幅由来の値を混入する
    // 変更が入ったら検知する。
    @Test("トップバーへ渡す windowWidth はドロワー幅から独立している（ソーススキャン）")
    func topBarWindowWidthDoesNotSubtractDrawerWidth() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let source = try String(
            contentsOf: url.appendingPathComponent(
                "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("windowWidth: geometry.size.width,"))
        #expect(!source.contains("windowWidth: drawerWidth"))
        #expect(!source.contains("windowWidth: storedDrawerWidth"))
    }
}

// レビュー MUST-1 の白箱テスト: エディタパネルの左右分割は内在最小幅
// (`EditorPanelLayout.splitMinimumWidth` ≈ 541pt) を持ち、確定容器（ドロワー既定幅 420pt・
// 最小幅 280pt）はこれを下回る。幅が足りないときは `.stacked`（縦積み）へ切り替えることで、
// 確定容器のどの幅でも操作可能な構造を保つ。
@Suite("Editor panel layout white-box tests")
struct EditorPanelLayoutWhiteboxTests {
    @Test("ドロワーの既定幅・最小幅の両方で左右分割の内在最小幅を下回るため縦積みになる")
    func editorStacksInsideConfirmedDrawer() {
        #expect(EditorPanelLayout.mode(forWidth: PanelDrawerLayout.preferredWidth) == .stacked)
        #expect(EditorPanelLayout.mode(forWidth: PanelDrawerLayout.minimumWidth) == .stacked)
    }

    @Test("左右分割の内在最小幅ちょうどでは分割、1pt 下回ると縦積み")
    func editorSwitchesAtSplitMinimumWidthBoundary() {
        #expect(EditorPanelLayout.mode(forWidth: EditorPanelLayout.splitMinimumWidth) == .split)
        #expect(EditorPanelLayout.mode(forWidth: EditorPanelLayout.splitMinimumWidth - 1) == .stacked)
    }

    @Test("十分に広い幅では左右分割になる")
    func editorSplitsWhenWide() {
        #expect(EditorPanelLayout.mode(forWidth: 700) == .split)
        #expect(EditorPanelLayout.splitMinimumWidth <= 700)
    }
}
