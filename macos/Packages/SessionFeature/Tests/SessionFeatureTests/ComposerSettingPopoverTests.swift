import AppKit
import AgentDomain
import DesignSystem
import Observation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite(.serialized) @MainActor
struct ComposerSettingPopoverTests {
    @Test func permissionPanelUsesSessionContentAndSeparatesPlanFromPermissions() throws {
        let cases: [(AgentKind, String, String?, Int)] = [
            (.claudeCode, "権限モード", "acceptEdits", 5),
            (.codex, "承認とサンドボックス", ":workspace", 3),
            (.cursor, "権限", nil, 2)
        ]
        for (kind, title, value, count) in cases {
            let options = composerModeOptions(for: .builtin(kind), codexProfileIDs: [":danger-full-access", ":workspace", ":read-only"], languageCode: "ja")
            for plan in [false, true] {
                let panel = ComposerPermissionPanel(
                    agentRef: .builtin(kind), options: options, currentValue: value,
                    isPlanOn: plan, isPlanAvailable: true, languageCode: "ja",
                    onSelect: { _ in }, onPlanChange: { _ in }, onClose: {}
                )
                #expect(panel.title == title)
                #expect(panel.options.count == count)
                #expect(panel.options.allSatisfy { !$0.isPlan && !$0.explanation.isEmpty })
                #expect(!panel.footnote.isEmpty)
                let selected = try #require(panel.options.first { $0.value == value })
                #expect(panel.isSelected(selected) == !plan)
                #expect(panel.isPlanOn == plan)
            }
        }
    }

    @Test func searchMatchesSectionAndBadgeWithoutDroppingDisabledNotes() {
        let options: [SelectablePopoverOption] = [
            .init(id: "claude:opus", title: "Opus", sectionTitle: "Claude Code"),
            .init(id: "codex:gpt", title: "gpt", sectionTitle: "Codex", badge: "既定"),
            .init(id: "missing", title: "未検出", sectionTitle: "Cursor", isEnabled: false, isSelectable: false)
        ]
        func matching(_ query: String) -> [String] {
            SelectablePopover(options: options, selectedID: nil, searchText: .constant(query), onSelect: { _ in })
                .visibleOptions.map(\.id)
        }
        #expect(matching(" CODEX\n") == ["codex:gpt"])
        #expect(matching("既定") == ["codex:gpt"])
        #expect(matching("cursor") == ["missing"])
        #expect(matching("nothing") == [])
    }


    @Test(arguments: [false, true])
    func bothTriggersOpenANativePopoverAndReopen(legacy: Bool) async throws {
        let harness = try await mount(legacy: legacy)
        defer { harness.close() }
        let popup = try await open(harness)
        #expect(popup !== harness.window)
        #expect(harness.state.openCount == (legacy ? 1 : 0))
        try sendKey(53, characters: "\u{1b}", to: popup)
        try await settle(harness.host)
        #expect(!popup.isVisible)
        let reopened = try await open(harness)
        #expect(reopened.isVisible)
        #expect(harness.state.openCount == (legacy ? 2 : 0))
        try sendKey(53, characters: "\u{1b}", to: reopened)
        try await settle(harness.host)
    }

    @Test(arguments: [false, true])
    func keyboardSelectionSkipsDisabledRowsAndRestoresTriggerFocus(legacy: Bool) async throws {
        let harness = try await mount(legacy: legacy)
        defer { harness.close() }
        let popup = try await open(harness)
        try sendKey(125, characters: "\u{f701}", to: popup)
        try sendKey(36, characters: "\r", to: popup)
        try await settle(harness.host)
        #expect(harness.state.chosen == "last")
        #expect(!popup.isVisible)
        let focused = harness.trigger.isAccessibilityFocused()
        #expect(focused)
    }

    @Test(arguments: [false, true])
    func searchFiltersNativePopoverAndDoesNotChooseDisabledRows(legacy: Bool) async throws {
        let harness = try await mount(legacy: legacy)
        defer { harness.close() }
        let popup = try await open(harness)
        harness.state.query = "disabled"
        try await settle(harness.host)
        try sendKey(36, characters: "\r", to: popup)
        try await settle(harness.host)
        #expect(harness.state.chosen == nil)
        #expect(popup.isVisible)
        harness.state.query = "gpt-6-astra"
        try await settle(harness.host)
        try sendKey(36, characters: "\r", to: popup)
        try await settle(harness.host)
        #expect(harness.state.chosen == "last")
        #expect(!popup.isVisible)
    }

    @Test(arguments: [false, true])
    func clickingOutsideClosesNativePopover(legacy: Bool) async throws {
        let harness = try await mount(legacy: legacy)
        defer { harness.close() }
        let popup = try await open(harness)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .init(x: 5, y: 5),
                                                  modifierFlags: [], timestamp: 0,
                                                  windowNumber: harness.window.windowNumber, context: nil,
                                                  eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        try await settle(harness.host)
        let closedByOutsideClick = !popup.isVisible
        #expect(closedByOutsideClick)
        if popup.isVisible {
            try sendKey(53, characters: "\u{1b}", to: popup)
            try await settle(harness.host)
        }
    }

    @Test(arguments: [false, true], [" ", "\r"])
    func focusedTriggerOpensWithSpaceAndReturn(legacy: Bool, character: String) async throws {
        let harness = try await mount(legacy: legacy)
        defer { harness.close() }
        harness.trigger.setAccessibilityFocused(true)
        try await settle(harness.host)
        try sendKey(character == " " ? 49 : 36, characters: character, to: harness.window)
        try await settle(harness.host)
        let popup = try #require(popupWindow())
        #expect(popup.isVisible)
        try sendKey(53, characters: "\u{1b}", to: popup)
        try await settle(harness.host)
    }

    @Test func changedSelectionIsUsedByTheOpenPopover() async throws {
        let harness = try await mount(legacy: false)
        defer { harness.close() }
        let popup = try await open(harness)
        harness.state.selectedID = "last"
        try await settle(harness.host)
        try sendKey(36, characters: "\r", to: popup)
        try await settle(harness.host)
        #expect(harness.state.chosen == "last")
    }

    @Test func nativePermissionPanelAcceptsArrowAndReturnKeys() async throws {
        let state = SelectionState()
        let choices = composerModeOptions(for: .builtin(.codex), codexProfileIDs: [":workspace", ":danger-full-access"], languageCode: "ja")
            .filter { !$0.isPlan }
        let host = NSHostingView(rootView:
            ComposerSettingPopover(accessibilityLabel: "権限", accessibilityIdentifier: "test.trigger") { _ in
                ComposerSettingChipLabel(title: "権限", systemImage: "shield")
            } content: { dismiss in
                ComposerPopupSurface(width: 340, padding: 10) {
                    ComposerPermissionPanel(agentRef: .builtin(.codex), options: choices,
                                            currentValue: choices[0].value, isPlanOn: false, isPlanAvailable: true,
                                            languageCode: "ja", onSelect: { state.chosen = $0.value },
                                            onPlanChange: { _ in }, onClose: dismiss)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("test.trigger.menu")
            }
        )
        let harness = try await mount(state: state, host: host)
        defer { harness.close() }
        let popup = try await open(harness)
        try sendKey(125, characters: "\u{f701}", to: popup)
        try sendKey(36, characters: "\r", to: popup)
        try await settle(harness.host)
        #expect(state.chosen == choices[1].value)
        #expect(!popup.isVisible)
        let reopened = try await open(harness)
        try sendKey(53, characters: "\u{1b}", to: reopened)
        try await settle(host)
        #expect(!reopened.isVisible)
    }

    @Test func nativeSettingsClosesExistingComposerOverlay() async throws {
        let state = SelectionState()
        let host = NSHostingView(rootView: ExclusionHarness(state: state))
        let harness = try await mount(state: state, host: host)
        defer { harness.close() }
        let overlayTrigger = try #require(find("test.overlayTrigger", in: host))
        let opened = overlayTrigger.accessibilityPerformPress()
        #expect(opened)
        try await settle(host)
        #expect(state.overlayOpen)
        let popup = try await open(harness)
        #expect(!state.overlayOpen)
        let reopened = overlayTrigger.accessibilityPerformPress()
        #expect(reopened)
        try await settle(host)
        #expect(state.overlayOpen)
        #expect(!popup.isVisible)
    }

    @Test func openingAnotherNativeSettingClosesThePreviousOne() async throws {
        let state = SelectionState()
        let host = NSHostingView(rootView: ExclusionHarness(state: state))
        let harness = try await mount(state: state, host: host)
        defer { harness.close() }
        let popup = try await open(harness)
        let secondTrigger = try #require(find("test.secondTrigger", in: host))
        let opened = secondTrigger.accessibilityPerformPress()
        #expect(opened)
        try await settle(host)
        #expect(!popup.isVisible)
        let secondPopup = try #require(NSApp.windows.first { $0.isVisible && $0.contentView.map { find("test.second.menu", in: $0) != nil } == true })
        let editor = try #require(secondPopup.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        try sendKey(125, characters: "\u{f701}", to: secondPopup)
        try sendKey(36, characters: "\r", to: secondPopup)
        try await settle(host)
        #expect(state.chosen == "last")
        #expect(!secondPopup.isVisible)
    }

    @Test func sharedCardsRenderWithBoundedHeight() async throws {
        _ = NSApplication.shared
        let preferences = UserDefaults.standard
        let arguments = preferences.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        defer {
            preferences.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
        }
        for light in [false, true] {
            var themeArguments = arguments
            themeArguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
            preferences.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            let state = SelectionState()
            let list = SelectionList(state: state, dismiss: {})
                .environment(\.colorScheme, light ? .light : .dark)
            let host = NSHostingView(rootView: list)
            let window = mount(host, width: 320, height: 540)
            window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            defer { window.close() }
            try await settle(host)
            #expect(host.fittingSize.width == DSLayout.harnessMenuWidth)
            #expect(host.fittingSize.height <= DSLayout.harnessMenuHeight)
            try snapshot(host, name: light ? "shared-model-light" : "shared-model-dark")
        }
        var themeArguments = arguments
        themeArguments[ThemeStore.themeKey] = AppTheme.phlox.id
        preferences.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let choices = composerModeOptions(for: .builtin(.codex), codexProfileIDs: [":workspace", ":danger-full-access"], languageCode: "ja")
            .filter { !$0.isPlan }
        let permission = ComposerPopupSurface(width: 340, padding: 10) {
            ComposerPermissionPanel(agentRef: .builtin(.codex), options: choices,
                                    currentValue: ":workspace", isPlanOn: false, isPlanAvailable: true,
                                    languageCode: "ja", onSelect: { _ in }, onPlanChange: { _ in }, onClose: {})
        }.environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: permission)
        let window = mount(host, width: 340, height: 350)
        defer { window.close() }
        try await settle(host)
        #expect(host.fittingSize.width == 340)
        try snapshot(host, name: "shared-permission-dark")
    }

    @Test func longNativeModelListsRespectTheirMaximumHeight() async throws {
        let card = SelectablePopover(
            options: (0..<50).map { .init(id: "model-\($0)", title: "モデル \($0)") }, selectedID: "model-0",
            width: DSLayout.harnessMenuWidth, maxHeight: DSLayout.harnessMenuHeight,
            footer: composerModelPickerFooter(languageCode: "ja"), searchText: .constant(""), onSelect: { _ in }
        )
        let host = NSHostingView(rootView: card)
        let window = mount(host, width: 320, height: 540)
        defer { window.close() }
        try await settle(host)
        #expect(host.fittingSize.height <= DSLayout.harnessMenuHeight)
        #expect(host.fittingSize.width == DSLayout.harnessMenuWidth)
    }

    @MainActor private struct Harness {
        let state: SelectionState
        let host: NSView
        let window: NSWindow
        let trigger: AnyObject
        let previousAccessibilityValue: Any?

        func close() {
            window.close()
            NSApp.accessibilitySetValue(previousAccessibilityValue, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        }
    }

    private func mount(legacy: Bool) async throws -> Harness {
        let state = SelectionState()
        let host = NSHostingView(rootView: TriggerHarness(state: state, legacy: legacy))
        return try await mount(state: state, host: host)
    }

    private func mount(state: SelectionState, host: NSView) async throws -> Harness {
        _ = NSApplication.shared
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(attribute)
        NSApp.accessibilitySetValue(true, forAttribute: attribute)
        let window = mount(host, width: 400, height: 300)
        window.makeKeyAndOrderFront(nil)
        try await settle(host)
        let trigger = try #require(find("test.trigger", in: host))
        return Harness(state: state, host: host, window: window, trigger: trigger, previousAccessibilityValue: previous)
    }

    private func open(_ harness: Harness) async throws -> NSWindow {
        let pressed = harness.trigger.accessibilityPerformPress()
        #expect(pressed)
        try await settle(harness.host)
        return try #require(popupWindow())
    }

    private func popupWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView.map { find("test.trigger.menu", in: $0) != nil } == true }
    }

    private func find(_ identifier: String, in root: Any) -> AnyObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ element: Any) -> AnyObject? {
            let object = element as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            if object.accessibilityIdentifier?() == identifier { return object }
            for child in object.accessibilityChildren?() ?? [] {
                if let result = visit(child) { return result }
            }
            for child in (element as? NSView)?.subviews ?? [] {
                if let result = visit(child) { return result }
            }
            return nil
        }
        return visit(root)
    }

    private func sendKey(_ code: UInt16, characters: String, to window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window.windowNumber, context: nil,
                                                characters: characters, charactersIgnoringModifiers: characters,
                                                isARepeat: false, keyCode: code))
        NSApp.sendEvent(event)
    }

    private func mount(_ view: NSView, width: CGFloat, height: CGFloat) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.frame = .init(x: 0, y: 0, width: width, height: height)
        window.contentView = view
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    private func snapshot(_ host: NSView, name: String) throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let output = root.appendingPathComponent(".verification/shared-chat-popovers/native-correction/snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1000)
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}

@MainActor @Observable
private final class SelectionState {
    var query = ""
    var selectedID = "first"
    var chosen: String?
    var openCount = 0
    var overlayOpen = false
}

@MainActor private let testOptions: [SelectablePopoverOption] = [
    .init(id: "first", title: "gpt-6.1-sol", sectionTitle: "Codex", sectionAgent: .codex, badge: "既定", isSelected: true),
    .init(id: "disabled", title: "disabled", sectionTitle: "Codex", isEnabled: false),
    .init(id: "last", title: "gpt-6-astra", sectionTitle: "Codex", sectionAgent: .codex)
]

private struct SelectionList: View {
    let state: SelectionState
    let dismiss: () -> Void

    var body: some View {
        SelectablePopover(options: testOptions, selectedID: state.selectedID, width: DSLayout.harnessMenuWidth,
                          maxHeight: DSLayout.harnessMenuHeight, footer: composerModelPickerFooter(languageCode: "ja"),
                          searchText: Binding(get: { state.query }, set: { state.query = $0 }),
                          accessibilityIdentifier: "test.trigger.menu",
                          onSelect: { state.chosen = $0.id; dismiss() }, onDismiss: dismiss)
    }
}

private struct TriggerHarness: View {
    let state: SelectionState
    let legacy: Bool

    var body: some View {
        VStack {
            if legacy {
                SelectablePopoverButton(options: testOptions, selectedID: state.selectedID, accessibilityLabel: "設定", accessibilityValue: "first",
                                        accessibilityIdentifier: "test.trigger", width: DSLayout.harnessMenuWidth,
                                        searchText: Binding(get: { state.query }, set: { state.query = $0 }),
                                        showsFocusRing: true, onOpen: { state.openCount += 1 },
                                        onSelect: { state.chosen = $0.id }) { _ in Text("設定") }
            } else {
                ComposerSettingPopover(accessibilityLabel: "設定", accessibilityIdentifier: "test.trigger",
                                       showsFocusRing: true) { _ in Text("設定") } content: { dismiss in
                    SelectionList(state: state, dismiss: dismiss)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExclusionHarness: View {
    let state: SelectionState

    var body: some View {
        VStack {
            Button("候補") { state.overlayOpen.toggle() }
                .accessibilityIdentifier("test.overlayTrigger")
                .composerPopup(isPresented: Binding(get: { state.overlayOpen }, set: { state.overlayOpen = $0 })) {
                    Text("候補の一覧").frame(width: 150, height: 80)
                }
            TriggerHarness(state: state, legacy: false)
            ComposerSettingPopover(accessibilityLabel: "別の設定", accessibilityIdentifier: "test.secondTrigger") { _ in
                ComposerSettingChipLabel(title: "別の設定")
            } content: { dismiss in
                SelectablePopover(options: testOptions, selectedID: "first", width: DSLayout.harnessMenuWidth,
                                  searchText: Binding(get: { state.query }, set: { state.query = $0 }),
                                  accessibilityIdentifier: "test.second.menu",
                                  onSelect: { state.chosen = $0.id; dismiss() }, onDismiss: dismiss)
            }
        }
    }
}
