// task-38（UX-06）の受け入れテスト。
//
// ベースラインでの red 理由: `SettingsGroup` と `SettingsGroup.all` は
// 本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 既存設定を 6 グループへ再配置する分類の id / title / systemImage /
// sectionIDs と 12 Section ID をリテラルで固定する。実装の all から期待値を生成しない。
// 2026-09 UI 再設計（10 Settings）で 5 → 6 タブに組み替えた（ユーザー承認）。「詳細」を解体して使用量を独立、
// 通知を「一般」から分離、「セッション」は「言語と起動」へ、「プライバシー」は「このアプリについて」へ統合、文字の大きさを新設。

import DesignSystem
import Testing

@Suite("task-38: settings grouping model")
struct AcceptanceSettingsGroupingModelTests {
    /// 契約「グループ順序と所属」の 6 行。実装の `all` から作らない。
    private static let expectedGroups: [(id: String, title: String, systemImage: String, sectionIDs: [String])] = [
        ("general", "一般", "gearshape", ["language", "updates", "about"]),
        ("appearance", "外観", "paintpalette", ["theme", "app-icon", "text-size"]),
        ("notifications", "通知", "bell.badge", ["notifications"]),
        ("agents", "エージェント", "wrench.and.screwdriver", ["permissions", "agent-management"]),
        ("usage", "使用量", "gauge.with.dots.needle.33percent", ["usage"]),
        ("mobile", "モバイル連携", "iphone", ["mobile-connection", "paired-devices"]),
    ]

    /// 契約「現状の全 Section 見出し」の 12 Section ID。集合比較用のリテラル。
    private static let expectedSectionIDs: [String] = [
        "theme",
        "app-icon",
        "text-size",
        "language",
        "permissions",
        "mobile-connection",
        "paired-devices",
        "notifications",
        "usage",
        "agent-management",
        "updates",
        "about",
    ]

    @Test("グループ数が 6 で、id / title / systemImage / sectionIDs の順序が契約表と一致する")
    func sixGroupsMatchFrozenTable() {
        #expect(SettingsGroup.all.count == 6)
        #expect(SettingsGroup.all.map(\.id) == ["general", "appearance", "notifications", "agents", "usage", "mobile"])
        #expect(SettingsGroup.all.map(\.title) == ["一般", "外観", "通知", "エージェント", "使用量", "モバイル連携"])
        #expect(SettingsGroup.all.map(\.systemImage) == [
            "gearshape", "paintpalette", "bell.badge", "wrench.and.screwdriver", "gauge.with.dots.needle.33percent", "iphone",
        ])
        #expect(SettingsGroup.all.map(\.id) == Self.expectedGroups.map(\.id))
        #expect(SettingsGroup.all.map(\.title) == Self.expectedGroups.map(\.title))
        #expect(SettingsGroup.all.map(\.systemImage) == Self.expectedGroups.map(\.systemImage))

        if SettingsGroup.all.count == 6 {
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

    @Test("sectionIDs の連結は 12 件で重複なし、和集合がリテラル 12 ID と一致する")
    func twelveSectionIDsAreUniqueUnion() {
        let expectedConcatenated = Self.expectedGroups.flatMap(\.sectionIDs)
        #expect(expectedConcatenated.count == 12)
        #expect(Set(expectedConcatenated).count == 12)
        #expect(Set(expectedConcatenated) == Set(Self.expectedSectionIDs))
        #expect(Self.expectedSectionIDs.count == 12)
        #expect(Set(Self.expectedSectionIDs).count == 12)

        let got = SettingsGroup.all.flatMap(\.sectionIDs)
        #expect(got.count == 12)
        #expect(Set(got).count == 12)
        #expect(got == expectedConcatenated)
        #expect(Set(got) == Set(Self.expectedSectionIDs))
    }

    @Test("グループ ID に重複がなく、初期グループは general")
    func groupIDsAreUniqueAndInitialIsGeneral() {
        let ids = SettingsGroup.all.map(\.id)
        #expect(ids.count == 6)
        #expect(Set(ids).count == 6)
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
