import AppKit
import XCTest

@MainActor
final class BrowserTabInteractionTests: XCTestCase {
    func testLocalHTMLRunsJavaScriptInBrowserTab() async throws {
        let dataParent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/UITestData", isDirectory: true)
        try FileManager.default.createDirectory(at: dataParent, withIntermediateDirectories: true)
        var workspace: URL?
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            dataParent: dataParent,
            prepareData: { directory in
                let root = directory.appendingPathComponent("workspace", isDirectory: true)
                workspace = root
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let git = Process()
                git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                git.arguments = ["init", "--quiet", root.path]
                try git.run()
                git.waitUntilExit()
                XCTAssertEqual(git.terminationStatus, 0)
                try Data("<!doctype html><meta charset='utf-8'><h1 id='result'>実行前</h1><script>document.querySelector('#result').textContent='ブラウザで JavaScript 実行済み';</script>".utf8)
                    .write(to: root.appendingPathComponent("slides.html"))
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "ブラウザ検証", "directoryPath": root.path,
                    "createdAt": now, "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "browser-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": root.path,
                    "name": "ブラウザ表示検証", "startedAt": now, "command": "/bin/cat",
                    "args": [String](), "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "browser-probe", "displayName": "ブラウザ検証", "binaryName": "cat",
                    "symbolName": "terminal", "colorHex": "#6080A0", "baseArgs": [String](),
                    "statusBootstrap": "idleOnSpawnComplete"
                ]
                for (name, object) in [
                    ("projects.json", ["schemaVersion": 1, "projects": [project]] as [String: Any]),
                    ("sessions.json", ["schemaVersion": 1, "sessions": [session]] as [String: Any]),
                    ("agents.json", ["agents": [agent]] as [String: Any])
                ] {
                    try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent(name))
                }
            }
        )
        let app = try isolated.application()
        _ = try XCTUnwrap(workspace)
        XCTAssertTrue(app.staticTexts["ブラウザ表示検証"].waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        app.staticTexts["ブラウザ表示検証"].firstMatch.click()
        XCTAssertFalse(app.textFields["browser-address"].exists)
        app.typeKey("r", modifierFlags: [.command, .control])
        XCTAssertTrue(app.textFields["browser-address"].waitForExistence(timeout: 5), "⌃⌘R でブラウザを開く")
        app.typeKey("b", modifierFlags: [.command, .control])
        let row = app.descendants(matching: .any).matching(identifier: "file-tree-row-slides.html").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.typeKey("i", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["実行前"].waitForExistence(timeout: 15), "ファイルプレビューでは JavaScript を実行しない")
        let open = app.buttons["html-open-in-browser"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        XCTAssertTrue(app.staticTexts["ブラウザで JavaScript 実行済み"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["browser-address"].exists)
    }
}
