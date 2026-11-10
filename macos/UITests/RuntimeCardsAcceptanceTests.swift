import AppKit
import XCTest

@MainActor
final class RuntimeCardsAcceptanceTests: XCTestCase {
    private let title = "Native card acceptance"

    func testRestoredCardsKeepIndependentHistoryAndDirectJump() async throws {
        let isolated = try await launchFixture(longHistory: true)
        let app = try openSession(isolated)
        let window = app.windows.firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["AgentStatusCard"].firstMatch.waitForExistence(timeout: 15))
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Validate semantic long card")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        let history = app.descendants(matching: .any)["ChatInputHistoryScrubber"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(history.frame.maxX, window.frame.midX)
        XCTAssertTrue(window.frame.contains(history.frame), "入力履歴が実ウィンドウ内に表示されていない")
        capture(window, name: "native-cards-and-input-history")

        try isolated.assertExclusiveOwnership()
        task.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "semantic-work-2999"))
            .firstMatch.waitForExistence(timeout: 15), "長いカードの作業を取得・表示できない")
        capture(window, name: "native-long-card-expanded")

        try isolated.assertExclusiveOwnership()
        history.hover()
        XCTAssertTrue(app.descendants(matching: .any)["ChatInputHistoryScrubber.panel"]
            .firstMatch.waitForExistence(timeout: 5))
        try isolated.assertExclusiveOwnership()
        app.buttons["ChatInputHistoryScrubber.loadEarlier"].firstMatch.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Semantic input 0028"))
            .firstMatch.waitForExistence(timeout: 10))
        try isolated.assertExclusiveOwnership()
        app.buttons["ChatInputHistoryScrubber.loadEarlier"].firstMatch.click()
        let oldest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Semantic oldest input.")).firstMatch
        XCTAssertTrue(oldest.waitForExistence(timeout: 10))
        capture(window, name: "native-oldest-input-in-history")
        try isolated.assertExclusiveOwnership()
        oldest.click()
        XCTAssertTrue(app.buttons["全文を表示"].firstMatch.waitForExistence(timeout: 10))
        capture(window, name: "native-direct-jump-to-oldest")
    }

    func testLiveCardAndCommandClocksAdvanceAndFreezeAfterStop() async throws {
        let isolated = try await launchFixture(longHistory: false)
        let app = try openSession(isolated)
        try send("native-prime", app: app, isolated: isolated)
        try waitFor("準備の送信が完了して入力可能にならない", timeout: 15) {
            app.staticTexts["native-prime"].firstMatch.exists
                && app.buttons["ChatComposer.sendButton"].firstMatch.exists
                && app.buttons["ChatComposer.sendButton"].firstMatch.label == "送信"
                && !app.buttons["ChatComposer.stopButton"].firstMatch.exists
        }
        try send("native-live-clock", app: app, isolated: isolated)
        let headers = app.descendants(matching: .any).matching(identifier: "AgentStatusCard.header")
        let running = headers.matching(NSPredicate(format: "label BEGINSWITH %@", "実行中")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 15))
        let command = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "実行。", "printf semantic-grid-live"
        )).firstMatch
        try revealCommand(command, app: app, isolated: isolated)
        try observeClockUpdates(header: running, command: command)
        capture(app.windows.firstMatch, name: "native-live-card-and-command-clocks")
        try isolated.assertExclusiveOwnership()
        app.buttons["ChatComposer.stopButton"].firstMatch.click()
        let stopped = headers.matching(NSPredicate(format: "label BEGINSWITH %@", "中断")).firstMatch
        XCTAssertTrue(stopped.waitForExistence(timeout: 10))
        try waitFor("中断後に手動で開いた作業が表示されない", timeout: 5) { command.exists }
        let stoppedHeader = stopped.label
        let stoppedCommand = command.label
        let stoppedAt = Date()
        try waitFor("中断後も時計が変化している", timeout: 6) {
            Date().timeIntervalSince(stoppedAt) >= 3
                && stopped.label == stoppedHeader && command.label == stoppedCommand
        }
        capture(app.windows.firstMatch, name: "native-stopped-clocks-fixed")
    }

    private func openSession(_ isolated: IsolatedPhloxApplication) throws -> XCUIApplication {
        let app = try isolated.application()
        let session = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        try isolated.assertExclusiveOwnership()
        session.click()
        return app
    }

    private func send(_ text: String, app: XCUIApplication, isolated: IsolatedPhloxApplication) throws {
        try isolated.assertExclusiveOwnership()
        let input = app.textViews["ChatComposer.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click()
        input.typeText(text)
        app.typeKey(.return, modifierFlags: [])
    }

    private func revealCommand(_ command: XCUIElement, app: XCUIApplication, isolated: IsolatedPhloxApplication) throws {
        let outside = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "タスク外の作業")).firstMatch
        guard outside.waitForExistence(timeout: 10) else {
            throw NSError(domain: "RuntimeCardsAcceptanceTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "タスク外の作業の行が表示されない"])
        }
        // 自動展開は停止後に畳まれる。手動で開いた状態の保持も実際の操作で検証する。
        if outside.label.contains("展開済み") {
            try isolated.assertExclusiveOwnership()
            outside.click()
            try waitFor("作業の行を閉じられない", timeout: 5) { outside.label.contains("折りたたみ済み") }
        }
        try isolated.assertExclusiveOwnership()
        outside.click()
        try waitFor("ライブコマンドが表示されない", timeout: 10) { command.exists }
    }

    private func waitFor(_ message: String, timeout: TimeInterval, condition: @escaping () -> Bool) throws {
        let predicate = NSPredicate { _, _ in condition() }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed else {
            throw NSError(domain: "RuntimeCardsAcceptanceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func observeClockUpdates(header: XCUIElement, command: XCUIElement) throws {
        let end = ProcessInfo.processInfo.systemUptime + 10
        var observations: [String] = []
        while ProcessInfo.processInfo.systemUptime < end {
            let previousHeader = header.label
            let previousCommand = command.label
            try waitFor("実行中のカードまたはコマンドの時計が3秒以上進まない", timeout: 3) {
                header.exists && header.label != previousHeader && command.label != previousCommand
            }
            observations.append("\(ProcessInfo.processInfo.systemUptime): \(header.label) / \(command.label)")
        }
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "native-clock-observations"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchFixture(longHistory: Bool) async throws -> IsolatedPhloxApplication {
        let macOS = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let parent = macOS.deletingLastPathComponent().appendingPathComponent(".verification/native-card-acceptance")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja", "-phlox.appLanguage", "ja"],
            dataParent: parent,
            testAgentBinaryPaths: { directory in
                ["codex": directory.appendingPathComponent("fake-codex.py").path,
                 "claudeCode": directory.appendingPathComponent("fake-claude.py").path]
            },
            prepareData: { directory in
                let configuration: [String: Any] = ["script": macOS.appendingPathComponent("scripts/tests/session-runtime-semantic-chat.test.py").path,
                    "longHistory": longHistory]
                try JSONSerialization.data(withJSONObject: configuration).write(to: directory.appendingPathComponent("fixture.json"))
                let driver = directory.appendingPathComponent("fake-codex.py")
                try Self.fixtureDriver.write(to: driver, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: driver.path)
                let claude = directory.appendingPathComponent("fake-claude.py")
                try Self.claudeDriver.write(to: claude, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [directory.appendingPathComponent("fake-codex.py").path, "--prepare"]
                process.standardOutput = output
                process.standardError = output
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "RuntimeCardsAcceptanceTests.fixture", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
                }
            }
        )
    }

    private static let fixtureDriver = #"""
    #!/usr/bin/python3
    import importlib.util, json, sys
    from pathlib import Path
    root = Path(__file__).resolve().parent
    config = json.loads((root / "fixture.json").read_text())
    spec = importlib.util.spec_from_file_location("native_card_fixture", config["script"])
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    if sys.argv[1:] == ["--prepare"]:
        for name in ("project", "fake-state", "transcripts"):
            (root / name).mkdir()
        (root / "ownership.json").write_text(json.dumps({"purpose": "XCTest synthetic card fixture"}))
        if not config["longHistory"]:
            fixture.INPUT_COUNT = fixture.WORK_COUNT = 1
            fixture.FIRST_INPUT_TEXT = "Semantic first input."
        identifier = fixture.SESSION_ID
        descriptor = dict(id=identifier, kind="codex", name="Native card acceptance", titleSource="manual",
            workingDirectory=str(root / "project"), startedAt=fixture.STAMP, command=str(Path(__file__).resolve()),
            args=["app-server"], env={}, backend="appServer", codexThreadId="synthetic-" + identifier["rawValue"],
            launchContext="interactive")
        (root / "sessions.json").write_text(json.dumps(dict(schemaVersion=1, sessions=[descriptor])))
        (root / "transcripts" / (identifier["rawValue"] + ".json")).write_text(json.dumps(fixture.synthetic_transcript()))
    else:
        fixture.fake_codex(root, sys.argv[1:])
    """#

    private static let claudeDriver = #"""
    #!/usr/bin/python3
    import json, os, sys
    from pathlib import Path
    root = Path(__file__).resolve().parent
    config = json.loads((root / "fixture.json").read_text())
    script = Path(config["script"]).with_name("session-runtime-fake-agent.py")
    os.execv(sys.executable, [sys.executable, str(script), "--work-dir", str(root), "--provider", "claudeCode", "--"] + sys.argv[1:])
    """#
}
