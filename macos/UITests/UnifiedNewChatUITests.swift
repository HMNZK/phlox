import AppKit
import XCTest

@MainActor
final class UnifiedNewChatUITests: XCTestCase {
    func testKeyboardNewChatAndProjectTabSwitching() async throws {
        let fakeAgent = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packages/DashboardFeature/Tests/DashboardFeatureTests/Fixtures/fake-agent.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fakeAgent.path), "fake-agent.sh が実行可能ではない")

        let isolated = try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            testAgentBinaryPaths: { _ in ["claudeCode": fakeAgent.path] },
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
            }
        )
        let app = try isolated.application()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let firstProject = app.buttons["tabs.project.1"]
        let secondProject = app.buttons["tabs.project.2"]
        XCTAssertTrue(firstProject.waitForExistence(timeout: 10))
        XCTAssertTrue(secondProject.exists, "2つ目のプロジェクトタブが見つからない")
        firstProject.click()
        try isolated.assertExclusiveOwnership()
        app.typeKey("n", modifierFlags: .command)

        let message = app.descendants(matching: .any)["newChat.messageInput"]
        XCTAssertTrue(message.waitForExistence(timeout: 10), "新規チャットの入力欄が表示されない")
        XCTAssertEqual(message.label, "メッセージ", "入力欄の役割を読み上げられない")
        message.typeText("作業内容を確認してください")
        XCTAssertEqual(message.value as? String, "作業内容を確認してください", "入力欄の値を読み上げられない")

        let harness = app.buttons["newChat.harnessModelPicker"]
        XCTAssertTrue(harness.waitForExistence(timeout: 10))
        XCTAssertEqual(harness.label, "ハーネスとモデル")
        XCTAssertTrue((harness.value as? String)?.contains("Claude Code") == true)
        message.typeKey(.tab, modifierFlags: [])
        harness.typeKey(.space, modifierFlags: [])
        let search = app.textFields["newChat.modelSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "モデルメニューが開かない")
        search.typeKey(.tab, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        let effort = app.descendants(matching: .any)["newChat.effortPicker"]
        let permission = app.descendants(matching: .any)["newChat.permissionPicker"]
        let project = app.descendants(matching: .any)["newChat.projectPicker"]
        let workspace = app.descendants(matching: .any)["newChat.workspacePicker"]
        XCTAssertEqual(effort.label, "推論の深さ")
        XCTAssertTrue((effort.value as? String)?.isEmpty == false)
        XCTAssertEqual(permission.label, "権限")
        XCTAssertTrue((permission.value as? String)?.isEmpty == false)
        XCTAssertEqual(project.label, "プロジェクト")
        XCTAssertEqual(project.value as? String, "Aster")
        XCTAssertEqual(workspace.label, "作業場所")
        XCTAssertEqual(workspace.value as? String, "既存ディレクトリ")

        for _ in 0..<4 { app.typeKey(.tab, modifierFlags: []) }
        workspace.typeKey(.space, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(workspace.value as? String, "新しい worktree", "矢印キーで作業場所を選べない")

        message.click()
        message.typeKey(.return, modifierFlags: [])
        let sessionTab = app.buttons["tabs.item.1"]
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
}
