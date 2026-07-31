import Foundation
import AgentDomain
import PTYKit
import Testing
@testable import DashboardFeature

@Suite("User terminal controller white-box tests")
@MainActor
struct UserTerminalControllerWhiteboxTests {

    @Test("同時に ensureStarted を呼んでも spawn は一度だけで、後続呼び出しは完了を待つ")
    func concurrentEnsureStartedSharesInFlightSpawn() async throws {
        let pty = SpawnGatePTYManager()
        let controller = makeController(pty: pty)

        let firstStart = Task { @MainActor in
            try await controller.ensureStarted()
        }
        let spawnBegan = await pty.waitForFirstSpawnToBegin()
        #expect(spawnBegan)

        let secondStart = Task { @MainActor in
            try await controller.ensureStarted()
        }
        await pty.releaseFirstSpawn()

        try await firstStart.value
        try await secondStart.value

        #expect((await pty.spawnCalls()).count == 1)
        #expect(controller.isRunning)
        await controller.shutdown()
    }

    @Test("spawn の引数を転送し、send は UTF-8 のまま現在のセッションへ書く")
    func forwardsSpawnRequestAndWritesUTF8() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)
        try await controller.send("日本語\n")

        let spawn = try #require(pty.spawnCalls.first)
        #expect(spawn.command == "/bin/sh")
        #expect(spawn.args.isEmpty)
        #expect(spawn.env == ["PATH": "/usr/bin:/bin", "HOME": "/tmp/phlox-user-terminal", "TERM": "dumb"])
        #expect(spawn.id == nil)
        #expect(spawn.initialSize == nil)
        #expect(spawn.workingDirectory == "/tmp/phlox-user-terminal")

        let write = try #require(pty.writtenCalls.first)
        #expect(write.0 == Data("日本語\n".utf8))
        #expect(write.1 == id)

        await controller.shutdown()
    }

    @Test("resize は現在のセッションの PTY へ列と行を転送する")
    func resizeForwardsCurrentSessionSize() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)
        try await controller.resize(cols: 58, rows: 40)

        #expect(pty.resizeCalls == [ResizeCall(id: id, cols: 58, rows: 40)])

        await controller.shutdown()
    }

    @Test("起動前に来た表示サイズを spawn の initialSize に渡す")
    func resizeBeforeStartIsAppliedToSpawn() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.resize(cols: 58, rows: 40)
        try await controller.ensureStarted()

        let spawn = try #require(pty.spawnCalls.first)
        #expect(spawn.initialSize == PTYInitialSize(cols: 58, rows: 40))
        #expect(pty.resizeCalls.isEmpty)

        await controller.shutdown()
    }

    @Test("spawn 中に変わった表示サイズを起動完了後の PTY へ反映する")
    func resizeDuringStartIsFlushedAfterSpawn() async throws {
        let pty = SpawnGatePTYManager()
        let controller = makeController(pty: pty)

        let start = Task { @MainActor in
            try await controller.ensureStarted()
        }
        #expect(await pty.waitForFirstSpawnToBegin())

        try await controller.resize(cols: 58, rows: 40)
        await pty.releaseFirstSpawn()
        try await start.value

        let id = try #require(controller.sessionID)
        #expect((await pty.resizeCalls()) == [ResizeCall(id: id, cols: 58, rows: 40)])

        await controller.shutdown()
    }

    @Test("旧世代の exit は再起動後のセッションを停止させない")
    func staleExitDoesNotStopRestartedSession() async throws {
        let pty = GenerationRacePTY()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let firstID = try #require(controller.sessionID)
        // 旧 observer を next() 待ちにしてからイベントをキューへ積み、shutdown の cancel と
        // 再起動の間に旧イベントが処理される競合を決定論的に作る。
        await Task.yield()
        pty.emitExit(for: firstID, spawnGeneration: 0, code: 137, finish: false)
        await controller.shutdown()
        try await controller.ensureStarted()
        let secondID = try #require(controller.sessionID)
        #expect(firstID == secondID)
        #expect(controller.sessionID == secondID)
        #expect(controller.isRunning)

        await Task.yield()
        #expect(controller.isRunning)

        pty.emitExit(for: secondID, spawnGeneration: 1, code: 0, finish: true)
        try await waitUntil { !controller.isRunning }
        await controller.shutdown()
    }

    @Test("exit 直前に積まれた出力を取りこぼさない")
    func tailOutputBeforeNaturalExitIsDelivered() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)

        let collector = OutputCollector()
        let stream = controller.makeOutputStream()
        let consumeTask = Task {
            for await chunk in stream {
                await collector.append(chunk)
            }
        }
        defer { consumeTask.cancel() }

        for index in 0..<200 {
            pty.emitOutput(for: id, data: Data("\(index),".utf8))
        }
        pty.emitExit(for: id, code: 0)

        try await waitUntil { !controller.isRunning }
        try await waitUntilAsync { await collector.text().contains("199,") }
        #expect(await collector.text().hasPrefix("0,"))

        await controller.shutdown()
    }

    @Test("自然終了を観測した直後に再起動しても旧世代の末尾出力を届ける")
    func tailOutputSurvivesImmediateRestart() async throws {
        let pty = GenerationRacePTY()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let firstID = try #require(controller.sessionID)

        let collector = OutputCollector()
        let stream = controller.makeOutputStream()
        let consumeTask = Task {
            for await chunk in stream {
                await collector.append(chunk)
            }
        }
        defer { consumeTask.cancel() }

        // relay が output stream の next() を待っている状態で自然終了を観測させる。
        await Task.yield()
        pty.emitExit(for: firstID, spawnGeneration: 0, code: 0, finish: true)
        try await waitUntil { !controller.isRunning }

        // exit 観測後、再 spawn 前に旧世代の最後の出力が到着する状況を再現する。
        pty.emitOutput(
            for: firstID,
            spawnGeneration: 0,
            data: Data("tail-after-exit".utf8),
            finish: true
        )
        try await controller.ensureStarted()

        try await waitUntilAsync {
            await collector.text().contains("tail-after-exit")
        }
        #expect(await collector.text().contains("tail-after-exit"))

        await controller.shutdown()
    }

    @Test("自然終了後も旧世代の relay は出力ストリームの finish まで配送する")
    func outputRelayDrainsAfterNaturalExit() async throws {
        let pty = GenerationRacePTY()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let firstID = try #require(controller.sessionID)

        let collector = OutputCollector()
        let stream = controller.makeOutputStream()
        let consumeTask = Task {
            for await chunk in stream {
                await collector.append(chunk)
            }
        }
        defer { consumeTask.cancel() }

        await Task.yield()
        pty.emitExit(for: firstID, spawnGeneration: 0, code: 0, finish: true)
        try await waitUntil { !controller.isRunning }

        pty.emitOutput(
            for: firstID,
            spawnGeneration: 0,
            data: Data("post-exit-tail".utf8),
            finish: true
        )

        try await waitUntilAsync {
            await collector.text().contains("post-exit-tail")
        }
        #expect(await collector.text().contains("post-exit-tail"))

        await controller.shutdown()
    }

    @Test("旧世代の出力は再起動後の購読者へ混入しない")
    func staleOutputDoesNotReachRestartedSession() async throws {
        let pty = GenerationRacePTY()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let firstID = try #require(controller.sessionID)
        let collector = OutputCollector()
        let stream = controller.makeOutputStream()
        let consumeTask = Task {
            for await chunk in stream {
                await collector.append(chunk)
            }
        }
        defer { consumeTask.cancel() }

        pty.emitExit(for: firstID, spawnGeneration: 0, code: 0, finish: true)
        // 実 PTYManager は exit code より先に output stream を finish する。
        pty.emitOutput(
            for: firstID,
            spawnGeneration: 0,
            data: Data(),
            finish: true
        )
        try await waitUntil { !controller.isRunning }

        try await controller.ensureStarted()
        let secondID = try #require(controller.sessionID)
        #expect(firstID == secondID)

        pty.emitOutput(
            for: firstID,
            spawnGeneration: 0,
            data: Data("stale-output".utf8)
        )
        pty.emitOutput(
            for: secondID,
            spawnGeneration: 1,
            data: Data("current-output".utf8)
        )

        try await waitUntilAsync { await collector.text().contains("current-output") }
        #expect(!(await collector.text().contains("stale-output")))

        await controller.shutdown()
    }

    @Test("購読を切って開き直しても出力が届く")
    func outputStreamCanBeResubscribed() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)

        let firstCollector = OutputCollector()
        let firstStream = controller.makeOutputStream()
        let firstTask = Task {
            for await chunk in firstStream {
                await firstCollector.append(chunk)
            }
        }
        pty.emitOutput(for: id, data: Data("A".utf8))
        try await waitUntilAsync { await firstCollector.text().contains("A") }
        firstTask.cancel()
        _ = await firstTask.value

        let secondCollector = OutputCollector()
        let secondStream = controller.makeOutputStream()
        let secondTask = Task {
            for await chunk in secondStream {
                await secondCollector.append(chunk)
            }
        }
        pty.emitOutput(for: id, data: Data("B".utf8))
        try await waitUntilAsync { await secondCollector.text().contains("B") }

        secondTask.cancel()
        _ = await secondTask.value
        await controller.shutdown()
    }

    @Test("同時に2購読しても各購読者が全出力を受け取る")
    func outputStreamFansOutToConcurrentConsumers() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)
        let firstCollector = OutputCollector()
        let secondCollector = OutputCollector()
        let firstStream = controller.makeOutputStream()
        let secondStream = controller.makeOutputStream()
        let firstTask = Task {
            for await chunk in firstStream {
                await firstCollector.append(chunk)
            }
        }
        let secondTask = Task {
            for await chunk in secondStream {
                await secondCollector.append(chunk)
            }
        }
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        for value in ["1", "2", "3", "4"] {
            pty.emitOutput(for: id, data: Data(value.utf8))
        }
        try await waitUntilAsync {
            let firstText = await firstCollector.text()
            let secondText = await secondCollector.text()
            return firstText == "1234" && secondText == "1234"
        }

        await controller.shutdown()
    }

    @Test("exitStream が要素なしで finish しても isRunning が固着しない")
    func exitStreamFinishWithoutElementClearsRunning() async throws {
        let controller = makeController(pty: InstantFinishExitPTY())

        try await controller.ensureStarted()
        try await waitUntil { !controller.isRunning }
        #expect(controller.sessionID == nil)
        await controller.shutdown()
    }

    @Test("start 進行中に shutdown しても、起動したシェルは必ず kill される")
    func shutdownDuringStartKillsSpawnedShell() async throws {
        let pty = SpawnGatePTYManager()
        let controller = makeController(pty: pty)
        let start = Task { @MainActor in
            try await controller.ensureStarted()
        }
        #expect(await pty.waitForFirstSpawnToBegin())

        let stop = Task { @MainActor in
            await controller.shutdown()
        }
        await Task.yield()
        await pty.releaseFirstSpawn()

        try await start.value
        await stop.value
        #expect(!controller.isRunning)
        #expect((await pty.killedIDs()).count == 1)
    }

    @Test("shutdown は自分のセッションだけを kill し、セッション ID を破棄する")
    func shutdownKillsOnlyOwnedSession() async throws {
        let pty = MockPTYManager()
        let controller = makeController(pty: pty)

        try await controller.ensureStarted()
        let id = try #require(controller.sessionID)
        await controller.shutdown()

        #expect(pty.killedIDs == [id])
        #expect(controller.sessionID == nil)
        #expect(!controller.isRunning)
    }

    private func makeController(pty: any PTYManagerProtocol) -> UserTerminalController {
        UserTerminalController(
            pty: pty,
            shellPath: "/bin/sh",
            workingDirectory: "/tmp/phlox-user-terminal",
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp/phlox-user-terminal",
                "TERM": "dumb",
            ]
        )
    }

    private func waitUntil(
        timeoutSeconds: Double = 1,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "タイムアウト: 条件が成立しなかった")
    }

    private func waitUntilAsync(
        timeoutSeconds: Double = 10,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await condition(), "タイムアウト: 条件が成立しなかった")
    }
}

private actor OutputCollector {
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
    }

    func text() -> String {
        String(decoding: buffer, as: UTF8.self)
    }
}

private final class InstantFinishExitPTY: PTYManagerProtocol, @unchecked Sendable {
    let base = MockPTYManager()

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        try await base.spawn(
            command: command,
            args: args,
            env: env,
            id: id,
            initialSize: initialSize,
            workingDirectory: workingDirectory
        )
    }

    func write(_ data: Data, to id: SessionID) async throws {
        try await base.write(data, to: id)
    }

    func kill(_ id: SessionID) async {
        await base.kill(id)
    }

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        try await base.resize(id, cols: cols, rows: rows)
    }

    nonisolated func outputStream(for id: SessionID) -> AsyncStream<Data> {
        base.outputStream(for: id)
    }

    nonisolated func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        AsyncStream { $0.finish() }
    }

    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        nil
    }
}

@MainActor
private final class GenerationRacePTY: @preconcurrency PTYManagerProtocol {
    private var outputStreams: [SessionID: [AsyncStream<Data>]] = [:]
    private var outputContinuations: [SessionID: [AsyncStream<Data>.Continuation]] = [:]
    private var exitStreams: [SessionID: [AsyncStream<Int32>]] = [:]
    private var exitContinuations: [SessionID: [AsyncStream<Int32>.Continuation]] = [:]
    private let sessionID = SessionID()

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        outputStreams[sessionID, default: []].append(outputStream)
        outputContinuations[sessionID, default: []].append(outputContinuation)
        exitStreams[sessionID, default: []].append(exitStream)
        exitContinuations[sessionID, default: []].append(exitContinuation)
        return sessionID
    }

    func write(_ data: Data, to id: SessionID) async throws {}

    func kill(_ id: SessionID) async {}

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {}

    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        outputStreams[id]?.removeFirst() ?? AsyncStream { $0.finish() }
    }

    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        exitStreams[id]?.removeFirst() ?? AsyncStream { $0.finish() }
    }

    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        nil
    }

    func emitOutput(
        for id: SessionID,
        spawnGeneration: Int,
        data: Data,
        finish: Bool = false
    ) {
        guard let continuations = outputContinuations[id],
              continuations.indices.contains(spawnGeneration) else {
            return
        }
        let continuation = continuations[spawnGeneration]
        continuation.yield(data)
        if finish {
            continuation.finish()
        }
    }

    func emitExit(
        for id: SessionID,
        spawnGeneration: Int,
        code: Int32,
        finish: Bool
    ) {
        guard let continuations = exitContinuations[id],
              continuations.indices.contains(spawnGeneration) else {
            return
        }
        let continuation = continuations[spawnGeneration]
        continuation.yield(code)
        if finish {
            continuation.finish()
        }
    }
}

/// MockPTYManager の spawn だけを一時停止し、同時呼び出しの待機契約を決定論的に検証する。
private actor SpawnGatePTYManager: PTYManagerProtocol {
    private let base = MockPTYManager()
    private var firstSpawnStarted = false
    private var firstSpawnRelease: CheckedContinuation<Void, Never>?

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        if !firstSpawnStarted {
            firstSpawnStarted = true
            await withCheckedContinuation { continuation in
                firstSpawnRelease = continuation
            }
        }

        return try await base.spawn(
            command: command,
            args: args,
            env: env,
            id: id,
            initialSize: initialSize,
            workingDirectory: workingDirectory
        )
    }

    func releaseFirstSpawn() {
        firstSpawnRelease?.resume()
        firstSpawnRelease = nil
    }

    func waitForFirstSpawnToBegin() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !firstSpawnStarted && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return firstSpawnStarted
    }

    func spawnCalls() -> [SpawnCall] {
        base.spawnCalls
    }

    func killedIDs() -> [SessionID] {
        base.killedIDs
    }

    func resizeCalls() -> [ResizeCall] {
        base.resizeCalls
    }

    func write(_ data: Data, to id: SessionID) async throws {
        try await base.write(data, to: id)
    }

    func kill(_ id: SessionID) async {
        await base.kill(id)
    }

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        try await base.resize(id, cols: cols, rows: rows)
    }

    nonisolated func outputStream(for id: SessionID) -> AsyncStream<Data> {
        base.outputStream(for: id)
    }

    nonisolated func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        base.exitStream(for: id)
    }

    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        await base.getWinsize(id)
    }
}
