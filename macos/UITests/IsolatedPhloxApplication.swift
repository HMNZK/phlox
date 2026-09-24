import AppKit
import Security
import XCTest

/// この3件のUIテスト専用。所有権は起動コールバックの戻り値だけから取得する。
@MainActor
final class IsolatedPhloxApplication {
    private static let bundleID = "com.phlox.Phlox.debug"
    private static let paneLayoutKey = "phlox.grid.paneLayout"
    /// 起動時にアプリが必ず保存するグリッド配置の記録（PaneLayoutStore.presetStorageKey）。
    /// 専用 suite にこれが書かれ、通常の保存先が変わらないことで、設定の隔離を確かめる。
    /// （以前はパネル幅の移行を目印にしていたが、その処理は 02 案 C のタブ再設計でパネルごと無くなった）
    private static let presetKey = "phlox.grid.paneLayoutPreset"

    private let appURL: URL
    private let executableURL: URL
    private let dataURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-uitest-" + UUID().uuidString, isDirectory: true)
    private let suite = "phlox.uitest." + UUID().uuidString
    private let originalDefaults: NSDictionary
    private var owned: NSRunningApplication?
    private var ownedPID: pid_t?
    private var launchError: Error?
    private var callbackReceived = false
    private var launchRequested = false
    private var abandoned = false
    private var cleanupTask: Task<Void, Never>?

    private enum Failure: Error {
        case unsafe(String)
    }

    private init(appURL: URL, executableURL: URL) throws {
        self.appURL = appURL
        self.executableURL = executableURL
        originalDefaults = try Self.drawerDefaults(in: Self.bundleID)
    }

    static func launch(
        in test: XCTestCase,
        arguments: [String] = [],
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

        let isolated = try Self(appURL: appURL, executableURL: executable)
        try FileManager.default.createDirectory(at: isolated.dataURL, withIntermediateDirectories: false)
        // 所有権取得より前に登録し、起動・接続・窓待ちのどこで失敗しても処理する。
        test.addTeardownBlock { await isolated.tearDown() }
        try prepareData?(isolated.dataURL)
        // 検査・削除はすべてcurrent user / any hostの同じ永続ドメインを使う。
        let seeded = try drawerDefaults(in: isolated.suite)
        guard seeded[presetKey] == nil else {
            throw Failure.unsafe("専用suiteの起動前条件（グリッド配置の記録なし）が成立しない: \(seeded)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = [
            "PHLOX_DATA_DIR": isolated.dataURL.path,
            "PHLOX_DEFAULTS_SUITE": isolated.suite,
            "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN": "1",
        ]
        let agentsURL = isolated.dataURL.appendingPathComponent("agents.json")
        if FileManager.default.fileExists(atPath: agentsURL.path) {
            configuration.environment["PHLOX_AGENTS_JSON"] = agentsURL.path
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
        guard candidates.count == 1, let candidate = candidates.first,
              matchesOwner(candidate) else {
            throw Failure.unsafe("Debugの接続対象が一意でない。GUI操作を拒否: \(Self.describe(candidates))")
        }
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
            if key == presetKey || key == paneLayoutKey || key.hasPrefix("SU")
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
            throw Failure.unsafe("通常Debugの保護対象設定（グリッド配置・更新確認）が変化")
        }
    }

    private func assertDefaultsIsolation() async throws {
        let deadline = Date().addingTimeInterval(10)
        var saved: NSDictionary = [:]
        repeat {
            try assertExclusiveOwnership()
            try assertStandardUnchanged()
            saved = try Self.drawerDefaults(in: suite)
            if let data = saved[Self.presetKey] as? Data,
               let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               record["preset"] is String {
                print("Phlox UI defaults: suite=\(suite) paneLayoutPreset=saved standard=unchanged")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        throw Failure.unsafe("専用suiteにグリッド配置の記録が保存されない: suite=\(suite) values=\(saved)")
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
