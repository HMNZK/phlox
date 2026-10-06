// レイアウトプリセット選択メニュー。ユーザー要望「3セッションのとき片方半分・もう半分を上下に」が
// 1クリックで到達できることを、メニュー項目とプリセットの幾何の両方で固定する。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout preset menu")
struct PaneLayoutPresetMenuTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    // MARK: - メニュー項目

    @Test func items_matchesDeclarationOrderOfEveryCase() {
        // 全プリセットを重複なく選べる。表示順は enum 宣言順に一致させている。
        // 並びを変えたら意図的な変更としてこのテストを更新すること。
        #expect(PaneLayoutPresetMenu.items == PaneLayoutPreset.allCases)
    }

    @Test @MainActor func onSelect_isInvokedWithTheChosenPreset() {
        var selected: [PaneLayoutPreset] = []
        let menu = PaneLayoutPresetMenu { preset in
            selected.append(preset)
        }

        menu.onSelect(.mainLeftStackRight)
        menu.onSelect(.grid2x2)

        #expect(selected == [.mainLeftStackRight, .grid2x2])
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
}
