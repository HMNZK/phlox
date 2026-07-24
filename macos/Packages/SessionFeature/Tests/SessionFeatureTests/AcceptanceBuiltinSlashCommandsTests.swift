import Foundation
import Testing
@testable import SessionFeature

// task-3 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-3.md
// 目的: composer のスラッシュコマンド補完に、/config・/plugin を含む Claude Code
//       組み込みコマンド一式を載せる（現状は 5 件のハードコードのみ）。

@Suite("Acceptance: 組み込みスラッシュコマンド補完の拡充（task-3）")
struct AcceptanceBuiltinSlashCommandsTests {

    private var titles: [String] {
        ComposerSuggestionSources.builtinSlashCommands.map(\.title)
    }

    @Test("ユーザー要望の /config・/plugin が補完候補に含まれる")
    func includesConfigAndPlugin() {
        #expect(titles.contains("/config"), "/config を補完候補に載せること")
        #expect(titles.contains("/plugin"), "/plugin を補完候補に載せること")
    }

    @Test("既存 5 件は維持される")
    func retainsExistingCommands() {
        for existing in ["/compact", "/clear", "/model", "/help", "/init"] {
            #expect(titles.contains(existing), "\(existing) を維持すること")
        }
    }

    @Test("組み込みコマンド一式として 12 件以上ある")
    func hasSubstantialBuiltinCoverage() {
        #expect(
            titles.count >= 12,
            "組み込み一式（/config /plugin に加え /status /context /cost 等の主要どころ）を載せること。現在=\(titles.count) 件"
        )
    }

    @Test("候補は一意で、/ 始まりで、説明（subtitle）を持つ")
    func candidatesAreWellFormed() {
        let candidates = ComposerSuggestionSources.builtinSlashCommands
        #expect(Set(titles).count == titles.count, "タイトルの重複禁止")
        for candidate in candidates {
            #expect(candidate.title.hasPrefix("/"), "\(candidate.title) は / 始まりであること")
            #expect(candidate.insertionText == candidate.title, "挿入テキストはタイトルと一致させること")
            #expect(candidate.subtitle?.isEmpty == false, "\(candidate.title) に説明を付けること")
        }
    }
}
