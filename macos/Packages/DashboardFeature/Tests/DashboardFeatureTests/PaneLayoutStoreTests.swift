// 分割ツリーの永続化境界（PaneLayoutStore ↔ PaneTree の Codable）。実実装に対して走らせる（テストダブルを使わない）。
//
// - save の完了後に load すると、書いたツリーがそのまま返る（構造・weights・PaneID・順序）。
// - 保存キーは専用の1つだけを使い、他のキー（旧 phlox.grid.arrangement.<k> を含む）を汚さない。
// - 保存が無い・壊れている・未知の schemaVersion のときは nil（既定へフォールバック）で、クラッシュしない。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayoutStore persistence")
struct PaneLayoutStoreTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    private func withIsolatedDefaults(
        _ name: String,
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suite = "pane-layout-store-\(name)"
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

    // MARK: - 保存が無い・壊れている・未知の版

    @Test func store_usesTheDedicatedKey() {
        #expect(PaneLayoutStore.storageKey == "phlox.grid.paneLayout")
    }

    @Test func load_returnsNilWhenNothingSaved() throws {
        try withIsolatedDefaults("nothing-saved") { defaults in
            #expect(PaneLayoutStore(userDefaults: defaults).load() == nil)
        }
    }

    @Test func load_returnsNilForCorruptDataWithoutCrashing() throws {
        try withIsolatedDefaults("corrupt") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            for payload in [Data([0x00, 0xff, 0x10]), Data(), Data(#"{"hello":"world"}"#.utf8)] {
                defaults.set(payload, forKey: PaneLayoutStore.storageKey)
                #expect(store.load() == nil, "壊れたデータは nil を返す（クラッシュしない）")
            }
        }
    }

    @Test func load_returnsNilForUnknownSchemaVersion() throws {
        try withIsolatedDefaults("schema") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            store.save(PaneLayoutPreset.columns2.tree(for: [sid(0), sid(1)]))
            let data = try #require(defaults.data(forKey: PaneLayoutStore.storageKey))
            var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["schemaVersion"] = 999
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: PaneLayoutStore.storageKey)

            #expect(store.load() == nil, "未知の schemaVersion は既定へフォールバックさせる")
        }
    }

    // MARK: - 他のキーを汚さない

    @Test func save_doesNotTouchLegacyArrangementKeys() throws {
        // 旧キー phlox.grid.arrangement.<k> は移行も削除もしない。
        try withIsolatedDefaults("legacy") { defaults in
            let legacy = Data("legacy-payload".utf8)
            for size in 1...4 {
                defaults.set(legacy, forKey: "phlox.grid.arrangement.\(size)")
            }
            PaneLayoutStore(userDefaults: defaults).save(
                PaneLayoutPreset.grid2x2.tree(for: (0..<4).map(sid))
            )
            for size in 1...4 {
                #expect(defaults.data(forKey: "phlox.grid.arrangement.\(size)") == legacy,
                        "旧キー \(size) を書き換えない")
            }
        }
    }

    @Test func save_writesOnlyItsOwnKey() throws {
        try withIsolatedDefaults("isolation") { defaults in
            let store = PaneLayoutStore(userDefaults: defaults)
            store.save(PaneLayoutPreset.grid2x2.tree(for: (0..<4).map(sid)))

            let domain = defaults.persistentDomain(forName: "pane-layout-store-isolation") ?? [:]
            #expect(domain.keys.contains(PaneLayoutStore.storageKey))
            #expect(domain.keys.count == 1, "書き込むキーは1つだけ（実際のキー: \(Array(domain.keys))）")
        }
    }
}
