import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

// task-3 白箱テスト（実装者著）。受け入れテストが覆っていない内部の境界を固める。

private struct WhiteboxSandboxUnavailable: Error {}

/// テスト専用の UserDefaults suite。`UserDefaults.standard` を汚さない。
private final class WhiteboxDefaultsSandbox {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "phlox.tests.availableCommands.whitebox.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else { throw WhiteboxSandboxUnavailable() }
        suiteName = name
        defaults = suite
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

@Suite("Whitebox: AvailableCommandsStore の内部境界（task-3）")
struct AvailableCommandsStoreWhiteboxTests {

    private let claude = AgentRef.builtin(.claudeCode)

    // MARK: - キー形式

    @Test("キーは phlox.availableCommands.<agentID>.<正規化済み cwd> 形式になる")
    func keyFollowsDocumentedFormat() {
        #expect(AvailableCommandsStore.key(agentRef: .custom("my-cli"), workingDirectory: "/tmp/work")
            == "phlox.availableCommands.my-cli./tmp/work")
    }

    @Test("作業ディレクトリなしのキーは空の接尾辞で終わる")
    func keyForMissingWorkingDirectoryEndsWithEmptySuffix() {
        #expect(AvailableCommandsStore.key(agentRef: .custom("my-cli"), workingDirectory: nil)
            == "phlox.availableCommands.my-cli.")
    }

    // MARK: - 正規化

    @Test("ルート直下の連続スラッシュを畳んでもルート自身は残る")
    func rootPathSurvivesTrailingSlashTrimming() {
        #expect(AvailableCommandsStore.normalizedWorkingDirectory("/") == "/")
        #expect(AvailableCommandsStore.normalizedWorkingDirectory("///") == "/")
    }

    @Test("末尾スラッシュが複数あっても 1 つのキーに畳まれる")
    func multipleTrailingSlashesCollapse() {
        let single = AvailableCommandsStore.normalizedWorkingDirectory("/tmp/work")
        #expect(AvailableCommandsStore.normalizedWorkingDirectory("/tmp/work///") == single)
    }

    @Test("チルダ単体はホームディレクトリへ展開される")
    func bareTildeExpandsToHome() {
        let home = ("~" as NSString).expandingTildeInPath
        #expect(AvailableCommandsStore.normalizedWorkingDirectory("~") == home)
    }

    // MARK: - 上限の境界

    @Test("上限ちょうどの 300 件は保存される")
    func exactlyMaxCountIsStored() throws {
        let sandbox = try WhiteboxDefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        let commands = (1...AvailableCommandsStore.maxCommandCount).map { "command-\($0)" }

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: commands)

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == commands)
    }

    @Test("1 件だけの記録も保存される")
    func singleCommandIsStored() throws {
        let sandbox = try WhiteboxDefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: ["ultrareview"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work") == ["ultrareview"])
    }

    // MARK: - 副作用の局所性

    @Test("保存しない記録は UserDefaults に何のキーも作らない")
    func rejectedRecordWritesNothing() throws {
        let sandbox = try WhiteboxDefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: [])
        store.record(agentRef: claude, workingDirectory: "/tmp/work", commands: (1...301).map { "command-\($0)" })

        #expect(sandbox.defaults.object(forKey: AvailableCommandsStore.key(agentRef: claude,
                                                                          workingDirectory: "/tmp/work")) == nil)
    }

    @Test("あるキーへの記録は別の作業ディレクトリの既存値に影響しない")
    func recordDoesNotDisturbOtherWorkingDirectory() throws {
        let sandbox = try WhiteboxDefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        store.record(agentRef: claude, workingDirectory: "/tmp/work-a", commands: ["a"])
        store.record(agentRef: claude, workingDirectory: "/tmp/work-b", commands: ["b"])

        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work-a") == ["a"])
        #expect(store.commands(agentRef: claude, workingDirectory: "/tmp/work-b") == ["b"])
    }
}
