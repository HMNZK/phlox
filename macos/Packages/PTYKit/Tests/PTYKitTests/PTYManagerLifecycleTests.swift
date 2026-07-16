import AgentDomain
import Darwin
import Foundation
import Testing
@testable import PTYKit

private let testEnv: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
]

private func withTimeout<T: Sendable>(
    seconds: Double = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}

private func collectOutput(
    from stream: AsyncStream<Data>,
    until: @escaping @Sendable (String) -> Bool,
    limit: Int = 32
) async -> String {
    var combined = ""
    var count = 0
    for await chunk in stream {
        if let text = String(data: chunk, encoding: .utf8) {
            combined += text
            if until(combined) { break }
        }
        count += 1
        if count >= limit { break }
    }
    return combined
}

private func collectData(
    from stream: AsyncStream<Data>,
    until: @escaping @Sendable (Data) -> Bool,
    limit: Int = 20_000
) async -> Data {
    var combined = Data()
    var count = 0
    for await chunk in stream {
        combined.append(chunk)
        if until(combined) { break }
        count += 1
        if count >= limit { break }
    }
    return combined
}

private func collectExitCode(from stream: AsyncStream<Int32>) async -> Int32? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

// MARK: - terminateAllAndWait (T5)

@Test func terminateAllAndWaitTerminatesSleepingChildGracefully() async throws {
    try await withTimeout(seconds: 10) {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sleep",
            args: ["30"],
            env: testEnv
        )
        let pid = try #require(await manager.pid(for: id))

        // 子プロセスが SIGTERM を受け取れる状態になるまで待つ
        try await Task.sleep(for: .milliseconds(200))
        await manager.terminateAllAndWait(timeout: .seconds(5))

        #expect(Posix.isAlive(pid: pid) == false)
    }
}

@Test func terminateAllAndWaitEscalatesToSIGKILLWhenChildIgnoresSIGTERM() async throws {
    try await withTimeout(seconds: 10) {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "trap '' TERM; echo READY; sleep 30"],
            env: testEnv
        )
        let pid = try #require(await manager.pid(for: id))

        // trap 設定完了を出力マーカーで待つ
        let ready = await collectOutput(from: manager.outputStream(for: id)) { $0.contains("READY") }
        #expect(ready.contains("READY"))

        // SIGTERM を無視する子に対し、短い timeout で SIGKILL エスカレーションさせる
        await manager.terminateAllAndWait(timeout: .milliseconds(200))

        #expect(Posix.isAlive(pid: pid) == false)
    }
}

@Test func writeAfterTerminateAllAndWaitThrowsSessionNotFound() async throws {
    try await withTimeout(seconds: 10) {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sleep",
            args: ["30"],
            env: testEnv
        )

        try await Task.sleep(for: .milliseconds(200))
        await manager.terminateAllAndWait(timeout: .seconds(5))

        await #expect(throws: PTYError.sessionNotFound) {
            try await manager.write(Data("x".utf8), to: id)
        }
    }
}

// MARK: - spawn 失敗パスとエラーコード (R6)

@Test func spawnNonexistentCommandThrowsSpawnFailedWithENOENT() async {
    let manager = PTYManager()
    // posix_spawn はエラーコードを「戻り値」で返す。errno 誤読だと診断値が信頼できない
    await #expect(throws: PTYError.spawnFailed(errno: ENOENT)) {
        _ = try await manager.spawn(
            command: "/nonexistent/binary-for-pty-test",
            args: [],
            env: testEnv
        )
    }
}

@Test func exitCodeReflectsChildExitStatus() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "exit 3"],
            env: testEnv
        )
        let exitStream = manager.exitStream(for: id)
        let code = await collectExitCode(from: exitStream)
        #expect(code == 3)
    }
}

// MARK: - StreamCache (B1)

@Test func streamCacheRemoveDeletesBothStreams() {
    let cache = StreamCache()
    let id = SessionID()
    let (output, _) = AsyncStream<Data>.makeStream()
    let (exit, _) = AsyncStream<Int32>.makeStream()
    cache.register(id: id, output: output, exit: exit)

    cache.remove(id: id)

    #expect(cache.outputStream(for: id) == nil)
    #expect(cache.exitStream(for: id) == nil)
}

// MARK: - 自然終了後のライフサイクル契約 (B1)

@Test func writeAfterNaturalExitThrowsSessionNotFound() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/usr/bin/true",
            args: [],
            env: testEnv
        )
        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let exitStream = manager.exitStream(for: id)
        let code = await collectExitCode(from: exitStream)
        #expect(code == 0)

        await #expect(throws: PTYError.sessionNotFound) {
            try await manager.write(Data("x".utf8), to: id)
        }
    }
}

@Test func resizeAfterNaturalExitThrowsSessionNotFound() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/usr/bin/true",
            args: [],
            env: testEnv
        )
        let exitStream = manager.exitStream(for: id)
        _ = await collectExitCode(from: exitStream)

        await #expect(throws: PTYError.sessionNotFound) {
            try await manager.resize(id, cols: 120, rows: 40)
        }
    }
}

@Test func getWinsizeAfterNaturalExitReturnsNil() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/usr/bin/true",
            args: [],
            env: testEnv
        )
        let exitStream = manager.exitStream(for: id)
        _ = await collectExitCode(from: exitStream)

        #expect(await manager.getWinsize(id) == nil)
    }
}

@Test func naturalExitRemovesSessionAndCachedStreams() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/usr/bin/true",
            args: [],
            env: testEnv
        )
        let exitStream = manager.exitStream(for: id)
        let code = await collectExitCode(from: exitStream)
        #expect(code == 0)

        #expect(await manager.sessionCount == 0)
        #expect(manager.hasCachedStreams(for: id) == false)
    }
}

@Test func outputEmittedJustBeforeExitIsDeliveredCompletely() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let marker = Data("END_MARKER".utf8)
        let byteCount = 9_000
        let id = try await manager.spawn(
            command: "/usr/bin/awk",
            args: ["BEGIN { for (i = 0; i < \(byteCount); i++) printf \"A\"; printf \"END_MARKER\" }"],
            env: testEnv
        )

        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let outputStream = manager.outputStream(for: id)
        let exitStream = manager.exitStream(for: id)

        // 先に終了を観測してから出力を回収しても、終了直前の出力が欠けないこと
        let code = await collectExitCode(from: exitStream)
        #expect(code == 0)

        let output = await collectData(from: outputStream) { $0.range(of: marker) != nil }
        #expect(output.range(of: marker) != nil)
        #expect(output.count >= byteCount + marker.count)
    }
}

@Test func respawnWithSameExplicitIDAfterExitStartsNewSession() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let sharedID = SessionID()
        _ = try await manager.spawn(
            command: "/usr/bin/true",
            args: [],
            env: testEnv,
            id: sharedID
        )
        let firstExit = manager.exitStream(for: sharedID)
        _ = await collectExitCode(from: firstExit)

        let returnedID = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "read x; printf 'got %s\\n' \"$x\""],
            env: testEnv,
            id: sharedID
        )
        #expect(returnedID == sharedID)
        let outputStream = manager.outputStream(for: sharedID)

        try await manager.write(Data("foo\n".utf8), to: sharedID)
        let output = await collectOutput(from: outputStream) { $0.contains("got foo") }
        #expect(output.contains("got foo"))
    }
}

@Test func respawnWithSameExplicitIDWhileAliveIsLastWinsAndKeepsNewSessionAfterOldExit() async throws {
    try await withTimeout(seconds: 10) {
        let manager = PTYManager()
        let sharedID = SessionID()
        _ = try await manager.spawn(
            command: "/bin/sleep",
            args: ["1"],
            env: testEnv,
            id: sharedID
        )
        // 旧セッションの exit stream は置き換え前に掴んでおく
        let oldExit = manager.exitStream(for: sharedID)
        let oldPID = try #require(await manager.pid(for: sharedID))

        // last-wins: 同一 ID での重複 spawn はレジストリとストリームを置き換える
        _ = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "read x; printf 'got %s\\n' \"$x\""],
            env: testEnv,
            id: sharedID
        )
        let newPID = try #require(await manager.pid(for: sharedID))
        #expect(newPID != oldPID)
        let outputStream = manager.outputStream(for: sharedID)

        // 旧 child の自然終了（とその後始末）を待つ
        _ = await collectExitCode(from: oldExit)

        // 旧 child の後始末が新セッションのレジストリを消していないこと
        try await manager.write(Data("foo\n".utf8), to: sharedID)
        let output = await collectOutput(from: outputStream) { $0.contains("got foo") }
        #expect(output.contains("got foo"))
    }
}
