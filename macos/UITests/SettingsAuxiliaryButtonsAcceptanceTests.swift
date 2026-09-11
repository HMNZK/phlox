import XCTest

// UI-05（task-17）受け入れテスト。設定の補助3ボタン（通知テスト／エージェント管理を開く／今すぐ確認）を
// 暗色 Dracula と明色 Phlox Light の隔離起動で観測し、名前・到達・enabled 状態を assert する。
// 外観（旧グラデーション枠・影の除去、焦点の見え方）は添付画像を PM が目視判定する（2026-09-11 承認の方式）。
// action を起こす Return/Space は押さない。
@MainActor
final class SettingsAuxiliaryButtonsAcceptanceTests: XCTestCase {
    func testAuxiliaryButtonsDarkDracula() async throws {
        try await observeAuxiliaryButtons(theme: "dracula")
    }

    func testAuxiliaryButtonsLightPhloxLight() async throws {
        try await observeAuxiliaryButtons(theme: "phlox-light")
    }

    private func observeAuxiliaryButtons(theme: String) async throws {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja",
                                  "-phlox.appLanguage", "ja", "-phlox.theme", theme]
        )
        let app = try isolated.application()
        try isolated.assertExclusiveOwnership()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(.staticText, identifier: "設定").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "[\(theme)] 日本語の設定画面が見つからない")
        guard settings.exists else { return }
        let scroll = settings.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "[\(theme)] 設定のスクロール領域が見つからない")
        guard scroll.exists else { return }

        let expectedEnabled: [String: Bool] = [
            "通知テスト": true, "エージェント管理を開く": true, "今すぐ確認": false,
        ]
        var observed = Set<String>()
        for index in 0..<7 {
            try isolated.assertExclusiveOwnership()
            attach(settings.screenshot(), name: "settings-\(theme)-scroll-\(index)")
            for (label, enabled) in expectedEnabled {
                let button = settings.buttons[label]
                guard button.exists, settings.frame.contains(button.frame), !button.frame.isEmpty else { continue }
                print("SETTINGS BUTTON [\(theme)]: label=\(button.label) enabled=\(button.isEnabled) frame=\(button.frame)")
                XCTAssertEqual(button.isEnabled, enabled, "[\(theme)] \(label) の enabled が期待と異なる")
                observed.insert(label)
            }
            if observed.count == expectedEnabled.count { break }
            if index < 6 {
                scroll.scroll(byDeltaX: 0, deltaY: -500)
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        XCTAssertEqual(observed, Set(expectedEnabled.keys), "[\(theme)] 対象3操作の画面内表示を観測できていない")
        guard observed.count == expectedEnabled.count else { return }

        // 外観証拠: 通常 → hover → hover離脱（PM 目視用。assert しない）
        for label in ["通知テスト", "エージェント管理を開く", "今すぐ確認"] {
            let button = settings.buttons[label]
            attach(settings.screenshot(), name: "settings-\(theme)-normal-\(label)")
            button.hover()
            try await Task.sleep(for: .milliseconds(250))
            attach(settings.screenshot(), name: "settings-\(theme)-hover-\(label)")
        }
        settings.staticTexts["設定"].firstMatch.hover()
        try await Task.sleep(for: .milliseconds(250))
        attach(settings.screenshot(), name: "settings-\(theme)-hover-left")

        // 焦点証拠: Tab 移動のみ（Return/Space は押さない）。到達を print と画像で記録する。
        for step in 0..<12 {
            try isolated.assertExclusiveOwnership()
            app.typeKey(.tab, modifierFlags: [])
            try await Task.sleep(for: .milliseconds(150))
            for label in expectedEnabled.keys {
                let button = settings.buttons[label]
                if button.exists, (button.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                    print("SETTINGS FOCUS [\(theme)]: step=\(step) label=\(label)")
                    attach(settings.screenshot(), name: "settings-\(theme)-focus-\(label)")
                }
            }
        }
        try isolated.assertExclusiveOwnership()
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
