import Foundation
import Darwin
import AgentDomain
import PTYKit
import Testing
@testable import DashboardFeature

@Suite("ユーザー用シェル設定")
struct UserShellSettingsTests {
    @Test("実際の bash に $0 と SHELL が反映される", .timeLimit(.minutes(1)))
    @MainActor
    func actualBash() async throws {
        let controller = UserTerminalController(pty: PTYManager(terminalMode: .interactive), shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: #filePath).deletingLastPathComponent().path, environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb"], resolveShell: {
            UserShellSettings.resolve(configuredPath: "/bin/bash", systemPath: "/bin/zsh")
        })
        let output = ShellOutput()
        let stream = controller.makeOutputStream()
        let reader = Task {
            for await data in stream { await output.append(data) }
        }
        try await controller.ensureStarted()
        try await controller.send("printf 'shell_%s|%s\\n' \"$0\" \"$SHELL\"\n")
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var received = false
        while ContinuousClock.now < deadline {
            if await output.text().contains("shell_/bin/bash|/bin/bash") { received = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        await controller.shutdown()
        reader.cancel()
        #expect(received)
    }
    @Test("候補はコメント・空行・重複・実行不可を除く")
    func shellList() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let file = root.appendingPathComponent("shells-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# comment\n\n/bin/bash\n/bin/bash # duplicate\n/bin/zsh\n/not/a/shell\n/tmp\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try UserShellSettings.availableShells(at: file) == ["/bin/bash", "/bin/zsh"])
        #expect(throws: (any Error).self) { try UserShellSettings.availableShells(at: file.appendingPathComponent("missing")) }
    }

    @Test("実際の /etc/shells を読み、実行可能なファイルだけ返す")
    func systemShellList() throws {
        let paths = try UserShellSettings.availableShells()
        #expect(paths.contains("/bin/bash"))
        #expect(paths.allSatisfy(UserShellSettings.isExecutableFile))
        #expect(Set(paths).count == paths.count)
    }

    @Test("未設定は既定、指定は優先、失効時は代替情報を返す")
    func resolution() {
        #expect(UserShellSettings.resolve(configuredPath: "", systemPath: "/bin/zsh") == UserShellResolution(path: "/bin/zsh"))
        #expect(UserShellSettings.resolve(configuredPath: "", systemPath: "").path == "/bin/zsh")
        #expect(UserShellSettings.resolve(configuredPath: "/bin/bash", systemPath: "/bin/zsh") == UserShellResolution(path: "/bin/bash", fallbackPath: "/bin/zsh"))
        #expect(UserShellSettings.resolve(configuredPath: "/not/a/shell", systemPath: "/bin/zsh") == UserShellResolution(path: "/bin/zsh", unavailablePath: "/not/a/shell"))
        #expect(!UserShellSettings.loginShellPath().isEmpty)
    }

    @Test("無効なパスは保存せず、既存の選択を保持する")
    func validationAndSave() throws {
        let name = "UserShellTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(UserShellSettings.resolve(defaults: defaults).unavailablePath == nil)
        #expect(UserShellSettings.save("/bin/bash", defaults: defaults))
        for path in ["/not/a/shell", "/tmp", "bin/bash", "/etc/shells", "/bin/bash\n"] {
            #expect(!UserShellSettings.save(path, defaults: defaults))
            #expect(defaults.string(forKey: UserShellSettings.pathKey) == "/bin/bash")
        }
        #expect(UserShellSettings.resolve(defaults: defaults).path == "/bin/bash")
        #expect(UserShellSettings.save("", defaults: defaults))
        #expect(UserShellSettings.resolve(defaults: defaults).path == UserShellSettings.loginShellPath())
    }

    @Test("起動済みは保持し、再起動に新しい設定と SHELL を反映する")
    @MainActor
    func restartSelection() async throws {
        let pty = MockPTYManager()
        let selected = ShellSelection()
        let controller = UserTerminalController(pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp", environment: ["SHELL": "/wrong"], resolveShell: {
            UserShellSettings.resolve(configuredPath: selected.path, systemPath: "/bin/zsh")
        })
        try await controller.ensureStarted()
        selected.path = "/bin/bash"
        try await controller.ensureStarted()
        #expect(pty.spawnCalls.count == 1)
        #expect(pty.spawnCalls[0].command == "/bin/zsh")
        try await controller.restart()
        #expect(pty.spawnCalls.count == 2)
        #expect(pty.spawnCalls[1].command == "/bin/bash")
        #expect(pty.spawnCalls[1].env["SHELL"] == "/bin/bash")
        await controller.shutdown()
    }

    @Test("代替の注意はシェルの出力より先に一行出す", .timeLimit(.minutes(1)))
    @MainActor
    func fallbackWarning() async throws {
        let pty = MockPTYManager()
        let controller = UserTerminalController(pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp", environment: [:], resolveShell: {
            UserShellSettings.resolve(configuredPath: "/missing", systemPath: "/bin/zsh")
        }, shellWarning: { "設定のシェル（\($0)）が見つからないため、システムの既定で起動しました" })
        let text = try await collectOutput(controller) { output in
            try await controller.ensureStarted()
            let id = try #require(controller.sessionID)
            pty.emitOutput(for: id, data: Data("prompt".utf8))
            try await output.waitFor("prompt")
        }
        #expect(text == "設定のシェル（/missing）が見つからないため、システムの既定で起動しました\r\nprompt")
        #expect(controller.shellResolution?.unavailablePath == "/missing")
        #expect(pty.spawnCalls.first?.env["SHELL"] == "/bin/zsh")
    }

    @Test("存在確認後に消えた設定シェルは実 PTY で代替起動する", .timeLimit(.minutes(1)))
    @MainActor
    func removedAfterResolution() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("shell-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let resolved = UserShellSettings.resolve(configuredPath: file.path, systemPath: "/bin/zsh")
        #expect(resolved.path == file.path)
        try FileManager.default.removeItem(at: file)
        let controller = UserTerminalController(pty: PTYManager(), shellPath: "/bin/zsh",
            workingDirectory: file.deletingLastPathComponent().path, environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb"],
            resolveShell: { resolved }, shellWarning: { "warning:\($0)" })
        let text = try await collectOutput(controller) { output in
            try await controller.ensureStarted()
            #expect(controller.shellResolution == UserShellResolution(path: "/bin/zsh", unavailablePath: file.path))
            try await output.waitFor("warning:\(file.path)\r\n")
        }
        #expect(text.hasPrefix("warning:\(file.path)\r\n"))
    }

    @Test("再起動の注意は改行なしの旧プロンプトを残して独立した行に出す", .timeLimit(.minutes(1)))
    @MainActor
    func restartWarning() async throws {
        let pty = MockPTYManager()
        let selected = ShellSelection()
        let controller = UserTerminalController(pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp",
            environment: [:], resolveShell: {
                UserShellSettings.resolve(configuredPath: selected.path, systemPath: "/bin/zsh")
            }, shellWarning: { "設定のシェル（\($0)）が見つからないため、システムの既定で起動しました" })
        let text = try await collectOutput(controller) { output in
            try await controller.ensureStarted()
            pty.emitOutput(for: try #require(controller.sessionID), data: Data("zsh% ".utf8))
            try await output.waitFor("zsh% ")
            selected.path = "/missing"
            try await controller.restart()
            pty.emitOutput(for: try #require(controller.sessionID), data: Data("new-prompt".utf8))
            try await output.waitFor("new-prompt")
        }
        #expect(text == "zsh% \r\n設定のシェル（/missing）が見つからないため、システムの既定で起動しました\r\nnew-prompt")
        #expect(!text.contains("zsh% 設定のシェル"))
        #expect(text.components(separatedBy: "\r\n").contains { $0.hasPrefix("設定のシェル（") })
    }

    @Test("設定シェルの消失だけを一度代替し、他の失敗は伝播する", .timeLimit(.minutes(1)),
          arguments: ShellFailure.allCases)
    @MainActor
    private func fallbackErrors(_ scenario: ShellFailure) async throws {
        let pty = MockPTYManager()
        let missing = "/missing-shell-\(UUID().uuidString)"
        let resolution = scenario == .existingShell
            ? UserShellResolution(path: "/bin/bash", fallbackPath: "/bin/zsh")
            : UserShellResolution(path: missing, fallbackPath: scenario == .systemDefault ? nil : "/bin/zsh")
        let firstError = PTYError.spawnFailed(errno: scenario == .permissionDenied ? EACCES : ENOENT)
        pty.setSpawnErrors(scenario == .fallbackFails ? [firstError, .spawnFailed(errno: EACCES)] : [firstError])
        let controller = UserTerminalController(pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp",
            environment: [:], resolveShell: { resolution })
        do {
            try await controller.ensureStarted()
            #expect(scenario == .removedShell)
            #expect(controller.shellResolution == UserShellResolution(path: "/bin/zsh", unavailablePath: missing))
            #expect(pty.spawnCalls.last?.env["SHELL"] == "/bin/zsh")
        } catch {
            #expect(scenario != .removedShell)
            #expect(error as? PTYError == (scenario == .fallbackFails ? .spawnFailed(errno: EACCES) : firstError))
        }
        await controller.shutdown()
        #expect(pty.spawnCalls.count == (scenario == .removedShell || scenario == .fallbackFails ? 2 : 1))
    }

    @Test("出力が欠けても期限内に終了し、失敗時にシェルを停止する", .timeLimit(.minutes(1)))
    @MainActor
    func outputTimeoutCleanup() async throws {
        let pty = MockPTYManager()
        let controller = UserTerminalController(pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp", environment: [:])
        var startedID: SessionID?
        do {
            _ = try await collectOutput(controller) { output in
                try await controller.ensureStarted()
                startedID = controller.sessionID
                try await output.waitFor("missing-warning")
            }
            Issue.record("欠けた出力の待機が成功扱いになりました")
        } catch is ShellOutputTimeout {
            #expect(!controller.isRunning)
            #expect(pty.killedIDs == [try #require(startedID)])
        }
    }
}

private enum ShellFailure: CaseIterable, Sendable {
    case removedShell, existingShell, permissionDenied, systemDefault, fallbackFails
}

private struct ShellOutputTimeout: Error {}

@MainActor
private func collectOutput(
    _ controller: UserTerminalController,
    action: (ShellOutput) async throws -> Void
) async throws -> String {
    let output = ShellOutput()
    let stream = controller.makeOutputStream()
    let reader = Task {
        for await data in stream { await output.append(data) }
    }
    do {
        try await action(output)
    } catch {
        await controller.shutdown()
        reader.cancel()
        await reader.value
        throw error
    }
    await controller.shutdown()
    await reader.value
    return await output.text()
}

private actor ShellOutput {
    private var bytes = Data()
    func append(_ data: Data) { bytes.append(data) }
    func text() -> String { String(decoding: bytes, as: UTF8.self) }
    func waitFor(_ expected: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !text().contains(expected), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard text().contains(expected) else { throw ShellOutputTimeout() }
    }
}

@MainActor
private final class ShellSelection {
    var path = "/bin/zsh"
}
