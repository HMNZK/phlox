import AppKit
import XCTest

/// 起動補助の追加入口を実アプリで確認する。UI改善そのものの受け入れ判定ではない。
@MainActor
final class IsolatedLaunchOptionsTests: XCTestCase {
    func testJapaneseDarkArgumentsReachApplication() async throws {
        try await observeEmpty(language: "ja", theme: "dracula", expectedText: "プロジェクトを追加してください")
    }

    func testEnglishLightArgumentsReachApplication() async throws {
        try await observeEmpty(language: "en", theme: "solarized-light", expectedText: "Add a project")
    }

    private func observeEmpty(language: String, theme: String, expectedText: String) async throws {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                        "-phlox.appLanguage", language, "-phlox.theme", theme]
        )
        let app = try isolated.application()
        XCTAssertTrue(app.staticTexts[expectedText].waitForExistence(timeout: 15), "所有アプリの表示言語が一致しない")
        try isolated.assertExclusiveOwnership()
        capture(app.windows.firstMatch, name: "appearance-\(language)-\(theme)")
    }

    func testSeededCustomSessionAppears() async throws {
        let name = "起動補助 検証会話"
        var preparations = 0
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja",
                                  "-phlox.appLanguage", "ja", "-phlox.theme", "dracula"],
            prepareData: { directory in
                preparations += 1
                let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "起動補助 検証プロジェクト",
                    "directoryPath": workspace.path, "createdAt": now,
                    "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "appearance-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": workspace.path,
                    "name": name, "startedAt": now, "command": "/bin/cat", "args": [String](),
                    "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "appearance-probe", "displayName": "起動補助確認", "binaryName": "cat",
                    "symbolName": "terminal", "colorHex": "#6080A0", "baseArgs": [String](),
                    "statusBootstrap": "idleOnSpawnComplete"
                ]
                for (filename, object) in [
                    ("projects.json", ["schemaVersion": 1, "projects": [project]] as [String: Any]),
                    ("sessions.json", ["schemaVersion": 1, "sessions": [session]] as [String: Any]),
                    ("agents.json", ["agents": [agent]] as [String: Any])
                ] {
                    try JSONSerialization.data(withJSONObject: object)
                        .write(to: directory.appendingPathComponent(filename), options: .withoutOverwriting)
                }
            }
        )
        XCTAssertEqual(preparations, 1)
        let app = try isolated.application()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), "専用dataのカスタムセッションが描画されない")
        try isolated.assertExclusiveOwnership()
        capture(app.windows.firstMatch, name: "appearance-seeded-session")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "起動補助確認, 待機"))
            .firstMatch.waitForExistence(timeout: 10), "会話名の表示だけではなく正常な待機状態が必要")
    }

    func testPreparationFailureDoesNotLaunchApplication() async throws {
        enum PreparationError: Error, Equatable { case expected }
        var preparations = 0
        do {
            _ = try await IsolatedPhloxApplication.launch(in: self, prepareData: { _ in
                preparations += 1
                throw PreparationError.expected
            })
            XCTFail("準備失敗が呼出元へ伝わっていない")
        } catch {
            XCTAssertEqual(error as? PreparationError, .expected)
        }
        XCTAssertEqual(preparations, 1)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "com.phlox.Phlox.debug").isEmpty)
    }

    private func capture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ISOLATED APPEARANCE \(name): \(window.debugDescription)")
    }
}
