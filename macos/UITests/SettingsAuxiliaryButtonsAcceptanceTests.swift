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
        // 2026-09-25 ユーザー承認: 設定の見出しを外したので、窓はタブ列の識別子で探す。
        let settings = app.windows.containing(.any, identifier: "settings-window").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "[\(theme)] 日本語の設定画面が見つからない")
        guard settings.exists else { return }
        let scroll = settings.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "[\(theme)] 設定のスクロール領域が見つからない")
        guard scroll.exists else { return }

        let expectedEnabled: [String: Bool] = [
            "テスト通知を送る": true, "エージェント管理を開く": true, "今すぐ確認…": false,
        ]
        // 10 Settings の 6 タブ化（2026-09 承認）で「通知テスト」は通知タブへ移った。一般タブは「今すぐ確認」。
        let generalLabels = ["今すぐ確認…"]
        var observed = Set<String>()
        for index in 0..<7 {
            try isolated.assertExclusiveOwnership()
            attach(settings.screenshot(), name: "settings-\(theme)-scroll-\(index)")
            for label in generalLabels {
                let button = settings.buttons[label]
                guard button.exists, settings.frame.contains(button.frame), !button.frame.isEmpty else { continue }
                print("SETTINGS BUTTON [\(theme)]: label=\(button.label) enabled=\(button.isEnabled) frame=\(button.frame)")
                XCTAssertEqual(button.isEnabled, expectedEnabled[label], "[\(theme)] \(label) の enabled が期待と異なる")
                observed.insert(label)
            }
            if observed.count == generalLabels.count { break }
            if index < 6 {
                scroll.scroll(byDeltaX: 0, deltaY: -500)
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        XCTAssertEqual(observed, Set(generalLabels), "[\(theme)] 一般タブの補助操作が見つからない")
        guard observed.count == generalLabels.count else { return }

        // 外観証拠: 通常 → hover → hover離脱（PM 目視用。assert しない）
        for label in generalLabels {
            let button = settings.buttons[label]
            attach(settings.screenshot(), name: "settings-\(theme)-normal-\(label)")
            button.hover()
            try await Task.sleep(for: .milliseconds(250))
            attach(settings.screenshot(), name: "settings-\(theme)-hover-\(label)")
        }
        settings.descendants(matching: .any)["settings-window"].firstMatch.hover()
        try await Task.sleep(for: .milliseconds(250))
        attach(settings.screenshot(), name: "settings-\(theme)-hover-left")

        // 焦点証拠: Tab 移動のみ（Return/Space は押さない）。到達を print と画像で記録する。
        for step in 0..<12 {
            try isolated.assertExclusiveOwnership()
            app.typeKey(.tab, modifierFlags: [])
            try await Task.sleep(for: .milliseconds(150))
            for label in generalLabels {
                let button = settings.buttons[label]
                if button.exists, (button.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                    print("SETTINGS FOCUS [\(theme)]: step=\(step) label=\(label)")
                    attach(settings.screenshot(), name: "settings-\(theme)-focus-\(label)")
                }
            }
        }

        settings.buttons["通知"].click()
        let notificationScroll = settings.scrollViews["settings-group-notifications"]
        XCTAssertTrue(notificationScroll.waitForExistence(timeout: 10), "[\(theme)] 通知タブが開かない")
        for index in 0..<7 {
            try isolated.assertExclusiveOwnership()
            let button = settings.buttons["テスト通知を送る"]
            if button.exists, settings.frame.contains(button.frame), !button.frame.isEmpty {
                print("SETTINGS BUTTON [\(theme)]: label=\(button.label) enabled=\(button.isEnabled) frame=\(button.frame)")
                XCTAssertEqual(button.isEnabled, expectedEnabled["テスト通知を送る"], "[\(theme)] 通知テスト の enabled が期待と異なる")
                observed.insert("テスト通知を送る")
                attach(settings.screenshot(), name: "settings-\(theme)-normal-テスト通知を送る")
                button.hover()
                try await Task.sleep(for: .milliseconds(250))
                attach(settings.screenshot(), name: "settings-\(theme)-hover-テスト通知を送る")
                for step in 0..<12 {
                    app.typeKey(.tab, modifierFlags: [])
                    try await Task.sleep(for: .milliseconds(150))
                    if (button.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                        print("SETTINGS FOCUS [\(theme)]: step=\(step) label=テスト通知を送る")
                        attach(settings.screenshot(), name: "settings-\(theme)-focus-テスト通知を送る")
                        break
                    }
                }
                break
            }
            if index < 6 { notificationScroll.scroll(byDeltaX: 0, deltaY: -500) }
        }

        settings.buttons["エージェント"].click()
        let agentScroll = settings.scrollViews["settings-group-agents"]
        XCTAssertTrue(agentScroll.waitForExistence(timeout: 10), "[\(theme)] エージェントタブが開かない")
        for index in 0..<7 {
            try isolated.assertExclusiveOwnership()
            let button = settings.buttons["エージェント管理を開く"]
            if button.exists, settings.frame.contains(button.frame), !button.frame.isEmpty {
                XCTAssertTrue(button.isEnabled, "[\(theme)] エージェント管理を開けない")
                observed.insert("エージェント管理を開く")
                attach(settings.screenshot(), name: "settings-\(theme)-agent-normal")
                button.hover()
                attach(settings.screenshot(), name: "settings-\(theme)-agent-hover")
                for step in 0..<12 {
                    app.typeKey(.tab, modifierFlags: [])
                    if (button.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                        print("SETTINGS FOCUS [\(theme)]: step=\(step) label=エージェント管理を開く")
                        attach(settings.screenshot(), name: "settings-\(theme)-agent-focus")
                        break
                    }
                }
                break
            }
            if index < 6 { agentScroll.scroll(byDeltaX: 0, deltaY: -500) }
        }
        XCTAssertEqual(observed, Set(expectedEnabled.keys), "[\(theme)] 対象3操作の画面内表示を観測できていない")
        try isolated.assertExclusiveOwnership()
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
