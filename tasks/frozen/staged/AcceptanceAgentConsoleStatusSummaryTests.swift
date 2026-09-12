// task-37（UX-12）の受け入れテスト。状態要約と CLI 詳細ラベル。
//
// ベースラインでの red 理由: `AgentConsoleStatusSummary` と
// `AgentConsoleStatusSummary.make(isAvailable:configFileExists:)` は
// 本タスクが新設を要求する API で、baseline_commit の AgentConfigKit
// には存在しない（参照未解決でコンパイル不能＝red）。
//
// 契約: Bool 2 入力の 4 組すべてで表示フィールドをリテラル比較する。
// ファイル・CLI・UserDefaults は読まない。

import AgentConfigKit
import Testing

@Suite("task-37: agent console status summary")
struct AcceptanceAgentConsoleStatusSummaryTests {
    @Test("StatusSummary の Bool 2 入力 4 組で 4 つの表示フィールドと CLI 詳細ラベルをリテラル比較する")
    func statusSummaryFourCombinations() {
        let bothTrue = AgentConsoleStatusSummary.make(isAvailable: true, configFileExists: true)
        #expect(bothTrue.availabilityText == "CLI を検出済み")
        #expect(bothTrue.availabilityDetail == "認証・通信の状態は未確認です")
        #expect(bothTrue.configurationText == "設定ファイルあり")
        #expect(bothTrue.configurationDetail == nil)
        #expect(bothTrue.cliDetailsTitle == "CLI の詳細")

        let cliOnly = AgentConsoleStatusSummary.make(isAvailable: true, configFileExists: false)
        #expect(cliOnly.availabilityText == "CLI を検出済み")
        #expect(cliOnly.availabilityDetail == "認証・通信の状態は未確認です")
        #expect(cliOnly.configurationText == "設定ファイル未作成")
        #expect(cliOnly.configurationDetail == "必要な設定は左の項目から変更できます")
        #expect(cliOnly.cliDetailsTitle == "CLI の詳細")

        let fileOnly = AgentConsoleStatusSummary.make(isAvailable: false, configFileExists: true)
        #expect(fileOnly.availabilityText == "CLI を検出できていません")
        #expect(fileOnly.availabilityDetail == "インストール先と PATH を確認してください")
        #expect(fileOnly.configurationText == "設定ファイルあり")
        #expect(fileOnly.configurationDetail == nil)
        #expect(fileOnly.cliDetailsTitle == "CLI の詳細")

        let bothFalse = AgentConsoleStatusSummary.make(isAvailable: false, configFileExists: false)
        #expect(bothFalse.availabilityText == "CLI を検出できていません")
        #expect(bothFalse.availabilityDetail == "インストール先と PATH を確認してください")
        #expect(bothFalse.configurationText == "設定ファイル未作成")
        #expect(bothFalse.configurationDetail == "必要な設定は左の項目から変更できます")
        #expect(bothFalse.cliDetailsTitle == "CLI の詳細")
    }

    @Test("AgentConsoleStatusSummary は Equatable & Sendable")
    func summaryIsEquatableAndSendable() {
        requireEquatable(AgentConsoleStatusSummary.self)
    }
}

private func requireEquatable<T: Equatable & Sendable>(_: T.Type) {}
