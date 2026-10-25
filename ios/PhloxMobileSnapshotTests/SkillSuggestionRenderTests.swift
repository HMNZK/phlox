import SwiftUI
import UIKit
import Testing
import PhloxCore
import DesignSystemIOS
import Features
import Observation

@MainActor @Suite(.serialized) struct SkillSuggestionRenderTests {
    @Test func rendersSkillsAtNarrowWidthAndLargeText() async throws {
        guard let path = ProcessInfo.processInfo.environment["PHLOX_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = UserDefaults.standard
        let previousTheme = preferences.object(forKey: ThemeStore.themeKey)
        defer {
            if let previousTheme { preferences.set(previousTheme, forKey: ThemeStore.themeKey) }
            else { preferences.removeObject(forKey: ThemeStore.themeKey) }
        }
        let skills = [
            AgentSkill(name: "poteto-mode", description: "必要な変更に絞って実装します。", path: "/a"),
            AgentSkill(name: "skill-authoring", description: "スキルの説明と手順を改善します。", path: "/b"),
            AgentSkill(name: "swift-ui", description: "SwiftUIで画面を作成します。", path: "/c")
        ]
        for largeText in [false, true] {
            for dark in [false, true] {
                preferences.set(AppearancePreference.system.themeID(systemColorScheme: dark ? .dark : .light), forKey: ThemeStore.themeKey)
                let content = VStack {
                    Spacer()
                    DSInputBar(text: .constant("/"), cursorUTF16: .constant(1), model: (.codex, "Codex"), skills: skills, onSubmit: {})
                }
                .background(dark ? Color.black : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.dynamicTypeSize, largeText ? .accessibility5 : .large)
                let image = try await DesignSnapshotRenderTests().windowImage(
                    content, size: CGSize(width: 375, height: 667), safeArea: .zero,
                    scale: 1, dark: dark, scenarioID: "skills",
                    contentSizeCategory: largeText ? .accessibilityExtraExtraExtraLarge : .large
                )
                let data = try #require(image.pngData())
                try data.write(to: output.appendingPathComponent("skills-\(dark ? "dark" : "light")-\(largeText ? "ax5" : "normal").png"))
            }
        }
    }

    @MainActor @Observable final class Draft {
        var text = "確認 /pot 後続文"
        var cursor = "確認 /pot".utf16.count
        var selected: AgentSkill?
    }

    @Test func acceptingSkillThroughAccessibilityKeepsTextAndCursor() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_SNAPSHOT_DIR"] != nil else { return }
        let draft = Draft()
        let skill = AgentSkill(name: "poteto-mode", description: "実装します", path: "/a")
        let content = VStack {
            Spacer()
            DSInputBar(
                text: Binding(get: { draft.text }, set: { draft.text = $0 }),
                cursorUTF16: Binding(get: { draft.cursor }, set: { draft.cursor = $0 }),
                model: (.codex, "Codex"), skills: [skill], onSelectSkill: { draft.selected = $0 }, onSubmit: {}
            )
        }
        let helper = DesignSnapshotRenderTests()
        _ = try await helper.windowImage(content, size: CGSize(width: 375, height: 667), safeArea: .zero,
            scale: 1, dark: false, scenarioID: "skill-selection", prepareWindow: { window in
                let button = try await helper.waitForSnapshotAccessibilityElement(in: window, label: "/poteto-mode")
                try #require(button.accessibilityActivate())
                let deadline = ContinuousClock.now + .seconds(2)
                while draft.selected == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            })
        #expect(draft.selected == skill)
        #expect(draft.text == "確認 $poteto-mode  後続文")
        #expect(draft.cursor == "確認 $poteto-mode ".utf16.count)
    }
}
