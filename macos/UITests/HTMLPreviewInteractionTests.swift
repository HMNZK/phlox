import XCTest

@MainActor
final class HTMLPreviewInteractionTests: XCTestCase {
    func testDraftSwitchReloadSaveLinksAndInspector() async throws {
        try await checkInteractions(hoverOnly: false)
    }

    func testHoverDestinationAfterOpening() async throws {
        try await checkInteractions(hoverOnly: true)
    }

    func testNativeMouseMovementReportsLink() async throws {
        try await checkInteractions(hoverOnly: true, hoverLink: "Browser link", hoverAction: "ブラウザで開く")
    }

    private func checkInteractions(hoverOnly: Bool, hoverLink: String = "Markdown link",
                                   hoverAction: String = "ファイルタブで開く") async throws {
        var workspace: URL?
        let initial = html(heading: "HTML_INITIAL")
        let draft = html(heading: "HTML_DRAFT")
        let saved = html(heading: "HTML_SAVED")
        let dataParent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/UITestData", isDirectory: true)
        try FileManager.default.createDirectory(at: dataParent, withIntermediateDirectories: true)
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            dataParent: dataParent,
            prepareData: { directory in
                let root = directory.appendingPathComponent("workspace", isDirectory: true)
                workspace = root
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                // フィクスチャを、親の作業ツリーとは別のGitルートにする。
                let repository = Process()
                repository.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                repository.arguments = ["init", "--quiet", root.path]
                try repository.run()
                repository.waitUntilExit()
                XCTAssertEqual(repository.terminationStatus, 0)
                for (name, text) in [
                    ("preview.html", initial), ("linked.htm", "<h1>HTML_LINKED</h1>"),
                    ("linked.md", "# MARKDOWN_SOURCE"), ("frame.html", "<h2>FRAME_INITIAL</h2>")
                ] {
                    try Data(text.utf8).write(to: root.appendingPathComponent(name))
                }
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "HTML検証", "directoryPath": root.path,
                    "createdAt": now, "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "html-preview-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": root.path,
                    "name": "HTML表示検証", "startedAt": now, "command": "/bin/cat",
                    "args": [String](), "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "html-preview-probe", "displayName": "HTML検証", "binaryName": "cat",
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
        let root = try XCTUnwrap(workspace)
        XCTAssertTrue(app.staticTexts["HTML表示検証"].waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        app.staticTexts["HTML表示検証"].firstMatch.click()
        app.typeKey("b", modifierFlags: [.command, .control])
        let row = app.descendants(matching: .any).matching(identifier: "file-tree-row-preview.html").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        guard row.exists else { return }
        row.click()
        app.typeKey("i", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_INITIAL"].waitForExistence(timeout: 15), "既定でHTMLを描画する")
        XCTAssertTrue(app.staticTexts["FRAME_INITIAL"].waitForExistence(timeout: 10), "作業フォルダのiframeを描画する")
        XCTAssertTrue(app.staticTexts["閲覧のみ"].exists)
        capture(app, name: "HTML・既定レンダリング")

        let isolation = app.buttons["外部の読み込みを止めています"]
        XCTAssertTrue(isolation.exists)
        isolation.click()
        XCTAssertTrue(app.staticTexts["このページが出す外部への要求と、ページのスクリプトは止めています"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        if hoverOnly {
            let link = app.links[hoverLink]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            guard link.exists else { return }
            link.hover()
            let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", hoverAction)).firstMatch
            let found = destination.waitForExistence(timeout: 5)
            capture(app, name: "HTML・初期表示直後のリンク先")
            XCTAssertTrue(found, "ホバー時にリンク先の開き方を表示する")
            return
        }

        app.buttons["ソース"].click()
        let editor = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "HTML_INITIAL")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        guard editor.exists else { return }
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(draft)
        XCTAssertTrue(app.staticTexts["未保存"].waitForExistence(timeout: 5))
        app.typeKey("m", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_DRAFT"].waitForExistence(timeout: 10), "未保存のdraftを表示する")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("preview.html"), encoding: .utf8), initial)
        capture(app, name: "HTML・未保存のdraft")

        try Data("<h2>FRAME_RELOADED</h2>".utf8).write(to: root.appendingPathComponent("frame.html"))
        app.buttons["再読込"].click()
        XCTAssertTrue(app.staticTexts["FRAME_RELOADED"].waitForExistence(timeout: 10), "再読込で作業フォルダ内の参照を読み直す")
        XCTAssertTrue(app.staticTexts["HTML_DRAFT"].exists, "再読込でdraftをディスクの内容へ戻さない")

        app.typeKey("m", modifierFlags: [.command, .control])
        let draftEditor = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "HTML_DRAFT")).firstMatch
        XCTAssertTrue(draftEditor.waitForExistence(timeout: 5))
        guard draftEditor.exists else { return }
        draftEditor.click()
        draftEditor.typeKey("a", modifierFlags: .command)
        draftEditor.typeText(saved)
        app.typeKey("s", modifierFlags: .command)
        let savedButton = app.buttons.matching(NSPredicate(format: "label == %@ AND enabled == false", "保存")).firstMatch
        XCTAssertTrue(savedButton.waitForExistence(timeout: 10))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("preview.html"), encoding: .utf8), saved)
        app.typeKey("m", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_SAVED"].waitForExistence(timeout: 10))
        capture(app, name: "HTML・保存後のdraft")

        app.links["HTML link"].click()
        XCTAssertTrue(app.staticTexts["HTML_LINKED"].waitForExistence(timeout: 10), ".htmのリンクをファイルタブで開く")
        app.typeKey("b", modifierFlags: [.command, .control])
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        app.typeKey("i", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_SAVED"].waitForExistence(timeout: 10))
        app.links["Markdown link"].click()
        XCTAssertTrue(app.staticTexts["MARKDOWN_SOURCE"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey("m", modifierFlags: [.command, .control])
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "MARKDOWN_SOURCE")).firstMatch.waitForExistence(timeout: 10))
        app.typeKey("b", modifierFlags: [.command, .control])
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        app.typeKey("i", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_SAVED"].waitForExistence(timeout: 10))

        let window = app.windows.firstMatch
        let resize = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        let narrow = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 758, dy: window.frame.height - 2))
        resize.click(forDuration: 0.2, thenDragTo: narrow)
        XCTAssertLessThan(window.frame.width, 800, "インスペクタを重ね表示にする幅へ縮める")
        app.typeKey("b", modifierFlags: [.command, .control])
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable, "WKWebViewより手前のインスペクタを操作できる")
        capture(app, name: "HTML・狭幅のインスペクタ重ね表示")
        row.click()
        app.typeKey("i", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["HTML_SAVED"].waitForExistence(timeout: 10))
        for label in ["レンダリング", "ソース", "保存", "再読込"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.exists, "狭幅でも操作と読み上げ名を残す: \(label)")
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.frame.maxX)
        }
        capture(app, name: "HTML・狭幅でインスペクタを閉じた後")

        for (label, action) in [("Markdown link", "ファイルタブで開く"), ("Browser link", "ブラウザで開く"), ("Unsupported link", "開きません")] {
            let link = app.links[label]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            guard link.exists else { return }
            link.hover()
            let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", action)).firstMatch
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "ホバー時にリンク先の開き方を表示する: \(label)")
            guard destination.exists else { return }
            capture(app, name: "HTML・リンク先・\(action)")
        }
    }

    private func html(heading: String) -> String {
        """
        <!doctype html><html><body style="font-family:system-ui;background:#f5f5f5;color:#222">
        <h1>\(heading)</h1>
        <p><a href="linked.md">Markdown link</a></p>
        <p><a href="linked.htm">HTML link</a></p>
        <p><a href="https://example.invalid/">Browser link</a></p>
        <p><a href="mailto:example@example.invalid">Unsupported link</a></p>
        <iframe src="frame.html" title="Local frame"></iframe>
        </body></html>
        """
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
