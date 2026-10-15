import AppKit
import Testing
@testable import TerminalUI

@MainActor @Suite(.serialized)
struct BottomPanelShortcutTests {
    private final class Target: NSObject {
        var calls = 0
        @objc func toggle(_ sender: Any?) { calls += 1 }
    }

    @Test("ターミナルに入力先があっても⌘Jはメニューを優先しシェルへ送らない")
    func commandJBeforeShell() async throws {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let target = Target()
        let menu = NSMenu(title: "表示")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "下部パネルを隠す", action: #selector(Target.toggle(_:)), keyEquivalent: "j")
        item.keyEquivalentModifierMask = .command
        item.target = target
        menu.addItem(item)
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let coordinator = TerminalCoordinator()
        window.contentView = coordinator.terminalView
        #expect(window.makeFirstResponder(coordinator.terminalView))
        var input = Data()
        coordinator.onInput = { input.append($0) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 38))
        #expect(!coordinator.terminalView.performKeyEquivalent(with: event))
        #expect(target.calls == 0)
        // NSApplication はまずウィンドウへ渡し、未処理ならメインメニューを探す。
        let handledByWindow = window.performKeyEquivalent(with: event)
        let handled = handledByWindow || NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        #expect(handled)
        // Coordinator の send は MainActor への非同期配送。
        for _ in 0..<5 { await Task.yield() }
        #expect(target.calls == 1)
        #expect(input.isEmpty)
    }

    @Test("入力先の取得・解除を所有者へ知らせる")
    func responderChanges() {
        let coordinator = TerminalCoordinator()
        var values: [Bool] = []
        coordinator.onFocusChange = { values.append($0) }
        #expect(coordinator.terminalView.becomeFirstResponder())
        #expect(coordinator.terminalView.resignFirstResponder())
        #expect(values == [true, false])
    }

    @Test("単一表示器のリサイズは既存のsoftResetを維持する")
    func resizeKeepsOriginalResetBehavior() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[?1h".utf8))
        #expect(coordinator.terminalView.getTerminal().applicationCursor)
        coordinator.terminalView.resize(cols: 80, rows: 24)
        #expect(!coordinator.terminalView.getTerminal().applicationCursor)
    }

    @Test("テキスト領域の値は可視行だけで、日本語・全角文字と表示位置に従う")
    func visibleAccessibilityValue() throws {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        view.resize(cols: 40, rows: 3)
        coordinator.feed(Data("old-hidden\r\nsecond\r\nhello 日本語\r\nlast".utf8))
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .textArea)
        let value = try #require(view.accessibilityValue() as? String)
        #expect(!value.contains("old-hidden"))
        #expect(value.contains("hello 日本語"))
        #expect(value.contains("last"))
        #expect(value.split(separator: "\n", omittingEmptySubsequences: false).count == 3)
        view.scroll(toPosition: 0)
        let scrolled = try #require(view.accessibilityValue() as? String)
        #expect(scrolled.contains("old-hidden"))
        #expect(!scrolled.contains("last"))
        coordinator.feed(Data("\u{1b}[?1049halt-screen".utf8))
        #expect((view.accessibilityValue() as? String)?.contains("alt-screen") == true)
        #expect((view.accessibilityValue() as? String)?.contains("old-hidden") == false)
    }
}
