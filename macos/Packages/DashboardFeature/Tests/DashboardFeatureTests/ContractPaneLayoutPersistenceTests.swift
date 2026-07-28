// シーム契約テスト: 分割ツリーの永続化境界（PaneLayoutStore ↔ PaneTree の Codable）。
// task-3（永続化・VM）と task-5（プリセット UI）が共有する。両タスクの verify で再実走する。
// PM 著・実装役は編集禁止（ハーネスの欠陥は PM に報告して承認を得てから修理）。
//
// 契約の骨子:
// - save の完了後に load すると、書いたツリーがそのまま返る（構造・weights・PaneID・順序）。
// - 実実装に対して走らせる（テストダブルを使わない）。
// - 保存キーは専用の1つだけを使い、他のキーを汚さない。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout persistence seam contract")
struct ContractPaneLayoutPersistenceTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    private func withIsolatedDefaults(
        _ name: String,
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suite = "pane-layout-contract-\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    // MARK: - 書いた値がそのまま返る

    @Test func saveThenLoad_returnsWhatWasWritten_forEveryPreset() throws {
        try withIsolatedDefaults("presets") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let sessions = (0..<5).map(sid)
            for preset in PaneLayoutPreset.allCases {
                let tree = preset.tree(for: sessions)
                store.save(tree)
                #expect(store.load() == tree, "\(preset.rawValue): 書いた木がそのまま返る")
            }
        }
    }

    @Test func saveThenLoad_preservesUnevenProportions() throws {
        try withIsolatedDefaults("proportions") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let sessions = (0..<3).map(sid)
            var tree = PaneLayoutPreset.columns3.tree(for: sessions)

            let bounds = CGSize(width: 1200, height: 800)
            let divider = try #require(tree.frames(in: bounds, spacing: 8).dividers.first)
            tree = tree.settingDivider(divider.id, leadingFraction: 0.73)

            store.save(tree)
            let restored = try #require(store.load())
            #expect(restored == tree, "比率がビット単位で保たれる")

            let before = tree.frames(in: bounds, spacing: 8).tiles.map(\.rect)
            let after = restored.frames(in: bounds, spacing: 8).tiles.map(\.rect)
            #expect(before == after, "復元後の矩形が一致する")
        }
    }

    @Test func saveThenLoad_preservesDividerIdentity() throws {
        // D10: 分割線 ID が往復で変わると、復元後のドラッグが別の分割線を動かす。
        try withIsolatedDefaults("divider-identity") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let tree = PaneLayoutPreset.mainLeftStackRight.tree(for: (0..<3).map(sid))
            store.save(tree)
            let restored = try #require(store.load())

            let bounds = CGSize(width: 1000, height: 800)
            #expect(
                tree.frames(in: bounds, spacing: 8).dividers.map(\.id)
                    == restored.frames(in: bounds, spacing: 8).dividers.map(\.id)
            )
        }
    }

    @Test func saveThenLoad_preservesEmptyTree() throws {
        try withIsolatedDefaults("empty") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let empty = PaneLayoutPreset.balanced.tree(for: [])
            store.save(empty)
            #expect(store.load() == empty)
        }
    }

    @Test func saveTwice_lastWriteWins() throws {
        try withIsolatedDefaults("overwrite") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let first = PaneLayoutPreset.columns2.tree(for: (0..<2).map(sid))
            let second = PaneLayoutPreset.rows3.tree(for: (0..<3).map(sid))
            store.save(first)
            store.save(second)
            #expect(store.load() == second)
        }
    }

    @Test func saveThenLoad_survivesManyPanes() throws {
        try withIsolatedDefaults("many") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            let tree = PaneLayoutPreset.balanced.tree(for: (0..<24).map(sid))
            store.save(tree)
            #expect(store.load() == tree)
            #expect(tree.sessions.count == 24)
        }
    }

    // MARK: - 他のキーを汚さない

    @Test func save_writesOnlyItsOwnKey() throws {
        try withIsolatedDefaults("isolation") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            store.save(PaneLayoutPreset.grid2x2.tree(for: (0..<4).map(sid)))

            let domain = defaults.persistentDomain(forName: "pane-layout-contract-isolation") ?? [:]
            #expect(domain.keys.contains(PaneLayoutStore.storageKey))
            #expect(domain.keys.count == 1, "書き込むキーは1つだけ（実際のキー: \(Array(domain.keys))）")
        }
    }
}
