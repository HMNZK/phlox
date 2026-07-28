// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-5.md — レイアウトプリセット選択 UI と画面配線。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// この run の目的そのもの（ユーザー要望「3セッションのとき片方半分・もう半分を上下に」）が
// **1クリックで到達できる**ことを、メニュー項目とプリセットの幾何の両方で固定する。
//
// 凍結する公開面:
// - PaneLayoutPresetMenu.items: [PaneLayoutPreset]（表示順。ビューはこれを描くだけ）
// - PaneLayoutPresetMenu(onSelect:)

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout preset menu acceptance (task-5)")
struct AcceptancePaneLayoutPresetMenuTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    private func dashboardSource(_ fileName: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // DashboardFeatureTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // DashboardFeature（パッケージルート）
            .appendingPathComponent("Sources/DashboardFeature/Dashboard/\(fileName)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - メニュー項目

    @Test func menu_offersEveryPreset() {
        #expect(Set(PaneLayoutPresetMenu.items) == Set(PaneLayoutPreset.allCases),
                "全プリセットを選べること")
    }

    @Test func menu_itemsAreOrderedAndUnique() {
        #expect(PaneLayoutPresetMenu.items.count == Set(PaneLayoutPresetMenu.items).count,
                "重複した項目がない")
        #expect(!PaneLayoutPresetMenu.items.isEmpty)
    }

    @Test func menu_reachesTheRequestedLayoutInOneClick() {
        // ユーザー要望そのもの: 左半分に1枚・右半分を上下に2枚。
        #expect(PaneLayoutPresetMenu.items.contains(.mainLeftStackRight),
                "「左1＋右上下2」が1クリックで選べる位置にある")
    }

    @Test func menu_everyItemHasAJapaneseDisplayName() {
        for preset in PaneLayoutPresetMenu.items {
            #expect(!preset.displayName.isEmpty, "\(preset.rawValue): 表示名が空でない")
            #expect(preset.displayName != preset.rawValue,
                    "\(preset.rawValue): 内部名をそのまま表示していない")
        }
    }

    // MARK: - プリセットが実際に要望どおりの幾何を作る（UI とモデルの結合）

    @Test func mainLeftStackRight_producesHalfPlusTwoStacked() {
        let sessions = (0..<3).map(sid)
        let frames = PaneLayoutPreset.mainLeftStackRight
            .tree(for: sessions)
            .frames(in: CGSize(width: 1000, height: 800), spacing: 8)

        #expect(frames.tiles.count == 3)
        let sorted = frames.tiles.sorted { ($0.rect.minX, $0.rect.minY) < ($1.rect.minX, $1.rect.minY) }
        #expect(abs(sorted[0].rect.width - 496) < 1.0, "左は画面の半分の幅")
        #expect(abs(sorted[0].rect.height - 800) < 1.0, "左は全高")
        #expect(abs(sorted[1].rect.height - 396) < 1.0, "右上は半分の高さ")
        #expect(abs(sorted[2].rect.height - 396) < 1.0, "右下は半分の高さ")
        #expect(abs(sorted[1].rect.minX - 504) < 1.0, "右のペインは右半分に置かれる")
    }

    // MARK: - 画面配線（ソーススキャン）

    @Test func topBar_replacesTheGridColumnsSegmentWithThePresetMenu() throws {
        // 効かないコントロールを画面に残さない（レビュー指摘の恒久化）。
        let source = try dashboardSource("DashboardTopBarControls.swift")
        #expect(source.contains("PaneLayoutPresetMenu"), "プリセットメニューを置くこと")
        #expect(!source.contains("gridColumnsToggle"),
                "旧 1/2/3/4/Auto セグメントをトップバーから外すこと")
    }

    @Test func detailView_passesPaneLayoutToTheGrid() throws {
        let source = try dashboardSource("DashboardDetailView.swift")
        #expect(source.contains("paneLayout:"), "SessionGridView に分割ツリーを渡すこと")
        #expect(source.contains("paneLayoutForDisplay()"), "描画用の実効ツリーを渡すこと")
        #expect(source.contains("onLayoutAction:"), "レイアウト操作のコールバックを渡すこと")
        #expect(source.contains("handlePaneLayoutAction"), "操作を VM の書き込み経路へ流すこと")
    }

    @Test func presetMenu_routesSelectionThroughTheViewModel() throws {
        // VM を迂回して直接ツリーを書いていないこと。
        let source = try dashboardSource("PaneLayoutPresetMenu.swift")
        #expect(!source.contains("PaneLayoutStore"),
                "メニューが永続化層を直接触らないこと（VM 経由にする）")
        #expect(source.contains("onSelect"), "選択はコールバックで外へ出すこと")
    }
}
