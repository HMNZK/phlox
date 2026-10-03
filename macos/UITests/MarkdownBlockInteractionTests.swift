import XCTest

@MainActor
final class MarkdownBlockInteractionTests: XCTestCase {
    func testBlockEditingSaveAndModes() async throws {
        let (isolated, root) = try await launchDocument()
        let app = try isolated.application()
        let paragraph = app.staticTexts["編集前の本文"].firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        paragraph.click()
        let editor = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "編集前の本文")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("編集した本文\n\n追加行\n")
        app.typeKey("s", modifierFlags: .command)
        let expected = "# 見出し\r\n\r\n編集した本文\n\n追加行\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n"
        let saved = NSPredicate { _, _ in
            (try? Data(contentsOf: root.appendingPathComponent("document.md"))) == Data(expected.utf8)
        }
        let written = expectation(for: saved, evaluatedWith: nil)
        await fulfillment(of: [written], timeout: 5)
        XCTAssertTrue(app.staticTexts["編集した本文"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey("m", modifierFlags: [.control, .command])
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "[guide]: linked.md")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey("m", modifierFlags: [.control, .command])
        XCTAssertTrue(app.staticTexts["編集した本文"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["編集した本文"].firstMatch.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.textViews.count, 0)
    }

    func testReferenceLinkOpensFileWithoutEditing() async throws {
        let (isolated, _) = try await launchDocument()
        let app = try isolated.application()
        let link = app.links["案内"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        XCTAssertTrue(app.staticTexts["リンク先の見出し"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews.count, 0)
        XCTAssertFalse(app.staticTexts["未保存"].exists)
    }

    private func launchDocument() async throws -> (IsolatedPhloxApplication, URL) {
        var workspace: URL?
        let dataParent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/UITestData", isDirectory: true)
        try FileManager.default.createDirectory(at: dataParent, withIntermediateDirectories: true)
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            dataParent: dataParent, prepareData: { directory in
                let root = directory.appendingPathComponent("workspace", isDirectory: true)
                workspace = root
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let repository = Process()
                repository.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                repository.arguments = ["init", "--quiet", root.path]
                try repository.run()
                repository.waitUntilExit()
                XCTAssertEqual(repository.terminationStatus, 0)
                try Data("# 見出し\r\n\r\n編集前の本文\r\n\r\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n".utf8)
                    .write(to: root.appendingPathComponent("document.md"))
                try Data("# リンク先の見出し\n".utf8).write(to: root.appendingPathComponent("linked.md"))
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "マークダウン検証", "directoryPath": root.path,
                    "createdAt": now, "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "markdown-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": root.path,
                    "name": "マークダウン検証", "startedAt": now, "command": "/bin/cat",
                    "args": [String](), "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "markdown-probe", "displayName": "マークダウン検証", "binaryName": "cat",
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
        XCTAssertTrue(app.staticTexts["マークダウン検証"].firstMatch.waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        app.staticTexts["マークダウン検証"].firstMatch.click()
        app.typeKey("b", modifierFlags: [.control, .command])
        let row = app.descendants(matching: .any).matching(identifier: "file-tree-row-document.md").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.typeKey("i", modifierFlags: [.control, .command])
        return (isolated, try XCTUnwrap(workspace))
    }
}
