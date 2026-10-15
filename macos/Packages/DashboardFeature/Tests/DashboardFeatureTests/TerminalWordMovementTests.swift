import AppKit
import Foundation
import PTYKit
import TerminalUI
import Testing

@MainActor
struct TerminalWordMovementTests {
    @Test("実zshでOption左2回とXによりone Xtwo threeになる", .timeLimit(.minutes(1)))
    func zshWordMovement() async throws {
        let manager = PTYManager(terminalMode: .interactive)
        let id = try await manager.spawn(command: "/bin/zsh", args: ["-f", "-i"],
            env: ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "PS1": "WORD_READY> ", "PS2": "CONT> "])
        let output = WordMovementOutput()
        let reader = Task { for await data in manager.outputStream(for: id) { await output.append(data) } }
        do {
            try await output.waitFor("WORD_READY> ")
            // 明示的なemacsモードでzshの環境差を除く。矢印用のbindkeyは追加しない。
            try await manager.write(Data("bindkey -e; PS1='WORD_INPUT> '\n".utf8), to: id)
            try await output.waitFor("WORD_INPUT> ")
            let coordinator = TerminalCoordinator()
            var input = Data()
            coordinator.onInput = { input.append($0) }
            for _ in 0..<2 {
                let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [.option, .function, .numericPad], timestamp: 0, windowNumber: 0,
                    context: nil, characters: "\u{f702}", charactersIgnoringModifiers: "\u{f702}",
                    isARepeat: false, keyCode: 123))
                coordinator.terminalView.keyDown(with: event)
            }
            let deadline = ContinuousClock.now + .seconds(1)
            while input.count < 4, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            #expect(input == Data([0x1b, 0x62, 0x1b, 0x62]))
            var command = Data("echo one two three".utf8)
            command.append(input)
            command.append(Data("X\n".utf8))
            try await manager.write(command, to: id)
            try await output.waitFor("\r\none Xtwo three\r\n")
        } catch {
            await manager.hangUp(id)
            reader.cancel()
            throw error
        }
        await manager.hangUp(id)
        reader.cancel()
    }
}

private actor WordMovementOutput {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    func waitFor(_ needle: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !String(decoding: data, as: UTF8.self).contains(needle) {
            guard ContinuousClock.now < deadline else {
                throw WordMovementTimeout(output: String(decoding: data, as: UTF8.self))
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
private struct WordMovementTimeout: Error { let output: String }
