import Darwin
import Foundation
import Testing
@testable import PTYKit

@Suite("ユーザー用とエージェント用の端末初期設定")
struct PTYTerminalModeTests {
    @Test("ユーザー用は echo・icanon・制御文字あり、エージェント既定は従来の raw")
    func initialFlags() throws {
        let interactive = try Posix.openPTY(terminalMode: .interactive)
        let raw = try Posix.openPTY()
        defer { close(interactive.master); close(interactive.slave); close(raw.master); close(raw.slave) }
        var cooked = termios(), agent = termios()
        #expect(tcgetattr(interactive.slave, &cooked) == 0)
        #expect(tcgetattr(raw.slave, &agent) == 0)
        #expect(cooked.c_lflag & tcflag_t(ECHO | ICANON | ISIG) == tcflag_t(ECHO | ICANON | ISIG))
        #expect(agent.c_lflag & tcflag_t(ECHO | ICANON | ISIG) == 0)
        #expect(agent.c_oflag & tcflag_t(OPOST | ONLCR) == tcflag_t(OPOST | ONLCR))
        let characters = withUnsafeBytes(of: cooked.c_cc) { Array($0) }
        #expect(characters[Int(VINTR)] == 3)
        #expect(characters[Int(VEOF)] == 4)
    }

    @Test("対話 bash の stty と、Return 前の入力エコーを実 PTY で確認する", .timeLimit(.minutes(1)))
    func bashEcho() async throws {
        let manager = PTYManager(terminalMode: .interactive)
        let id = try await manager.spawn(command: "/bin/bash", args: ["--noprofile", "--norc", "-i"],
            env: ["PATH": "/usr/bin:/bin", "TERM": "dumb", "PS1": "READY> "])
        let output = TerminalModeOutput()
        let reader = Task { for await data in manager.outputStream(for: id) { await output.append(data) } }
        do {
            try await waitFor("READY> ", output: output)
            try await manager.write(Data("stty -a\n".utf8), to: id)
            try await waitFor("lflags:", output: output)
            let flags = await output.text()
            #expect(flags.contains("icanon") && !flags.contains("-icanon"))
            #expect(flags.contains("echo ") && !flags.contains("-echo "))
            try await manager.write(Data("typed_without_return".utf8), to: id)
            try await waitFor("typed_without_return", output: output)
        } catch {
            await manager.hangUp(id); reader.cancel(); throw error
        }
        await manager.hangUp(id)
        reader.cancel()
    }

    @Test("PTYManager の既定で起動した stty は echo・icanon を無効にする", .timeLimit(.minutes(1)))
    func defaultManagerIsRaw() async throws {
        let manager = PTYManager()
        let id = try await manager.spawn(command: "/bin/sh", args: ["-c", "stty -a; read keep_open"],
                                         env: ["PATH": "/usr/bin:/bin", "TERM": "dumb"])
        let output = TerminalModeOutput()
        let reader = Task { for await data in manager.outputStream(for: id) { await output.append(data) } }
        do {
            try await waitFor("cchars:", output: output)
            let flags = await output.text().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            #expect(flags.contains("-echo"))
            #expect(flags.contains("-icanon"))
        } catch {
            await manager.hangUp(id); reader.cancel(); throw error
        }
        await manager.hangUp(id)
        reader.cancel()
    }

    private func waitFor(_ needle: String, output: TerminalModeOutput) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await output.text().contains(needle)) {
            guard ContinuousClock.now < deadline else { throw TerminalModeTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
private struct TerminalModeTimeout: Error {}
private actor TerminalModeOutput {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    func text() -> String { String(decoding: data, as: UTF8.self) }
}
