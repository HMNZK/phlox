import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Suite("画面配置の既定保存先の分離")
struct AcceptancePaneDefaultsIsolationTests {
    @Test("実環境のsuite指定・通常起動・明示注入を別プロセスで検査する")
    @MainActor
    func defaultStoreUsesApplicationSuite() async throws {
        let environment = ProcessInfo.processInfo.environment
        if let mode = environment["PHLOX_PANE_DEFAULTS_PROBE_MODE"] {
            let suite = try #require(environment["PHLOX_PANE_DEFAULTS_PROBE_SUITE"])
            let defaults = try #require(UserDefaults(suiteName: suite))
            // 空白付き名ではtrim後の所有ドメインを別ストアにして誤選択も検出する。
            let injectedSuite = suite.hasPrefix(" ")
                ? suite.trimmingCharacters(in: .whitespaces) : suite + ".injected"
            let injected = try #require(UserDefaults(suiteName: injectedSuite))
            defer {
                defaults.removePersistentDomain(forName: suite)
                injected.removePersistentDomain(forName: injectedSuite)
            }
            let tree = PaneLayoutPreset.columns2.tree(for: [SessionID(), SessionID()])
            let injectedTree = PaneLayoutPreset.rows3.tree(for: [SessionID(), SessionID(), SessionID()])
            PaneLayoutStore(userDefaults: defaults).save(tree)
            PaneLayoutStore(userDefaults: injected).save(injectedTree)
            // 通常側の非空入力は子プロセスのメモリ上だけで用意する。
            let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            if mode == "missing" || mode == "empty" {
                var arguments = originalArguments
                arguments[PaneLayoutStore.storageKey] = try JSONEncoder().encode(injectedTree)
                UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            }
            defer { UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }
            func standardSnapshot() -> NSDictionary {
                CFPreferencesCopyMultiple([PaneLayoutStore.storageKey] as CFArray,
                    kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as NSDictionary
            }
            let standardBefore = standardSnapshot()
            let workspace = try makeTemporaryWorkspaceRoot()
            defer { cleanupTemporaryWorkspaceRoot(workspace) }
            let (stream, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
            defer { continuation.finish() }
            let appEnvironment = makeTestEnvironment(
                pty: MockPTYManager(), hookStream: stream, workspaceDirectory: workspace
            )
            let dashboard: DashboardViewModel
            if mode == "explicit" {
                dashboard = DashboardViewModel(
                    environment: appEnvironment, paneLayoutStore: PaneLayoutStore(userDefaults: injected)
                )
            } else {
                dashboard = DashboardViewModel(environment: appEnvironment)
            }
            switch mode {
            case "suite", "explicit":
                // 既定の読取先が正しいと確認する前に、保存を伴うstartを呼ばない。
                try #require(dashboard.paneLayout == (mode == "suite" ? tree : injectedTree))
                await dashboard.start()
                #expect(dashboard.paneLayout.sessions.isEmpty)
                let selected = mode == "suite" ? defaults : injected
                #expect(PaneLayoutStore(userDefaults: selected).load() == dashboard.paneLayout)
                let untouched = mode == "suite" ? injected : defaults
                #expect(PaneLayoutStore(userDefaults: untouched).load() == (mode == "suite" ? injectedTree : tree))
            case "missing", "empty":
                // 通常設定は読取のみ。実ユーザーの値をテスト用に変更しない。
                #expect(dashboard.paneLayout == injectedTree)
                // 引数ドメインは他のUserDefaultsの検索にも優先されるため、保存値を直接読む。
                let persisted = try #require(defaults.persistentDomain(forName: suite)?[PaneLayoutStore.storageKey] as? Data)
                #expect(try JSONDecoder().decode(PaneTree.self, from: persisted) == tree)
            default:
                Issue.record("未知の検査モード")
            }
            #expect(standardSnapshot().isEqual(standardBefore))
            return
        }

        let bundleFlag = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
        let testBundle = CommandLine.arguments[bundleFlag + 1]
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (mode, paddedName) in [("suite", false), ("suite", true),
                                   ("missing", false), ("empty", false), ("explicit", false)] {
            let name = "phlox.pane-probe." + UUID().uuidString
            let suite = paddedName ? " \(name) " : name
            let injectedSuite = paddedName ? name : suite + ".injected"
            defer {
                UserDefaults.standard.removePersistentDomain(forName: suite)
                UserDefaults.standard.removePersistentDomain(forName: injectedSuite)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--test-bundle-path", testBundle, "--package-path", package.path,
                "--filter", "AcceptancePaneDefaultsIsolationTests.defaultStoreUsesApplicationSuite",
                testBundle, "--testing-library", "swift-testing"]
            var childEnvironment = environment
            childEnvironment["PHLOX_PANE_DEFAULTS_PROBE_MODE"] = mode
            childEnvironment["PHLOX_PANE_DEFAULTS_PROBE_SUITE"] = suite
            childEnvironment["PHLOX_DEFAULTS_SUITE"] = mode == "missing" ? nil : (mode == "empty" ? "" : suite)
            process.environment = childEnvironment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(mode)の別プロセス検査:\n\(log)")
        }
    }
}
