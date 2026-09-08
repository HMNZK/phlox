import XCTest

// 設定値と3ボタンのactionは変更せず観測する。表示時のDebug待受更新は既存挙動。
@MainActor
final class SettingsButtonAppearanceObservationTests: XCTestCase {
    /// 設定の補助操作を改善する前の観測。設定値やボタンのactionは変更・実行しない。
    func testSettingsButtonAppearanceObservation() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(
            in: self, arguments: ["-AppleLanguages", "(ja)", "-AppleLocale", "ja",
                                  "-phlox.appLanguage", "ja", "-phlox.theme", "dracula"]
        )
        let app = try isolated.application()
        try isolated.assertExclusiveOwnership()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(.staticText, identifier: "設定").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "日本語の設定画面が見つからない")
        guard settings.exists else { return }
        let scroll = settings.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "設定のスクロール領域が見つからない")
        guard scroll.exists else { return }
        let labels = ["通知テスト", "エージェント管理を開く", "今すぐ確認"]
        var observed = Set<String>()
        for index in 0..<7 {
            try isolated.assertExclusiveOwnership()
            let screenshot = XCTAttachment(screenshot: settings.screenshot())
            screenshot.name = "settings-baseline-\(index)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print("SETTINGS BASELINE \(index): \(settings.debugDescription)")
            for label in labels {
                let button = settings.buttons[label]
                if button.exists {
                    print("SETTINGS BUTTON: label=\(button.label) enabled=\(button.isEnabled) hittable=\(button.isHittable) frame=\(button.frame)")
                    if settings.frame.contains(button.frame), !button.frame.isEmpty {
                        observed.insert(label)
                    }
                }
            }
            if observed.count == labels.count { break }
            if index < 6 {
                try isolated.assertExclusiveOwnership()
                scroll.scroll(byDeltaX: 0, deltaY: -500)
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        XCTAssertEqual(observed, Set(labels), "対象3操作の画面内表示を観測できていない")
    }

}
