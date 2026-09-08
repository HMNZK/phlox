import XCTest

@MainActor
final class ViewModeHelpObservationTests: XCTestCase {
    func testJapaneseModeHelp() async throws { try await observe(language: "ja") }
    func testEnglishModeHelp() async throws { try await observe(language: "en") }

    private func observe(language: String) async throws {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                                  "-phlox.appLanguage", language]
        )
        let app = try isolated.application()
        for mode in ["single", "grid", "team"] {
            try isolated.assertExclusiveOwnership()
            let button = app.buttons["view-mode-\(mode)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            guard button.exists else { return }
            button.hover()
            try await Task.sleep(for: .seconds(2))
            let help = app.descendants(matching: .helpTag).firstMatch
            XCTAssertTrue(help.waitForExistence(timeout: 5), "ホバー説明が表示されない")
            guard help.exists else { return }
            let attachment = XCTAttachment(screenshot: help.screenshot())
            attachment.name = "mode-help-\(language)-\(mode)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("MODE HELP \(language)/\(mode): \(app.debugDescription)")
        }
    }
}
