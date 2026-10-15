import AgentDomain
import Darwin
import Foundation
import PTYKit
import Testing
import os
@testable import DashboardFeature

@Suite("ユーザー端末の同期配送と背圧", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct UserTerminalBackpressureTests {
    private let pattern = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-"

    private func command(repetitions: Int) -> String {
        "awk 'BEGIN { for (i=0; i<\(repetitions); i++) printf \"%08d:%s|\", i, \"\(pattern)\" }'\n"
    }

    private func makeController(_ pty: AcknowledgementPTY) -> UserTerminalController {
        UserTerminalController(pty: pty, shellPath: "/bin/sh", workingDirectory: "/tmp",
            environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb", "PS1": "", "PS2": ""])
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw TerminalDeliveryTimeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("大量出力の内容と順序を保ち、全購読者が戻った後にだけ通知する")
    func callbacksCompleteBeforeAcknowledgement() async throws {
        let pty = AcknowledgementPTY()
        let controller = makeController(pty)
        let expected = Data((0..<147456).map { String(format: "%08d:%@|", $0, pattern) }.joined().utf8)
        var first = Data()
        var second = Data()
        let firstToken = controller.observeOutput { data in
            first.append(data)
            pty.progress.withLock { $0.first += data.count }
        }
        let secondToken = controller.observeOutput { data in
            second.append(data)
            pty.progress.withLock { $0.second += data.count }
        }
        do {
            try await controller.ensureStarted()
            let id = try #require(controller.sessionID)
            try await controller.send(command(repetitions: 147456))
            try await waitUntil { pty.progress.withLock { $0.acknowledged == expected.count } }
            let firstMatches = first == expected
            let secondMatches = second == expected
            #expect(firstMatches)
            #expect(secondMatches)
            #expect(pty.progress.withLock { $0.afterBoth })
            #expect(pty.progress.withLock { $0.ids == Set([id]) })
        } catch {
            await controller.shutdown()
            await pty.real.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
        controller.removeOutputObserver(firstToken)
        controller.removeOutputObserver(secondToken)
        await controller.shutdown()
        await pty.real.terminateAllAndWait(timeout: .seconds(1))
    }

    @Test("購読者ゼロでも出力を消費し、登録と解除の後も進む")
    func zeroSubscribersAndRegistration() async throws {
        let pty = AcknowledgementPTY()
        let controller = makeController(pty)
        do {
            try await controller.ensureStarted()
            try await controller.send(command(repetitions: 49152))
            try await waitUntil { pty.progress.withLock { $0.acknowledged == 3 * 1024 * 1024 } }
            var received = Data()
            let token = controller.observeOutput { received.append($0) }
            try await controller.send("printf REGISTERED\n")
            try await waitUntil { received == Data("REGISTERED".utf8) }
            controller.removeOutputObserver(token)
            try await controller.send(command(repetitions: 49152))
            try await waitUntil { pty.progress.withLock { $0.acknowledged == 6 * 1024 * 1024 + 10 } }
            var again = Data()
            controller.observeOutput { again.append($0) }
            try await controller.send("printf AGAIN\n")
            try await waitUntil { again == Data("AGAIN".utf8) }
        } catch {
            await controller.shutdown()
            await pty.real.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
        await controller.shutdown()
        await pty.real.terminateAllAndWait(timeout: .seconds(1))
    }

    @Test("SIGHUPを無視して有限出力する旧シェルもrestart後に終了する")
    func restartAbandonsOldOutput() async throws {
        let pty = AcknowledgementPTY()
        let controller = makeController(pty)
        var ready = false
        var restartedOutput = Data()
        controller.observeOutput { data in
            ready = true
            restartedOutput.append(data)
        }
        var oldPID: pid_t?
        do {
            try await controller.ensureStarted()
            let oldID = try #require(controller.sessionID)
            oldPID = await pty.real.pid(for: oldID)
            // 最初の出力はtrap設定後。有限出力の後は明示exitし、生存を放置しない。
            try await controller.send("trap '' HUP\n" + command(repetitions: 147456) + "exit\n")
            try await waitUntil { ready }
            try await controller.restart()
            let newID = try #require(controller.sessionID)
            #expect(newID != oldID)
            restartedOutput.removeAll()
            try await controller.send("printf NEW_SESSION\n")
            try await waitUntil { restartedOutput == Data("NEW_SESSION".utf8) }
            if let pid = oldPID {
                try await waitUntil { Darwin.kill(pid, 0) != 0 && errno == ESRCH }
            }
        } catch {
            if let pid = oldPID { Darwin.kill(-pid, SIGKILL) }
            await controller.shutdown()
            await pty.real.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
        await controller.shutdown()
        await pty.real.terminateAllAndWait(timeout: .seconds(1))
    }
}

/// 実PTYを使い、通知の呼び出し時点だけを観測する。
private final class AcknowledgementPTY: PTYManagerProtocol, Sendable {
    let real = PTYManager()
    struct Progress {
        var first = 0
        var second = 0
        var acknowledged = 0
        var afterBoth = true
        var ids = Set<SessionID>()
    }
    let progress = OSAllocatedUnfairLock(initialState: Progress())

    func acknowledgeOutput(_ count: Int, for id: SessionID) {
        progress.withLock { state in
            state.acknowledged += count
            state.afterBoth = state.afterBoth && state.first == state.acknowledged && state.second == state.acknowledged
            state.ids.insert(id)
        }
        real.acknowledgeOutput(count, for: id)
    }

    func spawn(command: String, args: [String], env: [String: String], id: SessionID?,
               initialSize: PTYInitialSize?, workingDirectory: String?) async throws -> SessionID {
        // 識別用出力だけを比較するため、実シェルのプロンプト・readlineを無効にする。
        try await real.spawn(command: command, args: args.isEmpty ? ["+i"] : args, env: env, id: id,
            initialSize: initialSize, workingDirectory: workingDirectory)
    }
    func write(_ data: Data, to id: SessionID) async throws { try await real.write(data, to: id) }
    func kill(_ id: SessionID) async { await real.kill(id) }
    func hangUp(_ id: SessionID) async { await real.hangUp(id) }
    func outputStream(for id: SessionID) -> AsyncStream<Data> { real.outputStream(for: id) }
    func exitStream(for id: SessionID) -> AsyncStream<Int32> { real.exitStream(for: id) }
}

private struct TerminalDeliveryTimeout: Error {}
