import XCTest

@MainActor
final class ViewModeAccessibilityTests: XCTestCase {
    func testJapaneseModeNamesAndSelection() async throws {
        try await checkModes(language: "ja", heading: "プロジェクトを追加してください",
                             names: ["単体（⌃⌘1）", "グリッド（⌃⌘2）"], selectedValue: "選択中")
    }

    func testEnglishModeNamesAndSelection() async throws {
        try await checkModes(language: "en", heading: "Add a project",
                             names: ["Single (⌃⌘1)", "Grid (⌃⌘2)"], selectedValue: "Selected")
    }

    private func checkModes(language: String, heading: String, names: [String], selectedValue: String) async throws {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                                  "-phlox.appLanguage", language]
        )
        let app = try isolated.application()
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 15), "所有アプリの実効言語が一致しない")
        let ids = ["view-mode-single", "view-mode-grid"]
        var foundAll = true
        for (id, name) in zip(ids, names) {
            let matches = app.buttons.matching(identifier: id)
            let exists = matches.firstMatch.waitForExistence(timeout: 2)
            XCTAssertTrue(exists, "表示モードのボタン識別子がない: \(id)")
            if !exists { foundAll = false; continue }
            XCTAssertEqual(matches.count, 1, "識別子はボタン1件に限定する")
            XCTAssertEqual(matches.firstMatch.label, name, "アイコン名ではなく表示モード名が必要")
        }
        capture(app, name: "mode-\(language)-initial")
        guard foundAll else { return }

        func assertSelection(_ index: Int) {
            let selected = app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND (selected == true OR value == %@)", ids[index], selectedValue
            )).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5), "入力直後の選択が一致しない: \(ids[index])")
            for (other, id) in ids.enumerated() where other != index {
                let button = app.buttons[id]
                XCTAssertFalse(button.isSelected, "非選択モードに選択属性が残っている: \(id)")
                XCTAssertTrue(button.value == nil || (button.value as? String) == "",
                              "非選択モードに選択値が残っている: \(id)")
            }
        }

        assertSelection(0)
        for index in [1, 0] {
            try isolated.assertExclusiveOwnership()
            app.buttons[ids[index]].click()
            assertSelection(index)
            capture(app, name: "mode-\(language)-click-\(index)")
        }
        for index in [1, 0] {
            try isolated.assertExclusiveOwnership()
            app.typeKey("g", modifierFlags: [.command, .control])
            assertSelection(index)
            capture(app, name: "mode-\(language)-shortcut-\(index)")
        }
        for (key, index) in [("2", 1), ("1", 0)] {
            try isolated.assertExclusiveOwnership()
            app.typeKey(key, modifierFlags: [.command, .control])
            assertSelection(index)
            capture(app, name: "mode-\(language)-direct-\(index)")
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let window = app.windows.firstMatch
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MODE ACCESSIBILITY \(name): \(window.debugDescription)")
    }
}
