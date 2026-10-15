import AgentDomain
import Darwin
import Dispatch
import Foundation
import Testing
import os
@testable import PTYKit

@Suite("PTY出力の背圧", .serialized, .timeLimit(.minutes(1)))
struct OutputBackpressureTests {
    private let env = ["PATH": "/usr/bin:/bin"]
    // 8桁の連番＋区切り＋54文字＋末尾の | で64バイト。PTYの改行変換を避ける。
    private let pattern = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-"

    private func producer(bytes: Int) -> String {
        "awk 'BEGIN { for (i=0; i<\(bytes / 64); i++) printf \"%08d:%s|\", i, \"\(pattern)\" }'"
    }

    private func expectedOutput(bytes: Int) -> Data {
        Data((0..<((bytes + 63) / 64)).map { String(format: "%08d:%@|", $0, pattern) }.joined().utf8)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw BackpressureTimeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("停止中もkill・hangUp・全終了・自然終了が進みfdを閉じる")
    func suspendedExitPathsCloseDescriptors() async throws {
        // fd 数は他の並列スイートの増減から隔離して測る（既存の実PTYテストと同じ方式）。
        if ProcessInfo.processInfo.environment["PHLOX_BP_ISOLATED"] != "1" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            var arguments = Array(CommandLine.arguments.dropFirst())
            while let index = arguments.firstIndex(of: "--filter") {
                arguments.removeSubrange(index...index + 1)
            }
            process.arguments = arguments + ["--filter", "OutputBackpressureTests/suspendedExitPathsCloseDescriptors"]
            var environment = ProcessInfo.processInfo.environment
            environment["PHLOX_BP_ISOLATED"] = "1"
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        for path in ["kill", "hangUp", "all", "natural"] {
            let manager = PTYManager()
            let id = try await manager.spawn(command: "/bin/sh",
                args: ["-c", producer(bytes: OutputGate.highWater) + "; read release; printf TAIL"], env: env)
            let output = manager.outputStream(for: id)
            let exits = manager.exitStream(for: id)
            let gate = try #require(manager.outputGate(for: id))
            let pid = try #require(await manager.pid(for: id))
            let code = OSAllocatedUnfairLock<Int32?>(initialState: nil)
            let exitTask = Task { for await value in exits { code.withLock { $0 = value } } }
            do {
                try await waitUntil { gate.snapshot.suspended }
                switch path {
                case "kill": await manager.kill(id)
                case "hangUp": await manager.hangUp(id)
                case "all": await manager.terminateAllAndWait(timeout: .seconds(1))
                default: try await manager.write(Data("go\n".utf8), to: id)
                }
                try await waitUntil { code.withLock { $0 != nil } }
                #expect(!Posix.isAlive(pid: pid))
                #expect(gate.snapshot.cancelled)
                #expect(!gate.snapshot.suspended)
                if path == "natural" {
                    var received = Data()
                    for await chunk in output { received.append(chunk) }
                    var expected = expectedOutput(bytes: OutputGate.highWater)
                    expected.append(Data("TAIL".utf8))
                    let matches = received == expected
                    #expect(matches, "受信=\(received.count), 期待=\(expected.count), 末尾=\(String(decoding: received.suffix(80), as: UTF8.self))")
                    #expect(code.withLock { $0 } == 0)
                }
            } catch {
                exitTask.cancel()
                await manager.terminateAllAndWait(timeout: .seconds(1))
                throw error
            }
            await exitTask.value
            try await waitUntil {
                (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) == before
            }
        }
    }

    @Test("消費通知がなくても停止中の受信増加は100msごとに最大1チャンク")
    func trickleLimitsUnacknowledgedOutput() async throws {
        let manager = PTYManager()
        let id = try await manager.spawn(command: "/usr/bin/awk",
            args: ["BEGIN { for (i=0;;i++) printf \"%08d:%s|\", i, \"\(pattern)\" }"], env: env)
        let output = manager.outputStream(for: id)
        let exits = manager.exitStream(for: id)
        let gate = try #require(manager.outputGate(for: id))
        let pid = try #require(await manager.pid(for: id))
        do {
            try await waitUntil { gate.snapshot.suspended }
            // 停止を観測してから1秒間、消費通知を一切送らない。
            try await Task.sleep(for: .seconds(1))
            let pending = gate.snapshot.pendingBytes
            // 初回の端数、観測時点、終了時drainに4チャンクの余裕を持たせる。
            let limit = OutputGate.highWater
                + (1000 / OutputGate.trickleIntervalMilliseconds + 4) * PTYManager.readBufferSize
            #expect(pending > OutputGate.highWater)
            #expect(pending <= limit)
            #expect(Posix.isAlive(pid: pid))
            await manager.kill(id)
            var received = Data()
            for await chunk in output { received.append(chunk) }
            #expect(received.count >= pending)
            #expect(received.count <= limit)
            let expected = expectedOutput(bytes: received.count)
            let matches = received == expected.prefix(received.count)
            #expect(matches)
            for await code in exits { #expect(code != 0) }
        } catch {
            await manager.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
    }

    @Test("古い世代のtrickleを直接呼んでも再停止は解除されない")
    func trickleIgnoresEarlierSuspendEpochs() throws {
        let pipe = Pipe()
        let source = DispatchSource.makeReadSource(fileDescriptor: pipe.fileHandleForReading.fileDescriptor)
        source.resume()
        let gate = OutputGate(readSource: source)
        defer { gate.cancel() }

        gate.record(OutputGate.highWater)
        let epochA = gate.snapshot.suspendEpoch
        #expect(gate.snapshot.suspended)
        gate.acknowledge(OutputGate.highWater)
        #expect(!gate.snapshot.suspended)
        gate.record(OutputGate.highWater)
        let epochB = gate.snapshot.suspendEpoch
        #expect(epochB > epochA)
        #expect(gate.snapshot.suspended)

        gate.trickle(epoch: epochA)
        #expect(gate.snapshot.suspended)
        #expect(gate.snapshot.suspendEpoch == epochB)
        // 現在の世代なら再開することも確かめ、常に何もしない実装を検出する。
        gate.trickle(epoch: epochB)
        #expect(!gate.snapshot.suspended)
    }

    @Test("未消費量が上限なら複数read分の残出力を1readで打ち切る")
    func descendantOutputDrainStopsAtHighWater() async throws {
        let pipe = Pipe()
        let readFD = pipe.fileHandleForReading.fileDescriptor
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD)
        source.resume()
        let gate = OutputGate(readSource: source)
        defer { gate.cancel() }
        let (output, continuation) = AsyncStream<Data>.makeStream()
        defer { continuation.finish() }

        // 全量をdrainより先に書き込み、書き手を開いたまま保持する。
        // 打ち切りがなければ3read後のEAGAINまで配送される。
        let payload = expectedOutput(bytes: 3 * PTYManager.readBufferSize)
        let flags = fcntl(writeFD, F_GETFL)
        try #require(flags >= 0)
        try #require(fcntl(writeFD, F_SETFL, flags | O_NONBLOCK) == 0)
        let written = payload.withUnsafeBytes { write(writeFD, $0.baseAddress, $0.count) }
        try #require(written == payload.count)
        gate.record(OutputGate.highWater)

        PTYManager.drainRemainingOutput(masterFD: readFD, gate: gate, into: continuation)
        continuation.finish()
        var chunks: [Data] = []
        for await chunk in output { chunks.append(chunk) }
        #expect(chunks.count == 1)
        #expect(chunks.first == Data(payload.prefix(PTYManager.readBufferSize)))
        #expect(gate.snapshot.pendingBytes == OutputGate.highWater + PTYManager.readBufferSize)

        // 2read分がまだ残ることを確認し、入力不足による終了ではないと示す。
        var remaining = [UInt8](repeating: 0, count: payload.count)
        let count = read(readFD, &remaining, remaining.count)
        #expect(count == 2 * PTYManager.readBufferSize)
        if count > 0 {
            #expect(Data(remaining.prefix(count)) == Data(payload.dropFirst(PTYManager.readBufferSize)))
        }
        withExtendedLifetime(pipe) {}
    }

    @Test("読取タスクの取消で停止を解除し、子が終了まで進む")
    func cancellingReaderAbandonsGate() async throws {
        let manager = PTYManager()
        let id = try await manager.spawn(command: "/bin/sh",
            args: ["-c", producer(bytes: 3 * OutputGate.highWater)], env: env)
        let stream = manager.outputStream(for: id)
        let exits = manager.exitStream(for: id)
        let gate = try #require(manager.outputGate(for: id))
        do {
            try await waitUntil { gate.snapshot.suspended }
            let reader = Task { for await _ in stream {} }
            reader.cancel()
            await reader.value
            try await waitUntil { gate.snapshot.abandoned }
            let exited = OSAllocatedUnfairLock(initialState: false)
            let task = Task { for await code in exits { #expect(code == 0); exited.withLock { $0 = true } } }
            defer { task.cancel() }
            try await waitUntil { exited.withLock { $0 } }
            #expect(!gate.snapshot.suspended)
        } catch {
            await manager.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
    }

    @Test("同じIDへの置換は旧ストリームの配送を止め、旧子を止めない")
    func replacementAbandonsOldGate() async throws {
        let manager = PTYManager()
        let id = try await manager.spawn(command: "/bin/sh",
            args: ["-c", producer(bytes: 3 * OutputGate.highWater)], env: env)
        let oldOutput = manager.outputStream(for: id)
        let oldExits = manager.exitStream(for: id)
        let gate = try #require(manager.outputGate(for: id))
        do {
            try await waitUntil { gate.snapshot.suspended }
            let bufferedBeforeReplacement = gate.snapshot.pendingBytes
            _ = try await manager.spawn(command: "/bin/sh", args: ["-c", "read release"], env: env, id: id)
            #expect(gate.snapshot.abandoned)
            let exited = OSAllocatedUnfairLock(initialState: false)
            let task = Task { for await code in oldExits { #expect(code == 0); exited.withLock { $0 = true } } }
            defer { task.cancel() }
            try await waitUntil { exited.withLock { $0 } }
            var received = Data()
            for await chunk in oldOutput { received.append(chunk) }
            // 旧ストリームを未消費で保持したまま、旧子が残りの出力を終えるまで待った。
            // 置換と競合する1チャンクを許容し、以後の出力は追加されない。
            #expect(received.count >= bufferedBeforeReplacement)
            #expect(received.count <= bufferedBeforeReplacement + PTYManager.readBufferSize)
            let matches = received == expectedOutput(bytes: received.count).prefix(received.count)
            #expect(matches)
            #expect(manager.outputGate(for: id)?.snapshot.abandoned == false)
        } catch {
            await manager.terminateAllAndWait(timeout: .seconds(1))
            throw error
        }
        await manager.terminateAllAndWait(timeout: .seconds(1))
    }

    @Test("停止・通知・取消・放棄が競合しても停止回数が釣り合う")
    func gateRacesAndRepeatedTransitions() async throws {
        for _ in 0..<32 {
            let pipe = Pipe()
            let source = DispatchSource.makeReadSource(fileDescriptor: pipe.fileHandleForReading.fileDescriptor)
            let closed = OSAllocatedUnfairLock(initialState: false)
            source.setCancelHandler { closed.withLock { $0 = true } }
            source.resume()
            let gate = OutputGate(readSource: source)
            // 繰り返し上下限を横切り、過剰通知は0で止まる。
            for _ in 0..<16 {
                gate.record(OutputGate.highWater)
                #expect(gate.snapshot.suspended)
                gate.acknowledge(OutputGate.highWater - OutputGate.lowWater - 1)
                #expect(gate.snapshot.suspended)
                gate.acknowledge(1)
                #expect(!gate.snapshot.suspended)
                gate.acknowledge(OutputGate.highWater + 1)
                #expect(gate.snapshot.pendingBytes == 0)
                #expect(!gate.snapshot.suspended)
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for _ in 0..<100 { gate.record(OutputGate.highWater) } }
                group.addTask { for _ in 0..<100 { gate.acknowledge(OutputGate.highWater) } }
                group.addTask { gate.cancel(); gate.cancel() }
                group.addTask { gate.abandon(); gate.abandon() }
            }
            gate.record(OutputGate.highWater)
            try await waitUntil { closed.withLock { $0 } }
            #expect(gate.snapshot.cancelled)
            #expect(!gate.snapshot.suspended)
        }
    }
}

private struct BackpressureTimeout: Error {}
