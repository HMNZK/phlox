import AgentDomain
import Darwin
import Foundation
import Testing
@testable import ControlServer

@Suite("モデル取得の終了と出力", .serialized)
struct AcceptanceModelProcessLifetimeTests {
    @Test("正常終了と両パイプ容量超過でも一覧を取得する", arguments: ["small", "leading", "trailing"], ["stderr-first", "stdout-first", "stdout-only", "stderr-only"])
    func drainsBothOutputs(payload: String, direction: String) async throws {
        let list = "printf '\\nAvailable models\\nauto - Auto\\n'\n"
        let flood = #"""
        line=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        i=0
        while [ "$i" -lt 4096 ]; do printf '%s' "$line" >&\#(direction.hasPrefix("stdout") ? 1 : 2); i=$((i + 1)); done
        i=0
        while [ "$i" -lt \#(direction.hasSuffix("only") ? 0 : 4096) ]; do printf '%s' "$line" >&\#(direction.hasPrefix("stdout") ? 2 : 1); i=$((i + 1)); done
        """# + "\n"
        let fixture = try LifetimeFixture(script: payload == "small" ? list :
            (payload == "leading" ? list + flood : flood + list))
        defer { fixture.remove() }
        do {
            let models = try await fixture.provider(timeout: 3).fetchModels(for: .cursor)
            #expect(models == AgentModelCatalog.builtinModels(for: .cursor))
        } catch {
            Issue.record("モデル一覧取得に失敗: \(error)")
        }
    }

    @Test("Claudeの大きなJSONとstderrを先頭末尾とも欠落なく回収する", arguments: [false, true])
    func preservesLargeClaudeJSON(payloadFirst: Bool) async throws {
        let padding = String(repeating: "x", count: 262144)
        let result = #""result":"Current model: Probe\nAvailable: fable, or a full model ID.""#
        let fields = payloadFirst ? result + ",\"padding\":\"" + padding + "\""
            : "\"padding\":\"" + padding + "\"," + result
        let fixture = try LifetimeFixture(script: "printf '%s' '{" + fields + "}'\nprintf '%s' '" + padding + "' >&2")
        defer { fixture.remove() }
        let models = try await fixture.provider(timeout: 3, kind: .claudeCode).fetchModels(for: .claudeCode)
        #expect(models == [ControlModelOption(id: "fable", displayName: "Probe")])
    }

    @Test("Process.run自体の失敗を期限切れへ置換しない")
    func preservesLaunchFailure() async throws {
        let fixture = try LifetimeFixture(script: "exit 0", interpreter: "/phlox-test-missing-interpreter-" + UUID().uuidString)
        defer { fixture.remove() }
        let reference = Process()
        reference.executableURL = fixture.executable
        var expected: NSError?
        do {
            try reference.run()
            reference.terminate()
            Issue.record("存在しないinterpreterが起動した")
        } catch { expected = error as NSError }
        let failure = try #require(expected)
        let started = ContinuousClock.now
        do {
            _ = try await fixture.provider(timeout: 3).fetchModels(for: .cursor)
            Issue.record("起動失敗を成功扱いした")
        } catch {
            #expect((error as NSError).domain == failure.domain)
            #expect((error as NSError).code == failure.code)
        }
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: fixture.pidFile.path))
    }

    @Test("非ゼロ終了はstderr付き取得失敗になる")
    func preservesFailure() async throws {
        let fixture = try LifetimeFixture(script: "printf 'probe-failure\\n' >&2\nexit 23")
        defer { fixture.remove() }
        do {
            _ = try await fixture.provider(timeout: 3).fetchModels(for: .cursor)
            Issue.record("非ゼロ終了を成功扱いした")
        } catch {
            #expect(error.localizedDescription == "CLI exited unsuccessfully: probe-failure")
        }
    }

    @Test("期限切れでTERMを無視する所有CLIも終了する")
    func timeoutReapsOwnedProcess() async throws {
        let fixture = try LifetimeFixture(script: "trap '' TERM\nexec /bin/sleep 20")
        defer { fixture.remove() }
        let started = ContinuousClock.now
        do {
            _ = try await fixture.provider(timeout: 0.5).fetchModels(for: .cursor)
            Issue.record("期限切れを成功扱いした")
        } catch {
            #expect(error.localizedDescription == "CLI model-list request timed out")
        }
        #expect(started.duration(to: .now) < .seconds(3))
        let pid = try fixture.ownedPID()
        for _ in 0..<100 {
            if Darwin.kill(pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH, "期限切れ後に所有CLIが残っている")
    }

    @Test("終了と期限切れの反復競合が一度だけ完了し別プロセスを止めない")
    func terminationDeadlineRaces() async throws {
        let sentinel = Process()
        sentinel.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sentinel.arguments = ["20"]
        try sentinel.run()
        defer { if sentinel.isRunning { sentinel.terminate() } }
        var successes = 0
        var deadlines = 0
        for delay in ["0", "0.35", "0.7", "0", "0.35", "0.7"] {
            let fixture = try LifetimeFixture(script: "/bin/sleep " + delay + "\nprintf 'auto - Auto\\n'")
            defer { fixture.remove() }
            do {
                let models = try await fixture.provider(timeout: 0.5).fetchModels(for: .cursor)
                #expect(models == AgentModelCatalog.builtinModels(for: .cursor))
                successes += 1
            } catch {
                #expect(error.localizedDescription == "CLI model-list request timed out")
                deadlines += 1
            }
            #expect(sentinel.isRunning, "この呼出しと無関係な所有プロセスを止めない")
        }
        #expect(successes > 0)
        #expect(deadlines > 0)
        #expect(successes + deadlines == 6)
    }

    @Test("子孫がpipeを保持しても取得を打ち切りFDを解放する")
    func descendantPipeIsReleased() async throws {
        if ProcessInfo.processInfo.environment["PHLOX_LIFETIME_RESOURCE_CHILD"] != "1" {
            // 別suiteのFD変動を混ぜず、実際のSwiftPMヘルパーでこの検査だけを実走する。
            let flag = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
            let bundle = CommandLine.arguments[flag + 1]
            let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let fixture = try LifetimeFixture(script: "exit 0")
            defer { fixture.remove() }
            let log = fixture.root.appendingPathComponent("child.log")
            #expect(FileManager.default.createFile(atPath: log.path, contents: nil))
            let output = try FileHandle(forWritingTo: log)
            defer { do { try output.close() } catch { Issue.record("ログclose失敗: \(error)") } }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--test-bundle-path", bundle, "--package-path", package.path,
                "--filter", "AcceptanceModelProcessLifetimeTests.descendantPipeIsReleased",
                bundle, "--testing-library", "swift-testing"]
            var environment = ProcessInfo.processInfo.environment
            environment["PHLOX_LIFETIME_RESOURCE_CHILD"] = "1"
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = ContinuousClock.now + .seconds(18)
            while process.isRunning && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                #expect(Darwin.kill(process.processIdentifier, SIGKILL) == 0)
                Issue.record("所有テスト子プロセスの検査期限超過")
            } else {
                let childLog = try String(contentsOf: log, encoding: .utf8)
                #expect(process.terminationStatus == 0, "\(childLog)")
            }
            return
        }

        // Dispatch/Processの初回準備を観測対象から分け、短いタイマーも失効させる。
        let warmup = try LifetimeFixture(script: "printf 'auto - Auto\\n'")
        defer { warmup.remove() }
        _ = try await warmup.provider(timeout: 1).fetchModels(for: .cursor)
        try await Task.sleep(for: .milliseconds(1200))
        let before = try openDescriptorCount()
        var fixtures: [LifetimeFixture] = []
        defer { fixtures.forEach { $0.remove() } }
        for redirection in ["", "2>/dev/null", ">/dev/null"].flatMap({ Array(repeating: $0, count: 4) }) {
            let fixture = try LifetimeFixture(script: "/bin/sleep 20 " + redirection + " &\n" + #"""
            printf '%s' "$!" > "$PHLOX_LIFETIME_DESCENDANT"
            exit 0
            """#)
            fixtures.append(fixture)
            let started = ContinuousClock.now
            do {
                _ = try await fixture.provider(timeout: 1).fetchModels(for: .cursor)
                Issue.record("未完了pipeを一覧取得成功扱いした")
            } catch { #expect(error.localizedDescription == "CLI model-list request timed out") }
            #expect(started.duration(to: .now) < .seconds(2))
            let child = try fixture.ownedPID(at: fixture.descendantFile)
            #expect(Darwin.kill(child, 0) == 0, "背景子が保持中のpipeで検査する")
        }
        // 背景子を止める前に、呼出し側のpipeが解放済みであることを要求する。
        try await Task.sleep(for: .milliseconds(300))
        let after = try openDescriptorCount()
        #expect(after <= before, "反復取得後にFDが残留した")
    }

    private func openDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd")
            .compactMap(Int32.init).filter { fcntl($0, F_GETFD) != -1 }.count
    }
}

private struct LifetimeFixture {
    let root: URL
    let executable: URL
    let pidFile: URL
    let descendantFile: URL

    init(script: String, interpreter: String = "/bin/sh") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-model-lifetime-" + UUID().uuidString)
        executable = root.appendingPathComponent("probe")
        pidFile = root.appendingPathComponent("pid")
        descendantFile = root.appendingPathComponent("descendant")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ("#!" + interpreter + "\nset -eu\nprintf '%s' \"$$\" > \"$PHLOX_LIFETIME_PID\"\n" + script + "\n")
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func provider(timeout: TimeInterval, kind: AgentKind = .cursor) -> LiveAgentModelProvider {
        LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin", "PHLOX_DATA_DIR": root.appendingPathComponent("data").path,
                          "PHLOX_LIFETIME_PID": pidFile.path, "PHLOX_LIFETIME_DESCENDANT": descendantFile.path],
            commands: [kind: executable.path], timeout: timeout
        )
    }

    func ownedPID(at file: URL? = nil) throws -> pid_t {
        let value = try String(contentsOf: file ?? pidFile, encoding: .utf8)
        return try #require(pid_t(value).flatMap { $0 > 1 ? $0 : nil })
    }

    func remove() {
        do {
            for file in [pidFile, descendantFile] where FileManager.default.fileExists(atPath: file.path) {
                let pid = try ownedPID(at: file)
                if Darwin.kill(pid, 0) == 0 {
                    if Darwin.kill(pid, SIGKILL) != 0 && errno != ESRCH {
                        Issue.record("所有CLIの後始末失敗: errno=\(errno)")
                    }
                }
            }
            try FileManager.default.removeItem(at: root)
        } catch { Issue.record("所有fixtureの後始末失敗: \(error)") }
    }
}
