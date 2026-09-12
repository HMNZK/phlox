// task-38（UX-06）の受け入れテスト。
//
// ベースラインでの red 理由: `SettingsGroup` と `SettingsGroup.all` は
// 本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 既存設定を 5 グループへ再配置する分類の id / title / systemImage /
// sectionIDs と 14 Section ID をリテラルで固定する。実装の all から期待値を生成しない。

import DesignSystem
import Testing

@Suite("task-38: settings grouping model")
struct AcceptanceSettingsGroupingModelTests {
    /// 契約「グループ順序と所属」の 5 行。実装の `all` から作らない。
    private static let expectedGroups: [(id: String, title: String, systemImage: String, sectionIDs: [String])] = [
        ("general", "一般", "gearshape", ["language", "sessions", "notifications", "updates"]),
        ("appearance", "外観", "paintpalette", ["theme", "app-icon"]),
        ("agents", "エージェント", "wrench.and.screwdriver", ["permissions", "agent-management"]),
        ("connection", "接続", "network", ["mobile-connection", "paired-devices"]),
        ("advanced", "詳細", "slider.horizontal.3", ["discussion", "usage", "privacy", "about"]),
    ]

    /// 契約「現状の全 Section 見出し」の 14 Section ID。集合比較用のリテラル。
    private static let expectedSectionIDs: [String] = [
        "theme",
        "app-icon",
        "language",
        "sessions",
        "discussion",
        "permissions",
        "mobile-connection",
        "paired-devices",
        "notifications",
        "usage",
        "agent-management",
        "privacy",
        "updates",
        "about",
    ]

    @Test("グループ数が 5 で、id / title / systemImage / sectionIDs の順序が契約表と一致する")
    func fiveGroupsMatchFrozenTable() {
        #expect(SettingsGroup.all.count == 5)
        #expect(SettingsGroup.all.map(\.id) == ["general", "appearance", "agents", "connection", "advanced"])
        #expect(SettingsGroup.all.map(\.title) == ["一般", "外観", "エージェント", "接続", "詳細"])
        #expect(SettingsGroup.all.map(\.systemImage) == [
            "gearshape", "paintpalette", "wrench.and.screwdriver", "network", "slider.horizontal.3",
        ])
        #expect(SettingsGroup.all.map(\.id) == Self.expectedGroups.map(\.id))
        #expect(SettingsGroup.all.map(\.title) == Self.expectedGroups.map(\.title))
        #expect(SettingsGroup.all.map(\.systemImage) == Self.expectedGroups.map(\.systemImage))

        if SettingsGroup.all.count == 5 {
            for index in Self.expectedGroups.indices {
                let expected = Self.expectedGroups[index]
                let group = SettingsGroup.all[index]
                #expect(group.id == expected.id, Comment(rawValue: expected.id))
                #expect(group.title == expected.title, Comment(rawValue: expected.id))
                #expect(group.systemImage == expected.systemImage, Comment(rawValue: expected.id))
                #expect(group.sectionIDs == expected.sectionIDs, Comment(rawValue: expected.id))
            }
        }
    }

    @Test("sectionIDs の連結は 14 件で重複なし、和集合がリテラル 14 ID と一致する")
    func fourteenSectionIDsAreUniqueUnion() {
        let expectedConcatenated = Self.expectedGroups.flatMap(\.sectionIDs)
        #expect(expectedConcatenated.count == 14)
        #expect(Set(expectedConcatenated).count == 14)
        #expect(Set(expectedConcatenated) == Set(Self.expectedSectionIDs))
        #expect(Self.expectedSectionIDs.count == 14)
        #expect(Set(Self.expectedSectionIDs).count == 14)

        let got = SettingsGroup.all.flatMap(\.sectionIDs)
        #expect(got.count == 14)
        #expect(Set(got).count == 14)
        #expect(got == expectedConcatenated)
        #expect(Set(got) == Set(Self.expectedSectionIDs))
    }

    @Test("グループ ID に重複がなく、初期グループは general")
    func groupIDsAreUniqueAndInitialIsGeneral() {
        let ids = SettingsGroup.all.map(\.id)
        #expect(ids.count == 5)
        #expect(Set(ids).count == 5)
        #expect(SettingsGroup.all.first?.id == "general")
        #expect(ids.first == "general")
    }

    @Test("繰り返し取得して同じ値が得られる")
    func repeatedAllReadsAreEqual() {
        let first = SettingsGroup.all
        let second = SettingsGroup.all
        #expect(first == second)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.sectionIDs) == second.map(\.sectionIDs))
        #expect(SettingsGroup.all == SettingsGroup.all)
    }

    @Test("SettingsGroup は Identifiable かつ Equatable & Sendable")
    func modelIsIdentifiableEquatableAndSendable() {
        requireIdentifiable(SettingsGroup.self)
        requireEquatable(SettingsGroup.self)
    }
}

private func requireEquatable<T: Equatable & Sendable>(_: T.Type) {}

private func requireIdentifiable<T: Identifiable & Sendable>(_: T.Type) {}
