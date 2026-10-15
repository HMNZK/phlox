import AppKit
import Darwin
import Testing
@testable import TerminalUI

@MainActor
struct TerminalOptionArrowTests {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [.option, .function, .numericPad], text: String? = nil,
                     type: NSEvent.EventType = .keyDown, repeatPress: Bool = false) throws -> NSEvent {
        let chars = text ?? (code == 123 ? "\u{f702}" : "\u{f703}")
        return try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: repeatPress, keyCode: code))
    }

    @Test("KittyではOption矢印を押下・リピート・解放まで符号化する",
          arguments: [1, 3, 7], [UInt16(123), UInt16(124)])
    func kittyOptionArrowLifecycle(mode: Int, code: UInt16) async throws {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[>\(mode)u".utf8))
        var input = Data()
        coordinator.onInput = { input.append($0) }
        let view = coordinator.terminalView
        view.keyDown(with: try key(code))
        view.keyDown(with: try key(code, repeatPress: true))
        view.keyUp(with: try key(code, type: .keyUp))
        try await Task.sleep(for: .milliseconds(20))
        let arrow = code == 123 ? "D" : "C"
        let press = "\u{1b}[1;3\(arrow)"
        let tail = mode == 1 ? press : "\u{1b}[1;3:2\(arrow)\u{1b}[1;3:3\(arrow)"
        #expect(input == Data((press + tail).utf8))
        #expect(!input.contains(Data("\u{1b}b".utf8)))
        #expect(!input.contains(Data("\u{1b}f".utf8)))
        #expect(!view.optionAsMetaKey)
    }

    @Test("別端末で解放して戻っても通常矢印のリピートを変換しない", arguments: [0, 1, 3, 7])
    func focusChangeWithoutRelease(mode: Int) async throws {
        _ = NSApplication.shared
        let coordinator = TerminalCoordinator()
        let other = TerminalCoordinator()
        if mode != 0 { coordinator.feed(Data("\u{1b}[>\(mode)u".utf8)) }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let content = NSView(frame: window.contentView!.bounds)
        window.contentView = content
        content.addSubview(coordinator.terminalView)
        content.addSubview(other.terminalView)
        #expect(window.makeFirstResponder(coordinator.terminalView))
        coordinator.terminalView.keyDown(with: try key(123))
        #expect(window.makeFirstResponder(other.terminalView))
        other.terminalView.keyUp(with: try key(123, type: .keyUp))
        #expect(window.makeFirstResponder(coordinator.terminalView))
        // 前の押下の配送を終え、復帰後の通常矢印だけを比較する。
        try await Task.sleep(for: .milliseconds(20))
        var input = Data()
        coordinator.onInput = { input.append($0) }
        let flags: NSEvent.ModifierFlags = [.function, .numericPad]
        coordinator.terminalView.keyDown(with: try key(123, flags: flags))
        coordinator.terminalView.keyDown(with: try key(123, flags: flags, repeatPress: true))
        coordinator.terminalView.keyUp(with: try key(123, flags: flags, type: .keyUp))
        try await Task.sleep(for: .milliseconds(20))
        let expected = mode < 3 ? "\u{1b}[D\u{1b}[D" : "\u{1b}[D\u{1b}[1;1:2D\u{1b}[1;1:3D"
        #expect(input == Data(expected.utf8))
    }

    @Test("長押し途中のOption追加・解除でも現在の修飾と解放を保つ",
          arguments: [0, 1, 3, 7], [false, true])
    func optionAddedDuringRepeat(mode: Int, releaseOptionFirst: Bool) async throws {
        let coordinator = TerminalCoordinator()
        if mode != 0 { coordinator.feed(Data("\u{1b}[>\(mode)u".utf8)) }
        var input = Data()
        coordinator.onInput = { input.append($0) }
        let view = coordinator.terminalView
        let plain: NSEvent.ModifierFlags = [.function, .numericPad]
        view.keyDown(with: try key(123, flags: plain))
        view.keyDown(with: try key(123, repeatPress: true))
        let finalFlags: NSEvent.ModifierFlags = releaseOptionFirst ? plain : [.option, .function, .numericPad]
        view.keyDown(with: try key(123, flags: finalFlags, repeatPress: true))
        view.keyUp(with: try key(123, flags: finalFlags, type: .keyUp))
        try await Task.sleep(for: .milliseconds(20))
        let expected: String
        if mode == 0 {
            expected = "\u{1b}[D\u{1b}b" + (releaseOptionFirst ? "\u{1b}[D" : "\u{1b}b")
        } else if mode == 1 {
            expected = "\u{1b}[D\u{1b}[1;3D" + (releaseOptionFirst ? "\u{1b}[D" : "\u{1b}[1;3D")
        } else {
            let modifier = releaseOptionFirst ? 1 : 3
            expected = "\u{1b}[D\u{1b}[1;3:2D\u{1b}[1;\(modifier):2D\u{1b}[1;\(modifier):3D"
        }
        #expect(input == Data(expected.utf8))
        if mode != 0 { #expect(!input.contains(Data("\u{1b}b".utf8))) }
    }

    @Test("Option左右矢印からPTYのslaveにESC b/fが届く", arguments: ["", "\u{1b}[?1h"])
    func arrowsReachPTY(mode: String) async throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        #expect(openpty(&master, &slave, nil, nil, nil) == 0)
        guard master >= 0, slave >= 0 else { return }
        defer { close(master); close(slave) }
        var settings = termios()
        #expect(tcgetattr(slave, &settings) == 0)
        cfmakeraw(&settings)
        #expect(tcsetattr(slave, TCSANOW, &settings) == 0)
        #expect(fcntl(slave, F_SETFL, O_NONBLOCK) == 0)
        let coordinator = TerminalCoordinator()
        coordinator.onInput = { data in
            #expect(data.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == data.count)
        }
        coordinator.feed(Data(mode.utf8))
        #expect(coordinator.terminalView.getTerminal().applicationCursor == mode.contains("?1h"))
        #expect(coordinator.terminalView.getTerminal().keyboardEnhancementFlags.isEmpty == !mode.contains(">1u"))
        #expect(!coordinator.terminalView.optionAsMetaKey)
        coordinator.terminalView.keyDown(with: try key(123))
        coordinator.terminalView.keyDown(with: try key(124))
        var received: [UInt8] = []
        let deadline = ContinuousClock.now + .seconds(1)
        while received.count < 4, ContinuousClock.now < deadline {
            var bytes = [UInt8](repeating: 0, count: 64)
            let count = read(slave, &bytes, bytes.count)
            if count > 0 { received.append(contentsOf: bytes.prefix(count)) }
            else { #expect(errno == EAGAIN) }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(received == [0x1b, 0x62, 0x1b, 0x66])
        #expect(!coordinator.terminalView.optionAsMetaKey)
    }

    @Test("Optionで入力されたバックスラッシュをESCで包まない")
    func optionTextInput() async throws {
        let coordinator = TerminalCoordinator()
        var input = Data()
        coordinator.onInput = { input.append($0) }
        coordinator.terminalView.keyDown(with: try key(93, flags: .option, text: "\\"))
        let deadline = ContinuousClock.now + .seconds(1)
        while input.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(input == Data([0x5c]))
        #expect(!coordinator.terminalView.optionAsMetaKey)
    }

    @Test("追加修飾キーを単語移動に変換しない", arguments: [NSEvent.ModifierFlags.shift, .command, .control])
    func additionalModifiers(extra: NSEvent.ModifierFlags) async throws {
        let coordinator = TerminalCoordinator()
        var input = Data()
        coordinator.onInput = { input.append($0) }
        coordinator.terminalView.keyDown(with: try key(123, flags: [.option, .function, .numericPad, extra]))
        coordinator.terminalView.keyDown(with: try key(124, flags: [.option, .function, .numericPad, extra]))
        // 出力ゼロの経路も含め、MainActor上のsend配送を待つ。
        try await Task.sleep(for: .milliseconds(20))
        #expect(!input.contains(Data([0x1b, 0x62])))
        #expect(!input.contains(Data([0x1b, 0x66])))
        if extra == .control { #expect(input == Data("\u{1b}[1;5D\u{1b}[1;5C".utf8)) }
    }

    @Test("IME未確定中のOption矢印をPTYの単語移動にしない")
    func markedTextArrows() async throws {
        let coordinator = TerminalCoordinator()
        var input = Data()
        coordinator.onInput = { input.append($0) }
        coordinator.terminalView.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.terminalView.keyDown(with: try key(123))
        coordinator.terminalView.keyDown(with: try key(124))
        try await Task.sleep(for: .milliseconds(20))
        #expect(input.isEmpty)
        #expect(coordinator.terminalView.hasMarkedText())
    }

    @Test("通常の左右矢印はカーソルモードに従う", arguments: [false, true])
    func ordinaryArrows(application: Bool) async throws {
        let coordinator = TerminalCoordinator()
        if application { coordinator.feed(Data("\u{1b}[?1h".utf8)) }
        var input = Data()
        coordinator.onInput = { input.append($0) }
        coordinator.terminalView.keyDown(with: try key(123, flags: [.function, .numericPad]))
        coordinator.terminalView.keyDown(with: try key(124, flags: [.function, .numericPad]))
        let deadline = ContinuousClock.now + .seconds(1)
        while input.count < 6, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(input == Data((application ? "\u{1b}OD\u{1b}OC" : "\u{1b}[D\u{1b}[C").utf8))
    }
}
