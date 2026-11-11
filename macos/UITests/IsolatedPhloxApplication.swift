import AppKit
import Security
import XCTest

/// GUIは起動コールバック、実行サービスは専用保存先の発見情報と署名から所有権を確認する。
@MainActor
final class IsolatedPhloxApplication {
    private static let bundleID = "com.phlox.Phlox.debug"
    private static let paneLayoutKey = "phlox.grid.paneLayout"
    private static let presetKey = "phlox.grid.paneLayoutPreset"
    private static let layoutStateKey = "phlox.grid.layoutState"
    private static let inspectorTabKey = "phlox.inspector.tab"

    private let appURL: URL
    private let executableURL: URL
    private let dataURL: URL
    private let suite = "phlox.uitest." + UUID().uuidString
    private let originalDefaults: NSDictionary
    private var owned: NSRunningApplication?
    private var ownedPID: pid_t?
    private var ownedRuntime: NSRunningApplication?
    private var runtimeExecutableURL: URL?
    private var launchError: Error?
    private var callbackReceived = false
    private var launchRequested = false
    private var abandoned = false
    private var cleanupTask: Task<Void, Never>?

    private enum Failure: Error {
        case unsafe(String)
    }

    private struct RuntimeDiscovery: Decodable {
        let pid: pid_t
        let storeURL: URL
    }

    private init(appURL: URL, executableURL: URL, dataParent: URL) throws {
        self.appURL = appURL
        self.executableURL = executableURL
        dataURL = dataParent.resolvingSymlinksInPath()
            .appendingPathComponent("phlox-uitest-" + UUID().uuidString, isDirectory: true)
        originalDefaults = try Self.drawerDefaults(in: Self.bundleID)
    }

    static func launch(
        in test: XCTestCase,
        arguments: [String] = [],
        dataParent: URL = FileManager.default.temporaryDirectory,
        testClaudeBinaryPath: String? = nil,
        testAgentBinaryPaths: ((URL) throws -> [String: String])? = nil,
        prepareData: ((URL) throws -> Void)? = nil
    ) async throws -> IsolatedPhloxApplication {
        // 設定文字列ではなく実行中Runnerの署名を検査。保存先の読み書きより先に拒否する。
        try requireUnsandboxedRunner()
        var directory = Bundle(for: Self.self).bundleURL
        var appURL: URL?
        for _ in 0..<6 {
            directory.deleteLastPathComponent()
            let candidate = directory.appendingPathComponent("Phlox.app", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                appURL = candidate.resolvingSymlinksInPath()
                break
            }
        }
        guard let appURL, let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == bundleID,
              let executable = bundle.executableURL?.resolvingSymlinksInPath(),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure.unsafe("実ビルド成果物のDebug Phlox.appを確認できない: \(directory.path)")
        }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard existing.isEmpty else {
            throw Failure.unsafe("既存Debugと競合。起動・接続・終了を拒否: \(describe(existing))")
        }

        let isolated = try Self(appURL: appURL, executableURL: executable, dataParent: dataParent)
        try FileManager.default.createDirectory(at: isolated.dataURL, withIntermediateDirectories: false)
        // 所有権取得より前に登録し、起動・接続・窓待ちのどこで失敗しても処理する。
        test.addTeardownBlock { await isolated.tearDown() }
        try prepareData?(isolated.dataURL)
        // 検査・削除はすべてcurrent user / any hostの同じ永続ドメインを使う。
        let seeded = try drawerDefaults(in: isolated.suite)
        guard seeded[presetKey] == nil, seeded[layoutStateKey] == nil, seeded[inspectorTabKey] == nil else {
            throw Failure.unsafe("専用suiteの起動前条件（設定の記録なし）が成立しない: \(seeded)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = [
            "PHLOX_DATA_DIR": isolated.dataURL.path,
            "PHLOX_DEFAULTS_SUITE": isolated.suite,
            "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN": "1",
            "PHLOX_TEST_EPHEMERAL_MOBILE_PORT": "1",
        ]
        var paths = try testAgentBinaryPaths?(isolated.dataURL) ?? [:]
        if let testClaudeBinaryPath { paths["claudeCode"] = testClaudeBinaryPath }
        if !paths.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: paths)
            configuration.environment["PHLOX_TEST_AGENT_BINARY_PATHS"] = String(decoding: data, as: UTF8.self)
        }
        print("Phlox UI isolation: data=\(isolated.dataURL.path) suite=\(isolated.suite)")
        print("Phlox UI standard before: domain=\(bundleID) protectedKeys=\(isolated.originalDefaults.count)")
        isolated.launchRequested = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { running, error in
            // SDKのコールバックは並行キュー上。状態変更と後始末はMainActorに直列化する。
            Task { @MainActor in
                isolated.owned = running
                isolated.ownedPID = running?.processIdentifier
                isolated.launchError = error
                isolated.callbackReceived = true
                if let running {
                    print("Phlox UI owner: \(describe([running])) suite=\(isolated.suite)")
                }
                if isolated.abandoned {
                    print("Phlox UI: 失敗後の遅延コールバック。成功へ反転せず所有アプリを後始末")
                    if let error { XCTFail("遅延した起動APIのエラー: \(error)") }
                    await isolated.cleanUp()
                }
            }
        }
        do {
            let deadline = Date().addingTimeInterval(30)
            while !isolated.callbackReceived && Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard isolated.callbackReceived else {
                throw Failure.unsafe("起動コールバックが30秒で未到着。所有権・残留を確認不能。候補は終了しない")
            }
            if let error = isolated.launchError { throw error }
            let runtimeDeadline = Date().addingTimeInterval(30)
            while !(try isolated.captureOwnedRuntime()) && Date() < runtimeDeadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard isolated.ownedRuntime != nil else {
                throw Failure.unsafe("専用実行サービスの所有権を30秒以内に確認できない")
            }
            let app = try isolated.application()
            let windowDeadline = Date().addingTimeInterval(30)
            while Date() < windowDeadline {
                try isolated.assertExclusiveOwnership()
                if app.windows.firstMatch.exists { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try isolated.assertExclusiveOwnership()
            guard app.windows.firstMatch.exists else {
                throw Failure.unsafe("所有Debugのウィンドウが30秒以内に表示されなかった")
            }
            try await isolated.assertDefaultsIsolation()
            return isolated
        } catch {
            isolated.abandoned = true
            throw error
        }
    }

    func application() throws -> XCUIApplication {
        try assertExclusiveOwnership()
        return XCUIApplication(url: appURL)
    }

    func assertExclusiveOwnership() throws {
        guard let owned, matchesOwner(owned), !owned.isTerminated else {
            throw Failure.unsafe("起動コールバックのPID・実行パスを確認できない。接続を拒否")
        }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard candidates.filter({ matchesOwner($0) }).count == 1,
              candidates.allSatisfy({ matchesOwner($0) || matchesRuntime($0) }) else {
            throw Failure.unsafe("Debugの接続対象が一意でない。GUI操作を拒否: \(Self.describe(candidates))")
        }
    }

    private func captureOwnedRuntime() throws -> Bool {
        if let ownedRuntime, !ownedRuntime.isTerminated { return true }
        let discoveryURL = dataURL.appendingPathComponent("session-runtime/discovery.json")
        guard FileManager.default.fileExists(atPath: discoveryURL.path) else { return false }
        let discovery = try JSONDecoder().decode(RuntimeDiscovery.self, from: Data(contentsOf: discoveryURL))
        guard discovery.pid > 0,
              dataURL.resolvingSymlinksInPath().path == dataURL.path,
              discovery.storeURL.resolvingSymlinksInPath().path == dataURL.path else {
            throw Failure.unsafe("実行サービスの発見情報が専用保存先と一致しない")
        }
        guard let runtime = NSRunningApplication(processIdentifier: discovery.pid), !runtime.isTerminated else {
            return false
        }
        let bundles = dataURL.appendingPathComponent("session-runtime-bundles").resolvingSymlinksInPath()
        guard bundles.deletingLastPathComponent().path == dataURL.path,
              runtime.bundleIdentifier == Self.bundleID,
              let bundleURL = runtime.bundleURL?.resolvingSymlinksInPath(),
              bundleURL.deletingLastPathComponent().path == bundles.path,
              let executable = runtime.executableURL?.resolvingSymlinksInPath(),
              executable == Bundle(url: bundleURL)?.executableURL?.resolvingSymlinksInPath() else {
            throw Failure.unsafe("実行サービスのPID・bundle・実行パスが専用保存先と一致しない")
        }
        var originalCode: SecStaticCode?
        var runtimeCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &originalCode) == errSecSuccess,
              let originalCode,
              SecCodeCopyDesignatedRequirement(originalCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &runtimeCode) == errSecSuccess,
              let runtimeCode,
              SecStaticCodeCheckValidity(runtimeCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw Failure.unsafe("専用実行サービスの署名が起動したアプリと一致しない")
        }
        ownedRuntime = runtime
        runtimeExecutableURL = executable
        print("Phlox UI runtime owner: \(Self.describe([runtime])) data=\(dataURL.path)")
        return true
    }

    private func matchesRuntime(_ running: NSRunningApplication) -> Bool {
        ownedRuntime != nil && running.isEqual(ownedRuntime) && !running.isTerminated
            && running.bundleIdentifier == Self.bundleID
            && running.executableURL?.resolvingSymlinksInPath() == runtimeExecutableURL
    }

    private func matchesOwner(_ running: NSRunningApplication) -> Bool {
        running.isEqual(owned) && running.processIdentifier > 0 && running.processIdentifier == ownedPID
            && running.bundleIdentifier == Self.bundleID
            && running.executableURL?.resolvingSymlinksInPath() == executableURL
    }

    private static func describe(_ applications: [NSRunningApplication]) -> String {
        applications.map {
            "pid=\($0.processIdentifier) executable=\($0.executableURL?.path ?? "確認不能")"
        }.joined(separator: ", ")
    }

    private static func requireUnsandboxedRunner() throws {
        guard let task = SecTaskCreateFromSelf(nil) else {
            throw Failure.unsafe("実行中Runnerの署名を取得できない。保存先準備・起動・接続を拒否")
        }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, &error)
        if let error {
            throw Failure.unsafe("Runnerのsandbox権限取得に失敗。起動を拒否: \(error.takeRetainedValue())")
        }
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID(), CFEqual(value, kCFBooleanFalse) else {
            throw Failure.unsafe("Runnerのapp-sandbox=falseを確認できない（有効・欠落・型不正）。保存先準備・起動・接続を拒否")
        }
        print("Phlox UI Runner: pid=\(ProcessInfo.processInfo.processIdentifier) app-sandbox=false (SecTask)")
    }

    /// 他プロセスが保存した値を、検索順や登録既定値を含めず永続ドメインから読む。
    private static func drawerDefaults(in domain: String) throws -> NSDictionary {
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw Failure.unsafe("defaultsの同期に失敗: \(domain)")
        }
        let values = CFPreferencesCopyMultiple(
            nil, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) as NSDictionary
        var protected: [String: Any] = [:]
        for (rawKey, value) in values {
            guard let key = rawKey as? String else { continue }
            if key == presetKey || key == paneLayoutKey || key == layoutStateKey || key == inspectorTabKey || key.hasPrefix("SU")
                || key == "phlox.theme" || key == "phlox.appLanguage"
                || key == "AppleLanguages" || key == "AppleLocale" {
                protected[key] = value
            }
        }
        return protected as NSDictionary
    }

    private func assertStandardUnchanged() throws {
        let current = try Self.drawerDefaults(in: Self.bundleID)
        guard current.isEqual(originalDefaults) else {
            throw Failure.unsafe("通常Debugの保護対象設定が変化")
        }
    }

    private func assertDefaultsIsolation() async throws {
        let app = try application()
        guard app.checkBoxes["inspector-toggle"].firstMatch.waitForExistence(timeout: 30) else {
            throw Failure.unsafe("設定の隔離を検証するダッシュボードが表示されない")
        }
        // 自動配置は起動時に保存しない。実際の設定操作で専用suiteへの書込みを確認する。
        try assertExclusiveOwnership()
        app.typeKey("g", modifierFlags: [.shift, .control, .command])
        try await assertStoredInspectorTab("git")
        try assertExclusiveOwnership()
        app.typeKey("b", modifierFlags: [.control, .command])
        try await assertStoredInspectorTab("files")
        try assertExclusiveOwnership()
        app.typeKey("i", modifierFlags: [.control, .command])
        print("Phlox UI defaults: suite=\(suite) inspectorTab=files standard=unchanged")
    }

    private func assertStoredInspectorTab(_ expected: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        var saved: NSDictionary = [:]
        repeat {
            try assertExclusiveOwnership()
            try assertStandardUnchanged()
            saved = try Self.drawerDefaults(in: suite)
            if saved[Self.inspectorTabKey] as? String == expected { return }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        throw Failure.unsafe("専用suiteに設定の変更が保存されない: suite=\(suite) expected=\(expected) values=\(saved)")
    }

    private func tearDown() async {
        abandoned = true
        if !launchRequested { await cleanUp(); return }
        // 起動要求はキャンセル不能。遅延通知を有限時間待ち、その後もcallback側に後始末を残す。
        let deadline = Date().addingTimeInterval(10)
        while !callbackReceived && Date() < deadline {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch {
                XCTFail("後始末のコールバック待機が中断: \(error)")
                return
            }
        }
        guard callbackReceived else {
            XCTFail("起動結果が未到着。所有権・残留を確認不能、候補を終了せず隔離データを保持: \(dataURL.path)")
            return
        }
        await cleanUp()
    }

    private func cleanUp() async {
        if let cleanupTask { await cleanupTask.value; return }
        let task = Task { @MainActor in
            // 遅延callbackとteardownが同時に来ても、終了要求と削除は一度だけ。
            do {
                defer {
                    do {
                        try self.assertStandardUnchanged()
                        print("Phlox UI standard after: domain=\(Self.bundleID) protectedKeys=\(self.originalDefaults.count) unchanged=true")
                    }
                    catch { XCTFail("後始末時の通常Debug保存先検査に失敗: \(error)") }
                }
                let capturedRuntime = try self.captureOwnedRuntime()
                if let owned = self.owned {
                    guard self.matchesOwner(owned) else {
                        throw Failure.unsafe("所有PID・実行パスの照合失敗。終了せず残留を報告: \(Self.describe([owned]))")
                    }
                    if !owned.isTerminated {
                        do { try self.assertExclusiveOwnership() }
                        catch { XCTFail("終了前の接続対象検査に失敗: \(error)") }
                        guard owned.terminate() else {
                            throw Failure.unsafe("所有Debugが正常終了要求を拒否: \(Self.describe([owned]))")
                        }
                        let deadline = Date().addingTimeInterval(10)
                        while !owned.isTerminated && Date() < deadline {
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        guard owned.isTerminated else {
                            throw Failure.unsafe("所有Debugの正常終了を確認できず残留: \(Self.describe([owned]))")
                        }
                    }
                    print("Phlox UI terminated: pid=\(owned.processIdentifier) executable=\(self.executableURL.path)")
                } else if self.launchRequested && self.launchError == nil {
                    throw Failure.unsafe("起動結果にアプリもエラーもなく所有権・残留を確認不能")
                }
                guard !self.launchRequested || capturedRuntime else {
                    throw Failure.unsafe("起動を要求した実行サービスの所有権を確認できないため専用保存先を保持")
                }
                if let runtime = self.ownedRuntime, !runtime.isTerminated {
                    guard self.matchesRuntime(runtime), runtime.terminate() else {
                        throw Failure.unsafe("所有実行サービスが一致しないか正常終了要求を拒否")
                    }
                    let deadline = Date().addingTimeInterval(15)
                    while !runtime.isTerminated && Date() < deadline {
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    guard runtime.isTerminated else {
                        throw Failure.unsafe("所有実行サービスが終了していないため専用保存先を保持")
                    }
                    print("Phlox UI runtime terminated: pid=\(runtime.processIdentifier)")
                }
                let prefix = self.dataURL.resolvingSymlinksInPath().path + "/"
                let remaining = NSWorkspace.shared.runningApplications.filter {
                    !$0.isTerminated && $0.executableURL?.resolvingSymlinksInPath().path.hasPrefix(prefix) == true
                }
                guard remaining.isEmpty else {
                    throw Failure.unsafe("専用保存先を使うアプリが残っているため保持: \(Self.describe(remaining))")
                }
                let keys = CFPreferencesCopyKeyList(self.suite as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                CFPreferencesSetMultiple(nil, keys, self.suite as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                guard CFPreferencesSynchronize(self.suite as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                    throw Failure.unsafe("専用suite削除の同期に失敗: \(self.suite)")
                }
                try FileManager.default.removeItem(at: self.dataURL)
            } catch {
                XCTFail("隔離Debugの後始末に失敗（強制終了はしない）: \(error)")
            }
        }
        cleanupTask = task
        await task.value
    }
}
