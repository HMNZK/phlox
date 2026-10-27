import Darwin
import AgentDomain
import Foundation
import Testing
@testable import PTYKit

@Suite("制御端末を持つユーザー用プロセスの起動")
struct InteractiveSpawnTests {
    @Test("標準入出力が閉じていても ENOENT を返し、子を回収する", .timeLimit(.minutes(1)))
    func missingStandardDescriptorsStillReportFailure() throws {
        if try runIsolated("missingStandardDescriptorsStillReportFailure") { return }
        signal(SIGCHLD, SIG_DFL)
        // Swift Testing の報告先は検査直後に復元する。標準 fd が全欠落の場合も含める。
        let saved = try (0...2).map { fd -> Int32 in
            let copy = fcntl(Int32(fd), F_DUPFD_CLOEXEC, 3)
            return try #require(copy >= 3 ? copy : nil)
        }
        defer { for fd in saved { close(fd) } }
        for missing in [[Int32(1), 2], [0, 1, 2]] {
            // 制御端末を持つ子の終了後は slave が revoke されるため、毎回開く。
            let pty = try Posix.openPTY(terminalMode: .interactive)
            defer { close(pty.master); close(pty.slave) }
            var failure: Error?
            var unexpectedlySpawned: pid_t?
            for fd in missing { close(fd) }
            do {
                unexpectedlySpawned = try Posix.spawn(command: "/nonexistent/phlox-shell",
                    args: [], env: [:], masterFD: pty.master, slaveFD: pty.slave,
                    workingDirectory: nil, terminalMode: .interactive)
            } catch { failure = error }
            let restores = (0...2).map { dup2(saved[$0], Int32($0)) }
            #expect(restores == [0, 1, 2])
            #expect((failure as? PTYError) == .spawnFailed(errno: ENOENT))
            var status: Int32 = 0
            let waited = waitpid(-1, &status, WNOHANG)
            let waitError = errno
            #expect(waited == -1 && waitError == ECHILD,
                "失敗した子が残った: pid=\(String(describing: unexpectedlySpawned)), waitpid=\(waited), errno=\(waitError)")
            if let pid = unexpectedlySpawned { _ = waitpid(pid, nil, 0) }
        }
    }

    @Test("対話シェルに前景グループがあり Ctrl-C が sleep を止める", .timeLimit(.minutes(1)),
          arguments: ["/bin/zsh", "/bin/bash"])
    func foregroundGroupAndInterrupt(shell: String) async throws {
        try await withInteractiveShell(shell) { manager, id, output in
            try await manager.write(Data("printf 'TPGID=%s\\nTPGID_DONE\\n' \"$(ps -o tpgid= -p $$ | tr -d ' ')\"\n".utf8), to: id)
            try await output.waitFor("TPGID_DONE\r\n")
            let text = await output.text()
            let line = try #require(text.components(separatedBy: "\r\n").first { $0.hasPrefix("TPGID=") })
            let tpgid = try #require(Int32(line.dropFirst("TPGID=".count)))
            #expect(tpgid > 0, "前景グループがない: \(text)")
            let pid = try #require(await manager.pid(for: id))
            await output.clear()
            // 入力エコーに待機文字列が現れないよう、プロンプトの値を分けて渡す。
            try await manager.write(Data("PS1='INTERRUPT''> '; sleep 20\n".utf8), to: id)
            let deadline = ContinuousClock.now + .seconds(5)
            while !Posix.hasChildProcesses(pid: pid) {
                try #require(ContinuousClock.now < deadline, "sleep が起動しなかった")
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(100))
            let interruptedAt = ContinuousClock.now
            try await manager.write(Data([3]), to: id)
            try await output.waitFor("INTERRUPT> ")
            #expect(ContinuousClock.now - interruptedAt < .seconds(5), "Ctrl-C が sleep を中断しなかった")
            let interruptedOutput = await output.text()
            #expect(!Posix.hasChildProcesses(pid: pid), "プロンプト復帰後も子が残った: \(interruptedOutput)")
            // 引用符により入力エコーの末尾も AFTER の出力と一致させない。
            try await manager.write(Data("echo 'AFTER'\n".utf8), to: id)
            try await output.waitFor("AFTER\r\n")
        }
    }

    @Test("対話シェル配下の前景プログラムへサイズ変更が届く", .timeLimit(.minutes(1)),
          arguments: ["/bin/zsh", "/bin/bash"])
    func foregroundReceivesResize(shell: String) async throws {
        try await withInteractiveShell(shell) { manager, id, output in
            let command = "/bin/sh -c 'trap \"printf WINCH; stty size\" WINCH; printf PROBE_READY; while :; do read line; done'\n"
            try await manager.write(Data(command.utf8), to: id)
            try await output.waitFor("PROBE_READY")
            try await manager.resize(id, cols: 74, rows: 17)
            try await output.waitFor("WINCH17 74\r\n")
        }
    }

    @Test("soft limit より高い fd と複数バッチの fd を継承しない", .timeLimit(.minutes(1)))
    func descriptorsAboveLoweredSoftLimitAreClosed() async throws {
        if try runIsolated("descriptorsAboveLoweredSoftLimitAreClosed") { return }
        do {
            var original = rlimit()
            try #require(getrlimit(RLIMIT_NOFILE, &original) == 0)
            var raised = original
            raised.rlim_cur = max(original.rlim_cur, 2048)
            try #require(setrlimit(RLIMIT_NOFILE, &raised) == 0)
            defer { #expect(setrlimit(RLIMIT_NOFILE, &original) == 0) }

            let source = open("/dev/null", O_WRONLY)
            try #require(source >= 0)
            defer { close(source) }
            let highFD = fcntl(source, F_DUPFD, 1024)
            try #require(highFD >= 1024)
            defer { close(highFD) }
            #expect(fcntl(highFD, F_GETFD) & FD_CLOEXEC == 0)
            var descriptors: [Int32] = []
            defer { for fd in descriptors { close(fd) } }
            for _ in 0..<300 {
                let fd = dup(source)
                try #require(fd >= 0)
                descriptors.append(fd)
            }
            var lowered = raised
            lowered.rlim_cur = 512
            try #require(setrlimit(RLIMIT_NOFILE, &lowered) == 0)
            let pty = try Posix.openPTY(terminalMode: .interactive)
            defer { close(pty.master); close(pty.slave) }
            let numbers = (descriptors.filter { $0 >= 20 } + [highFD]).map(String.init).joined(separator: " ")
            let pid = try Posix.spawn(command: "/bin/sh",
                args: ["-c", "for fd in \(numbers); do if test -e /dev/fd/$fd; then exit 1; fi; done"],
                env: [:], masterFD: pty.master, slaveFD: pty.slave,
                workingDirectory: nil, terminalMode: .interactive)
            var status: Int32 = 0
            var waited: pid_t
            repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
            #expect(waited == pid)
            #expect(status == 0, "シェルが無関係な fd を継承した")
        }
    }

    @Test("起動失敗を反復しても fd と未回収の子が残らない", .timeLimit(.minutes(1)))
    func repeatedFailuresDoNotLeakDescriptorsOrChildren() async throws {
        if try runIsolated("repeatedFailuresDoNotLeakDescriptorsOrChildren") { return }
        do {
            // 別プロセスで実行し、他のテストが持つ子や fd の増減から隔離する。
            signal(SIGCHLD, SIG_DFL)
            let before = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
            for invalidDirectory in [false, true] {
                for _ in 0..<32 {
                    let pty = try Posix.openPTY(terminalMode: .interactive)
                    do {
                        defer { close(pty.master); close(pty.slave) }
                        do {
                            _ = try Posix.spawn(command: invalidDirectory ? "/bin/sh" : "/nonexistent/phlox-shell",
                                args: ["-c", "exit 0"], env: [:], masterFD: pty.master, slaveFD: pty.slave,
                                workingDirectory: invalidDirectory ? "/nonexistent/phlox-cwd" : nil, terminalMode: .interactive)
                            Issue.record("存在しない実行ファイルまたは作業場所で起動が成功した")
                        } catch PTYError.spawnFailed(let code) {
                            #expect(code == ENOENT)
                        }
                    }
                    var status: Int32 = 0
                    let waited = waitpid(-1, &status, WNOHANG)
                    let waitError = errno
                    #expect(waited == -1 && waitError == ECHILD, "起動失敗後に子が残った: waitpid=\(waited), errno=\(waitError)")
                    let after = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
                    #expect(after == before, "起動失敗後に親の fd が増えた")
                }
            }
        }
    }

    @Test("既定の raw でも起動したプロセスに従来どおりサイズ変更を通知する", .timeLimit(.minutes(1)))
    func rawResizeStillNotifiesSpawnedProcess() async throws {
        let manager = PTYManager()
        let id = try await manager.spawn(command: "/bin/sh", args: ["-c",
            "trap 'printf RAW_WINCH; stty size' WINCH; printf RAW_READY; while :; do read line; done",
        ], env: ["PATH": "/usr/bin:/bin"])
        let output = SpawnOutput()
        let reader = Task { for await data in manager.outputStream(for: id) { await output.append(data) } }
        do {
            try await output.waitFor("RAW_READY")
            try await manager.resize(id, cols: 74, rows: 17)
            try await output.waitFor("RAW_WINCH17 74\r\n")
        } catch {
            reader.cancel()
            await manager.terminateAllAndWait(timeout: .seconds(2))
            throw error
        }
        reader.cancel()
        await manager.terminateAllAndWait(timeout: .seconds(2))
    }

    @Test("作業場所と環境を引き継ぎ、無関係な fd を継承しない", .timeLimit(.minutes(1)), arguments: [PTYTerminalMode.interactive, .raw])
    func workingDirectoryEnvironmentAndDescriptors(mode: PTYTerminalMode) async throws {
        let pipe = Pipe()
        defer { pipe.fileHandleForReading.closeFile(); pipe.fileHandleForWriting.closeFile() }
        let fd = pipe.fileHandleForWriting.fileDescriptor
        let directory = FileManager.default.temporaryDirectory.path
        let manager = PTYManager(terminalMode: mode)
        let id = try await manager.spawn(command: "/bin/sh", args: ["-c",
            "pwd; printf 'ENV=%s\\n' \"$PROBE_VALUE\"; if (printf LEAKED >&\(fd)); then printf FD_LEAKED; else printf FD_CLOSED; fi",
        ], env: ["PATH": "/usr/bin:/bin", "PROBE_VALUE": "日本語"], id: nil, initialSize: nil, workingDirectory: directory)
        var bytes = Data()
        for await data in manager.outputStream(for: id) { bytes.append(data) }
        await manager.terminateAllAndWait(timeout: .seconds(2))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        #expect(text.contains("ENV=日本語\r\n"))
        #expect(text.contains("FD_CLOSED"))
        #expect(!text.contains("FD_LEAKED"))
    }

    @Test("exec と cwd の失敗を spawnFailed の errno として伝える", arguments: [false, true])
    func failuresAreReported(invalidDirectory: Bool) async {
        let manager = PTYManager(terminalMode: .interactive)
        do {
            _ = try await manager.spawn(command: invalidDirectory ? "/bin/sh" : "/nonexistent/phlox-shell",
                args: ["-c", "exit 0"], env: [:], id: nil, initialSize: nil, workingDirectory: invalidDirectory ? "/nonexistent/phlox-cwd" : nil)
            Issue.record("存在しない実行ファイルまたは作業場所で起動が成功した")
        } catch PTYError.spawnFailed(let code) {
            #expect(code == ENOENT)
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
        await manager.terminateAllAndWait(timeout: .seconds(2))
    }
}

private func withInteractiveShell(
    _ shell: String,
    body: (PTYManager, SessionID, SpawnOutput) async throws -> Void
) async throws {
    let manager = PTYManager(terminalMode: .interactive)
    let args = shell == "/bin/zsh" ? ["-f", "-i"] : ["--noprofile", "--norc", "-i"]
    let id = try await manager.spawn(command: shell, args: args,
        env: ["PATH": "/usr/bin:/bin", "TERM": "dumb", "PS1": "PTY> ", "PS2": ""])
    let output = SpawnOutput()
    let reader = Task { for await data in manager.outputStream(for: id) { await output.append(data) } }
    do {
        try await output.waitFor("PTY> ")
        // コマンドのエコーを成功印と取り違えない。
        try await manager.write(Data("stty -echo; printf 'SHELL_%s\\n' READY\n".utf8), to: id)
        try await output.waitFor("SHELL_READY\r\n")
        await output.clear()
        try await body(manager, id, output)
    } catch {
        reader.cancel()
        await manager.terminateAllAndWait(timeout: .seconds(2))
        throw error
    }
    reader.cancel()
    await manager.terminateAllAndWait(timeout: .seconds(2))
}

/// 同じ実行ファイルから対象テストだけを起動し、limit・fd・子の所有者を隔離する。
private func runIsolated(_ name: String) throws -> Bool {
    let key = "PHLOX_PTY_ISOLATED_TEST"
    if ProcessInfo.processInfo.environment[key] == name {
        print("PHLOX_PTY_PROBE_STARTED:\(name)")
        return false
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    var arguments = Array(CommandLine.arguments.dropFirst())
    for option in ["--filter", "--event-stream-output-path"] {
        while let index = arguments.firstIndex(of: option) {
            arguments.removeSubrange(index...index + 1)
        }
    }
    process.arguments = arguments + ["--filter", "InteractiveSpawnTests/\(name)"]
    var environment = ProcessInfo.processInfo.environment
    environment[key] = name
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(text.contains("PHLOX_PTY_PROBE_STARTED:\(name)"), "検査本体が実行されなかった: \(CommandLine.arguments)\n\(text)")
    #expect(process.terminationReason == .exit && process.terminationStatus == 0,
        "隔離した検証プロセスが失敗した: \(name), status=\(process.terminationStatus)\n\(text)")
    return true
}

private actor SpawnOutput {
    private var data = Data()
    func append(_ bytes: Data) { data.append(bytes) }
    func text() -> String { String(decoding: data, as: UTF8.self) }
    func clear() { data.removeAll() }
    func waitFor(_ expected: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !String(decoding: data, as: UTF8.self).contains(expected) {
            guard ContinuousClock.now < deadline else {
                throw SpawnOutputTimeout(expected: expected, received: String(decoding: data, as: UTF8.self))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct SpawnOutputTimeout: Error {
    let expected: String
    let received: String
}
