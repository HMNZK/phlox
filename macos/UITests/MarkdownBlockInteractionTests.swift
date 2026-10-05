import AppKit
import XCTest

@MainActor
final class MarkdownBlockInteractionTests: XCTestCase {
    func testLargeHTMLSourceEditsSavesAndUndoes() async throws {
        let original = Data(String(repeating: "<!doctype html>\n<!-- 大容量編集の検証 -->\n", count: 30_000).utf8)
        XCTAssertGreaterThan(original.count, 1_000_000)
        let (isolated, root) = try await launchDocument(filename: "large.html", contents: original)
        let app = try isolated.application()
        app.typeKey("m", modifierFlags: [.control, .command])
        let notice = app.descendants(matching: .any).matching(identifier: "large-file-plain-notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        let editor = app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", "<!doctype html>")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("x")
        app.typeKey("s", modifierFlags: .command)
        let file = root.appendingPathComponent("large.html")
        let edited = original + Data("x".utf8)
        let saved = expectation(for: NSPredicate { _, _ in
            (try? Data(contentsOf: file)) == edited && !app.staticTexts["未保存"].exists
        }, evaluatedWith: nil)
        await fulfillment(of: [saved], timeout: 10)
        editor.typeKey("z", modifierFlags: .command)
        app.typeKey("s", modifierFlags: .command)
        let restored = expectation(for: NSPredicate { _, _ in
            (try? Data(contentsOf: file)) == original && !app.staticTexts["未保存"].exists
        }, evaluatedWith: nil)
        await fulfillment(of: [restored], timeout: 10)
    }

    func testFileOverHardLimitShowsUnavailableState() async throws {
        let (isolated, _) = try await launchDocument(filename: "too-large.txt", contents: Data(repeating: 65, count: 20_000_001))
        let app = try isolated.application()
        XCTAssertTrue(app.staticTexts["ファイルが大きすぎるため開けません"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["20MB+"].exists)
        XCTAssertTrue(app.buttons["既定のアプリで開く"].exists)
        XCTAssertFalse(app.buttons["保存"].exists)
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", "AAAAAAAA")).firstMatch.exists)
    }

    func testLargeFileReadOnlyKeepsSelectionAndSavedBytes() async throws {
        let unit = "閲覧専用の先頭行\n"
        let original = Data((unit + String(repeating: "a", count: 10_001) + "隠す末尾\n" + String(repeating: "次の行\n", count: 500_000) + "検索の目印\n").utf8)
        XCTAssertGreaterThan(original.count, 5_000_000)
        XCTAssertLessThanOrEqual(original.count, 20_000_000)
        let (isolated, root) = try await launchDocument(filename: "read-only.txt", contents: original)
        let app = try isolated.application()
        let notice = app.descendants(matching: .any).matching(identifier: "large-file-read-only-notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        let editor = app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", unit)).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let displayed = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(displayed.contains("…（残り 5 文字を省略）"))
        XCTAssertFalse(displayed.contains("隠す末尾"))
        // 帯の案内文は help（AX の value）として公開される。
        XCTAssertTrue((notice.value as? String)?.contains("長い行は省略して表示") == true)
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("c", modifierFlags: .command)
        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(copied.hasPrefix(unit))
        XCTAssertTrue(copied.contains("…（残り 5 文字を省略）"), "コピーは表示中の文字列が対象")
        XCTAssertFalse(copied.contains("隠す末尾"))
        editor.typeKey("v", modifierFlags: .command)
        editor.typeText("入力は禁止")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("read-only.txt")), original)
        XCTAssertFalse(app.staticTexts["未保存"].exists)
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        // 検索欄はシステム共通の検索語を引き継ぐので、前回の実行の検索語を消してから開く。
        NSPasteboard(name: .find).clearContents()
        defer { NSPasteboard(name: .find).clearContents() }
        editor.click()
        editor.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.typeText("検索の目印")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        editor.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "検索の目印")
        editor.scroll(byDeltaX: 0, deltaY: -300)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("read-only.txt")), original)
    }

    func testSourceHighlightingKeepsUndoAndSavedBytes() async throws {
        let (isolated, root) = try await launchDocument()
        let app = try isolated.application()
        let file = root.appendingPathComponent("document.md")
        let originalBytes = try Data(contentsOf: file)
        app.typeKey("m", modifierFlags: [.control, .command])
        let editor = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "[guide]: linked.md")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let originalText = try XCTUnwrap(editor.value as? String)
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("x")
        XCTAssertEqual(editor.value as? String, originalText + "x")
        editor.typeKey("z", modifierFlags: .command)
        let restored = expectation(for: NSPredicate { _, _ in
            editor.value as? String == originalText
        }, evaluatedWith: nil)
        await fulfillment(of: [restored], timeout: 5)
        app.typeKey("s", modifierFlags: .command)
        let saved = expectation(for: NSPredicate { _, _ in
            (try? Data(contentsOf: file)) == originalBytes && !app.staticTexts["未保存"].exists
        }, evaluatedWith: nil)
        await fulfillment(of: [saved], timeout: 5)
    }

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

    private func launchDocument(filename: String = "document.md", contents: Data? = nil) async throws -> (IsolatedPhloxApplication, URL) {
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
                try (contents ?? Data("# 見出し\r\n\r\n編集前の本文\r\n\r\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n".utf8))
                    .write(to: root.appendingPathComponent(filename))
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
        let row = app.descendants(matching: .any).matching(identifier: "file-tree-row-\(filename)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.typeKey("i", modifierFlags: [.control, .command])
        return (isolated, try XCTUnwrap(workspace))
    }
}
