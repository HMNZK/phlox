import XCTest

@MainActor
final class FileTreeInteractionTests: XCTestCase {
    func testTreeRowsOpeningAndRefresh() async throws {
        var workspace: URL?
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            prepareData: { directory in
                let root = directory.appendingPathComponent("workspace", isDirectory: true)
                workspace = root
                try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
                for name in ["a.txt", "b.txt"] {
                    try Data("ファイルツリーの実画面検証".utf8).write(to: root.appendingPathComponent(name))
                }
                try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"),
                                                           withDestinationURL: URL(fileURLWithPath: "/usr"))
                try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("broken").path,
                                                           withDestinationPath: "missing")
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "ツリー検証", "directoryPath": root.path,
                    "createdAt": now, "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "file-tree-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": root.path,
                    "name": "ファイルツリー検証", "startedAt": now, "command": "/bin/cat",
                    "args": [String](), "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "file-tree-probe", "displayName": "ツリー検証", "binaryName": "cat",
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
        XCTAssertTrue(app.staticTexts["ファイルツリー検証"].waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        app.typeKey("b", modifierFlags: [.command, .control])
        func row(_ name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "file-tree-row-\(name)").firstMatch
        }
        XCTAssertTrue(row("folder").waitForExistence(timeout: 10))
        XCTAssertTrue(row("broken").exists)
        XCTAssertTrue(row("outside").exists)
        XCTAssertEqual(row("outside").label, "outside、作業ツリーの外を指すリンク、開けません")
        XCTAssertTrue(row("broken").label.hasPrefix("broken、開けません。"))
        row("outside").click()
        let blockedReason = app.staticTexts["file-tree-blocked-reason"]
        XCTAssertTrue(blockedReason.waitForExistence(timeout: 5))
        XCTAssertEqual(blockedReason.value as? String, "作業ツリーの外を指しているため開けません。→ /usr")
        capture(app, name: "ファイルツリー・空行なし・開けないリンク")

        row("b.txt").click()
        app.typeKey("i", modifierFlags: [.command, .control])
        app.typeKey("b", modifierFlags: [.command, .control])
        XCTAssertTrue(row("b.txt").waitForExistence(timeout: 5))
        capture(app, name: "ファイルツリー・開いたファイルの選択")

        try Data().write(to: XCTUnwrap(workspace).appendingPathComponent("new.txt"))
        let refresh = app.buttons.matching(NSPredicate(format: "label == %@", "更新")).firstMatch
        XCTAssertTrue(refresh.exists)
        refresh.click()
        XCTAssertTrue(row("new.txt").waitForExistence(timeout: 5))
        capture(app, name: "ファイルツリー・更新後")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
