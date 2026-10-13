import AppKit
import XCTest

@MainActor
final class UnifiedNewChatUITests: XCTestCase {
    private func launchFixture(prepareData: ((URL) throws -> Void)? = nil) async throws -> IsolatedPhloxApplication {
        return try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja", "-AppleKeyboardUIMode", "3"],
            testAgentBinaryPaths: { directory in
                guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
                    throw NSError(domain: "UnifiedNewChatUITests", code: 8,
                                  userInfo: [NSLocalizedDescriptionKey: "structured fake用の/usr/bin/python3がない"])
                }
                let fake = directory.appendingPathComponent("fake-claude.py")
                try Self.structuredFakeClaude.write(to: fake, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
                return ["claudeCode": fake.path]
            },
            prepareData: { directory in
                let now = Date().timeIntervalSinceReferenceDate
                let projects = try ["Aster", "Cedar"].enumerated().map { index, name -> [String: Any] in
                    let root = directory.appendingPathComponent(name, isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                    let git = Process()
                    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    git.arguments = ["-C", root.path, "init", "-q", "--initial-branch=main"]
                    try git.run()
                    git.waitUntilExit()
                    guard git.terminationStatus == 0 else {
                        throw NSError(domain: "UnifiedNewChatUITests", code: Int(git.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: "Git fixture initialization failed: \(root.path)"])
                    }
                    let commit = Process()
                    commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    commit.arguments = [
                        "-C", root.path, "-c", "user.name=Phlox UI Fixture",
                        "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
                        "commit", "--allow-empty", "-q", "-m", "テスト用初期コミット",
                    ]
                    try commit.run()
                    commit.waitUntilExit()
                    guard commit.terminationStatus == 0 else {
                        throw NSError(domain: "UnifiedNewChatUITests", code: Int(commit.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: "Git fixture initial commit failed: \(root.path)"])
                    }
                    return [
                        "id": ["rawValue": UUID().uuidString],
                        "name": name,
                        "directoryPath": root.path,
                        "createdAt": now + Double(index),
                        "isManagedDirectory": false,
                        "worktreeIsolationEnabled": false,
                    ]
                }
                for (filename, object) in [
                    ("projects.json", ["schemaVersion": 1, "projects": projects] as [String: Any]),
                    ("sessions.json", ["schemaVersion": 1, "sessions": [[String: Any]]()] as [String: Any]),
                ] {
                    try JSONSerialization.data(withJSONObject: object)
                        .write(to: directory.appendingPathComponent(filename), options: .withoutOverwriting)
                }
                try prepareData?(directory)
            }
        )
    }

    func testKeyboardNewChatAndProjectTabSwitching() async throws {
        let isolated = try await launchFixture()
        let app = try isolated.application()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let firstProject = app.buttons["tabs.project.1"].firstMatch
        let secondProject = app.buttons["tabs.project.2"].firstMatch
        XCTAssertTrue(firstProject.waitForExistence(timeout: 10))
        XCTAssertTrue(secondProject.exists, "2つ目のプロジェクトタブが見つからない")
        firstProject.click()
        try isolated.assertExclusiveOwnership()
        app.typeKey("n", modifierFlags: .command)

        let message = app.descendants(matching: .any)["newChat.messageInput"]
        try requireExists(message, "新規チャットの入力欄が表示されない")
        XCTAssertEqual(message.label, "メッセージ", "入力欄の役割を読み上げられない")
        try typeUsingKeyboard("作業内容を確認してください", into: message, app: app)
        XCTAssertEqual(message.value as? String, "作業内容を確認してください", "入力欄の値を読み上げられない")

        let harness = app.buttons["newChat.harnessModelPicker"]
        XCTAssertTrue(harness.waitForExistence(timeout: 10))
        XCTAssertEqual(harness.label, "ハーネスとモデル")
        XCTAssertTrue((harness.value as? String)?.contains("Claude Code") == true)
        try focusUsingKeyboard(harness, app: app)
        app.typeKey(.space, modifierFlags: [])
        let search = app.textFields["newChat.modelSearch"]
        try requireExists(search, "モデルメニューが開かない")
        try typeUsingKeyboard("Sonnet", into: search, app: app)
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        let effort = app.descendants(matching: .any)["newChat.effortPicker"]
        let permission = app.descendants(matching: .any)["newChat.permissionPicker"]
        let overflow = app.descendants(matching: .any)["newChat.settingsOverflow"]
        let project = app.descendants(matching: .any)["newChat.projectPicker"]
        let workspace = app.descendants(matching: .any)["newChat.workspacePicker"]
        // 既定の 900pt の窓では effort・権限を「…」へ畳む（要件 E6）。
        if overflow.exists {
            XCTAssertEqual(overflow.label, "設定")
            XCTAssertTrue((overflow.value as? String)?.contains("、") == true, "畳んだ effort・権限の値を読み上げられない")
        } else {
            XCTAssertEqual(effort.label, "推論の深さ")
            XCTAssertTrue((effort.value as? String)?.isEmpty == false)
            XCTAssertEqual(permission.label, "権限")
            XCTAssertTrue((permission.value as? String)?.isEmpty == false)
        }
        XCTAssertEqual(project.label, "プロジェクト")
        XCTAssertEqual(project.value as? String, "Aster")
        XCTAssertEqual(workspace.label, "作業場所")
        XCTAssertEqual(workspace.value as? String, "既存ディレクトリ")

        try selectNewWorktreeUsingKeyboard(workspace, app: app)

        try focusUsingKeyboard(message, app: app, backwards: true)
        app.typeKey(.return, modifierFlags: [])
        let sessionTab = app.buttons["tabs.item.1"].firstMatch
        XCTAssertTrue(sessionTab.waitForExistence(timeout: 20), "送信後にセッションタブができない")
        XCTAssertNotEqual(sessionTab.label, "新規チャット")

        try isolated.assertExclusiveOwnership()
        app.typeKey("]", modifierFlags: [.command, .shift])
        let newProjectPicker = app.descendants(matching: .any)["newChat.projectPicker"]
        XCTAssertTrue(newProjectPicker.waitForExistence(timeout: 10), "2つ目のプロジェクトの新規チャットが表示されない")
        XCTAssertEqual(newProjectPicker.value as? String, "Cedar", "⌘⇧] で次のプロジェクトへ切り替わらない")
        XCTAssertTrue(app.buttons["tabs.project.1"].exists)
        XCTAssertTrue(app.buttons["tabs.project.2"].exists)
        try isolated.assertExclusiveOwnership()
    }

    func testStructuredFakeRepliesWithValidClaudeEvents() throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", Self.structuredFakeClaude]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("""
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
        {"type":"control_request","request_id":"ui-control","request":{"subtype":"set_permission_mode"}}

        """.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let events = try data.split(separator: 0x0A).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
        XCTAssertEqual(events.compactMap { $0["type"] as? String }, ["system", "assistant", "result", "control_response"])
        let result = try XCTUnwrap(events.first { $0["type"] as? String == "result" })
        XCTAssertEqual(result["subtype"] as? String, "success")
        XCTAssertEqual(result["is_error"] as? Bool, false)
        let response = try XCTUnwrap(events.last?["response"] as? [String: Any])
        XCTAssertEqual(response["request_id"] as? String, "ui-control")
    }

    func testProjectAndSessionCloseRequireConfirmationAndRemoveSidebarRows() async throws {
        let isolated = try await launchFixture()
        let app = try isolated.application()
        addTeardownBlock { @MainActor in
            try isolated.assertExclusiveOwnership()
            let sheet = app.sheets.firstMatch
            if sheet.exists {
                let cancel = sheet.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "キャンセル")).firstMatch
                guard cancel.exists else {
                    throw NSError(domain: "UnifiedNewChatUITests", code: 9,
                                  userInfo: [NSLocalizedDescriptionKey: "所有アプリの確認sheetをキャンセルできない"])
                }
                cancel.click()
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "後始末で削除確認sheetを閉じられない")
            }
        }
        app.buttons["tabs.project.1"].firstMatch.click()
        let sessionName = try sendNewChat("削除確認の会話", index: 1, app: app, isolated: isolated)
        let sidebarSession = sidebarSession(named: sessionName, app: app)
        XCTAssertTrue(sidebarSession.waitForExistence(timeout: 10))

        // 下段は子の AX 要素をまとめているため、表示中の ✕（右端の 14pt）を押す。
        let sessionTab = app.buttons["tabs.item.1"].firstMatch
        sessionTab.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -13, dy: 0)).click()
        let sheet = app.sheets.firstMatch
        let delete = sheet.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "削除")).firstMatch
        let cancel = sheet.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "キャンセル")).firstMatch
        try requireExists(delete, "下段の ✕ から削除確認が開かない")
        XCTAssertTrue(sidebarSession.exists, "確認前にセッションが消えた")
        cancel.click()
        try requireClosed(sheet, "キャンセル後も削除確認が残る")
        XCTAssertTrue(sidebarSession.exists, "キャンセルでセッションが消えた")
        sessionTab.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -13, dy: 0)).click()
        try requireExists(delete, "下段の ✕ から削除確認が開かない")
        delete.click()
        try requireClosed(sheet, "削除後も確認sheetが残る")
        XCTAssertTrue(sidebarSession.waitForNonExistence(timeout: 10), "削除後もサイドバーにセッションが残る")
        let deletedTab = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tabs.item.' AND label == %@", sessionName)).firstMatch
        XCTAssertTrue(deletedTab.waitForNonExistence(timeout: 10), "削除後も下段にセッションが残る")

        let sidebarProject = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "プロジェクト Aster、")).firstMatch
        XCTAssertTrue(sidebarProject.exists)
        let projectTab = app.buttons["tabs.project.1"].firstMatch
        projectTab.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -10, dy: 0)).click()
        try requireExists(delete, "上段の ✕ から削除確認が開かない")
        XCTAssertTrue(sidebarProject.exists, "確認前にプロジェクトが消えた")
        cancel.click()
        try requireClosed(sheet, "キャンセル後も削除確認が残る")
        XCTAssertTrue(sidebarProject.exists)
        projectTab.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -10, dy: 0)).click()
        try requireExists(delete, "上段の ✕ から削除確認が開かない")
        delete.click()
        try requireClosed(sheet, "削除後も確認sheetが残る")
        XCTAssertTrue(sidebarProject.waitForNonExistence(timeout: 10), "削除後もサイドバーにプロジェクトが残る")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tabs.project.' AND label == %@", "Aster")).firstMatch.exists)
        XCTAssertTrue(app.buttons["tabs.project.1"].exists, "残りの Cedar タブまで消えた")
        try isolated.assertExclusiveOwnership()
    }

    func testChildTabKeyboardSwitchingKeepsSidebarSelectionInSync() async throws {
        let isolated = try await launchFixture()
        let app = try isolated.application()
        app.buttons["tabs.project.1"].firstMatch.click()
        var names: [String] = []
        for index in 1...9 {
            names.append(try sendNewChat("切り替え確認 \(index)", index: index, app: app, isolated: isolated))
        }

        for index in 1...9 {
            app.typeKey(String(index), modifierFlags: .command)
            assertCurrentSidebarSession(names[index - 1], app: app)
        }
        app.typeKey("1", modifierFlags: .command)
        app.typeKey(.tab, modifierFlags: .control)
        assertCurrentSidebarSession(names[1], app: app)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        assertCurrentSidebarSession(names[0], app: app)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        assertCurrentSidebarSession(names[8], app: app)
        try isolated.assertExclusiveOwnership()
    }

    func testWorktreeConversationChangesExcludeMainDirectoryChanges() async throws {
        var fixtureRoot: URL?
        let isolated = try await launchFixture { directory in
            let root = directory.appendingPathComponent("Aster", isDirectory: true)
            fixtureRoot = root
            try Data("本体だけの変更\n".utf8).write(to: root.appendingPathComponent("main-only.txt"), options: .withoutOverwriting)
        }
        let app = try isolated.application()
        let root = try XCTUnwrap(fixtureRoot)
        app.buttons["tabs.project.1"].firstMatch.click()
        app.typeKey("n", modifierFlags: .command)
        let input = app.descendants(matching: .any)["newChat.messageInput"]
        try requireExists(input, "新規チャットの入力欄が表示されない")
        try typeUsingKeyboard("worktree の変更確認", into: input, app: app)
        let workspace = app.descendants(matching: .any)["newChat.workspacePicker"]
        workspace.click()
        let choice = app.buttons["新しい worktree"].firstMatch
        try requireExists(choice, "作業場所のメニューが開かない")
        XCTAssertTrue(choice.isEnabled)
        choice.click()
        try focusUsingKeyboard(input, app: app, backwards: true)
        app.typeKey(.return, modifierFlags: [])
        let changes = app.buttons["worktreeChanges.toggle"]
        try requireExists(changes, "worktree 会話の変更ボタンが表示されない", timeout: 20)

        let git = Process()
        let output = Pipe()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", root.path, "worktree", "list", "--porcelain"]
        git.standardOutput = output
        try git.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0)
        let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("worktree ") else { return nil }
            return String(line.dropFirst("worktree ".count))
        }.filter { URL(fileURLWithPath: $0).resolvingSymlinksInPath() != root.resolvingSymlinksInPath() }
        XCTAssertEqual(paths.count, 1, "テスト所有の worktree が一意ではない")
        let path = try XCTUnwrap(paths.first)
        try Data("worktree だけの変更\n".utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent("worktree-only.txt"), options: .withoutOverwriting)
        changes.click()
        let panel = app.groups["editor-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let worktreeFile = panel.descendants(matching: .any)["git-commit-select-worktree-only.txt"]
        XCTAssertTrue(worktreeFile.waitForExistence(timeout: 10), "worktree の変更が表示されない")
        XCTAssertFalse(panel.descendants(matching: .any)["git-commit-select-main-only.txt"].exists,
                       "本体フォルダの変更が worktree 会話に混ざった")
        try isolated.assertExclusiveOwnership()
    }

    private func sendNewChat(
        _ text: String, index: Int, app: XCUIApplication, isolated: IsolatedPhloxApplication
    ) throws -> String {
        try isolated.assertExclusiveOwnership()
        app.typeKey("n", modifierFlags: .command)
        let input = app.descendants(matching: .any)["newChat.messageInput"]
        try requireExists(input, "新規チャットの入力欄が表示されない")
        try typeUsingKeyboard(text, into: input, app: app)
        app.typeKey(.return, modifierFlags: [])
        let tab = app.buttons["tabs.item.\(index)"].firstMatch
        let launched = NSPredicate { _, _ in tab.exists && tab.label == text }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: launched, object: nil)], timeout: 20)
        XCTAssertEqual(result, .completed, "fake CLI の会話タブができない")
        guard result == .completed else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "fake CLI の会話タブができない: \(text)"])
        }
        let draftClosed = input.waitForNonExistence(timeout: 10)
        XCTAssertTrue(draftClosed, "送信後も下書きが表示されたまま")
        guard draftClosed else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "送信後も下書きが表示されたまま"])
        }
        return tab.label
    }

    private func typeUsingKeyboard(_ text: String, into input: XCUIElement, app: XCUIApplication) throws {
        try focusUsingKeyboard(input, app: app)
        app.typeText(text)
        XCTAssertEqual(input.value as? String, text, "キーボード入力が本文に反映されない")
        guard input.value as? String == text else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "キーボード入力が本文に反映されない: \(text)"])
        }
    }

    private func requireExists(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 10) throws {
        guard element.waitForExistence(timeout: timeout) else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func requireClosed(_ element: XCUIElement, _ message: String) throws {
        let closed = element.waitForNonExistence(timeout: 10)
        XCTAssertTrue(closed, message)
        guard closed else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func focusUsingKeyboard(_ element: XCUIElement, app: XCUIApplication, backwards: Bool = false) throws {
        try requireExists(element, "キーボード移動先が表示されない: \(element.identifier)")
        for _ in 0..<40 {
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return }
            app.typeKey(.tab, modifierFlags: backwards ? .shift : [])
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "keyboard-focus-failure-\(element.identifier)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        throw NSError(domain: "UnifiedNewChatUITests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Tabで到達できない: \(element.identifier)\n\(app.debugDescription)"])
    }

    private func selectNewWorktreeUsingKeyboard(_ workspace: XCUIElement, app: XCUIApplication) throws {
        // XCUITest の Menu 焦点判定は偽陰性になる。焦点枠で確認したチップ順を使う。
        try focusUsingKeyboard(app.buttons["newChat.harnessModelPicker"], app: app)
        // 畳んだときは effort・権限の 2 つが「…」1 つになる。
        let chipsBeforeWorkspace = app.descendants(matching: .any)["newChat.settingsOverflow"].exists ? 3 : 4
        for _ in 0..<chipsBeforeWorkspace { app.typeKey(.tab, modifierFlags: []) }
        app.typeKey(.space, modifierFlags: [])
        let choice = app.buttons["新しい worktree"].firstMatch
        try requireExists(choice, "Spaceで作業場所のメニューを開けない")
        app.typeKey(.escape, modifierFlags: [])
        try requireClosed(choice, "Escで作業場所のメニューを閉じられない")
        app.typeKey(.return, modifierFlags: [])
        try requireExists(choice, "Returnで作業場所のメニューを開けない")
        attachWorkspaceSelection("return-opened", app: app)
        guard choice.isEnabled else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "初期コミットのあるGit fixtureで新しいworktreeを選べない"])
        }
        app.typeKey(.downArrow, modifierFlags: [])
        attachWorkspaceSelection("down-1", app: app)
        app.typeKey(.downArrow, modifierFlags: [])
        attachWorkspaceSelection("down-2", app: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(workspace.value as? String, "新しい worktree", "キーボードで作業場所を選べない")
        guard workspace.value as? String == "新しい worktree" else {
            throw NSError(domain: "UnifiedNewChatUITests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "キーボードで新しいworktreeを選択できなかった"])
        }
    }

    private func attachWorkspaceSelection(_ stage: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "workspace-selection-\(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sidebarSession(named name: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + "、")).firstMatch
    }

    private func assertCurrentSidebarSession(_ name: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = sidebarSession(named: name, app: app)
        let selected = NSPredicate { _, _ in row.exists && (row.value as? String) == "現在の会話" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: nil)], timeout: 10), .completed,
                       "キーボード切り替え後のサイドバー選択が \(name) と一致しない", file: file, line: line)
    }

    private static let structuredFakeClaude = """
    #!/usr/bin/python3
    import json
    import os
    import sys
    import uuid

    session_id = os.environ.get("PHLOX_SESSION_ID", str(uuid.uuid4()))

    def emit(event):
        print(json.dumps(event), flush=True)

    emit({"type": "system", "subtype": "init", "session_id": session_id})
    for line in sys.stdin:
        request = json.loads(line)
        if request["type"] == "user":
            emit({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "UI fixture response"}]}})
            emit({"type": "result", "subtype": "success", "is_error": False, "session_id": session_id, "result": "UI fixture response"})
        elif request["type"] == "control_request":
            emit({"type": "control_response", "response": {"subtype": "success", "request_id": request["request_id"], "response": {}}})
    """
}
