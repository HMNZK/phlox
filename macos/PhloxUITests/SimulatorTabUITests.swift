import XCTest

@MainActor
final class SimulatorTabUITests: XCTestCase {
    /// 開くだけでは画面への入力を始めず、帯の端末メニューにフォーカスを置く。
    func testShortcutOpensSimulatorWithDeviceMenuFocusAndWithoutDuplicate() async throws {
        let isolated = try await launchSession()
        let app = try isolated.application()
        try isolated.assertExclusiveOwnership()
        app.typeKey("y", modifierFlags: [.command, .control])

        let tab = simulatorTab(in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        captureAccessibility(app, name: "シミュレーター・初期アクセシビリティ構造")
        let deviceMenu = app.popUpButtons["simulator-device-menu"]
        XCTAssertTrue(deviceMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(isKeyboardFocused(deviceMenu),
                       "ショートカット直後のフォーカスは端末メニューに置く")
        let screen = element("simulator-screen", in: app)
        if screen.exists {
            XCTAssertFalse(isKeyboardFocused(screen),
                           "起動済み端末が表示されても画面にフォーカスを置かない")
        }
        XCTAssertTrue(app.staticTexts["キー入力はまだ送っていません · 画面をクリックすると送ります"].exists)

        try isolated.assertExclusiveOwnership()
        app.typeKey("y", modifierFlags: [.command, .control])
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "シミュレーター")).count, 1)
        capture(app, name: "シミュレーター・ショートカット直後")
    }

    func testPlusChooserOpensSimulatorAndCanReturnToConversation() async throws {
        let isolated = try await launchSession()
        let app = try isolated.application()
        try isolated.assertExclusiveOwnership()
        let addTab = app.buttons["このセッションにタブを追加"]
        XCTAssertTrue(addTab.waitForExistence(timeout: 10))
        addTab.click()
        let simulator = app.buttons["シミュレーター"]
        XCTAssertTrue(simulator.waitForExistence(timeout: 5))
        simulator.click()
        XCTAssertTrue(simulatorTab(in: app).waitForExistence(timeout: 10))

        try isolated.assertExclusiveOwnership()
        app.buttons["会話"].click()
        XCTAssertFalse(simulatorTab(in: app).exists)
        app.buttons["シミュレーター"].click()
        XCTAssertTrue(simulatorTab(in: app).waitForExistence(timeout: 5))
        capture(app, name: "シミュレーター・子タブ切り替え")
    }

    func testSimulatorSupportsSplitAndUnsplit() async throws {
        let isolated = try await launchSession()
        let app = try isolated.application()
        try isolated.assertExclusiveOwnership()
        // 初期幅では左右それぞれ320ptを確保できず単体表示になるため、所有する窓だけを広げる。
        let window = app.windows.firstMatch
        let resizeHandle = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        resizeHandle.click(forDuration: 0.2, thenDragTo: resizeHandle.withOffset(CGVector(dx: 300, dy: 0)))
        app.typeKey("y", modifierFlags: [.command, .control])
        let tab = simulatorTab(in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let fullWidth = tab.frame.width
        XCTAssertGreaterThan(fullWidth, 641, "左右の区画を表示できる幅を検証の前提にする")
        try toggleSplit(in: app, isolated: isolated)
        let tabs = app.groups.matching(identifier: "simulator-tab")
        XCTAssertEqual(tabs.count, 1, "右のシミュレーターと左の会話を並べる")
        XCTAssertGreaterThan(tab.frame.width, 0)
        XCTAssertLessThan(tab.frame.width, fullWidth * 0.8)
        capture(app, name: "シミュレーター・左右分割")

        try isolated.assertExclusiveOwnership()
        try toggleSplit(in: app, isolated: isolated)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertGreaterThan(tab.frame.width, fullWidth * 0.95)
    }

    private func launchSession() async throws -> IsolatedPhloxApplication {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self,
            arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            prepareData: { directory in
                let root = directory.appendingPathComponent("workspace", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                let projectID = UUID().uuidString
                let now = Date().timeIntervalSinceReferenceDate
                let project: [String: Any] = [
                    "id": ["rawValue": projectID], "name": "シミュレーター検証", "directoryPath": root.path,
                    "createdAt": now, "isManagedDirectory": false, "worktreeIsolationEnabled": false
                ]
                let session: [String: Any] = [
                    "id": ["rawValue": UUID().uuidString], "kind": ["type": "custom", "id": "simulator-probe"],
                    "projectID": ["rawValue": projectID], "workingDirectory": root.path,
                    "name": "シミュレーター用セッション", "startedAt": now, "command": "/bin/cat",
                    "args": [String](), "env": [String: String](), "backend": "pty"
                ]
                let agent: [String: Any] = [
                    "id": "simulator-probe", "displayName": "シミュレーター検証", "binaryName": "cat",
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
        let session = app.staticTexts["シミュレーター用セッション"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        session.click()
        app.typeKey("1", modifierFlags: [.command, .control])
        return isolated
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func simulatorTab(in app: XCUIApplication) -> XCUIElement {
        app.groups["simulator-tab"]
    }

    private func toggleSplit(in app: XCUIApplication, isolated: IsolatedPhloxApplication) throws {
        try isolated.assertExclusiveOwnership()
        app.menuBars.menuBarItems["表示"].click()
        let split = app.menuItems["右に分割して開く"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        XCTAssertTrue(split.isEnabled, "選択中セッションの子タブを分割できる")
        split.click()
    }

    /// macOSで公開snapshotのhasFocusはキーボードフォーカスを表さないため、公開の診断属性を読む。
    private func isKeyboardFocused(_ element: XCUIElement) -> Bool {
        let attributes = element.debugDescription.components(separatedBy: "Element subtree:").first ?? ""
        return attributes.contains("Keyboard Focused")
    }

    private func captureAccessibility(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
