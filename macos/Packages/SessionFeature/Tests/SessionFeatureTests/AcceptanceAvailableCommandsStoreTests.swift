import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

// task-3 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-3.md
// セッションが system/init で申告したコマンド一覧を、エージェント × 作業ディレクトリ単位で
// 永続化し、次回セッションの補完の種として取り出せるようにする。

private struct DefaultsSandboxUnavailable: Error {}

/// テスト専用の UserDefaults suite。`UserDefaults.standard` を汚さない。
private final class DefaultsSandbox {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "phlox.tests.availableCommands.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else { throw DefaultsSandboxUnavailable() }
        suiteName = name
        defaults = suite
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

@Suite("Acceptance: 利用可能コマンド一覧の永続ストア（task-3）")
struct AcceptanceAvailableCommandsStoreTests {

    private let claude = AgentRef.builtin(.claudeCode)

    // MARK: - 記録と取り出し

    @Test("記録した一覧を、同じエージェント・同じ作業ディレクトリで順序どおり取り出せる")
    func recordsAndReadsBack() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["ultrareview", "deep-research", "clear"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work")
            == ["ultrareview", "deep-research", "clear"])
    }

    @Test("未記録の組み合わせは nil を返す")
    func unrecordedCombinationReturnsNil() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == nil)
    }

    // MARK: - キーの分離

    @Test("エージェントが違えば取り出せない")
    func differentAgentDoesNotShareCommands() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["ultrareview"])

        #expect(store.commands(agentRef: .builtin(.codex), workingDirectory: "/tmp/work") == nil)
        #expect(store.commands(agentRef: .builtin(.cursor), workingDirectory: "/tmp/work") == nil)
    }

    @Test("カスタム CLI 同士も ID で分離される")
    func customAgentsAreSeparatedByID() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: .custom("my-cli"), workingDirectory: "/tmp/work", commands: ["mine"])

        #expect(store.commands(agentRef: .custom("my-cli"), workingDirectory: "/tmp/work") == ["mine"])
        #expect(store.commands(agentRef: .custom("other-cli"), workingDirectory: "/tmp/work") == nil)
    }

    @Test("作業ディレクトリが違えば取り出せない")
    func differentWorkingDirectoryDoesNotShareCommands() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work-a", commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work-b") == nil)
    }

    // MARK: - 作業ディレクトリの正規化

    @Test("nil と空文字は同じキーに解決される")
    func nilAndEmptyWorkingDirectoryShareOneKey() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: nil, commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: "") == ["ultrareview"])
    }

    @Test("チルダ表記と展開済みパスは同じキーに解決される")
    func tildePathAndExpandedPathShareOneKey() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        let expanded = ("~/phlox-store-test" as NSString).expandingTildeInPath

        store.record(agentRef: claude, workingDirectory: "~/phlox-store-test", commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: expanded) == ["ultrareview"])
    }

    @Test("末尾スラッシュの有無で別キーにならない")
    func trailingSlashDoesNotSplitKey() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work/", commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["ultrareview"])
    }

    @Test("相対要素を含むパスは解決してから同じキーに解決される")
    func relativeComponentsAreResolved() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work/sub/..", commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["ultrareview"])
    }

    // MARK: - 保存しない条件（既存値を壊さない）

    @Test("空配列は保存せず、既存値も消さない")
    func emptyCommandsAreNotStoredAndKeepPreviousValue() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["ultrareview"])
        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: [])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["ultrareview"],
                "空配列で既存の一覧を消さないこと")
    }

    @Test("空配列だけを記録した場合は nil のまま")
    func emptyCommandsAloneStoreNothing() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: [])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == nil)
    }

    @Test("300件までは保存する")
    func storesUpToThreeHundredCommands() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        let commands = (1...300).map { "command-\($0)" }

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: commands)

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work")?.count == 300)
    }

    @Test("301件以上は保存せず、既存値も消さない")
    func rejectsMoreThanThreeHundredCommandsAndKeepsPreviousValue() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["ultrareview"])
        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: (1...301).map { "command-\($0)" })

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["ultrareview"],
                "上限超過で既存の一覧を消さないこと")
    }

    // MARK: - 上書き

    @Test("同じキーへの再記録は全量で置き換える（後勝ち）")
    func recordReplacesWholeSnapshot() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["old-a", "old-b"])
        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["new-a"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["new-a"],
                "差分マージせず全量で置き換えること")
    }
}
