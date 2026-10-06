import AgentDomain
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

@Test func echoSpawnProducesHelloAndZeroExit() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/echo",
            args: ["hello"],
            env: testEnv
        )

        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let outputStream = manager.outputStream(for: id)
        let exitStream = manager.exitStream(for: id)

        let output = await collectOutput(from: outputStream) { $0.contains("hello") }
        #expect(output.contains("hello"))

        let exitCode = await collectExitCode(from: exitStream)
        #expect(exitCode == 0)
    }
}

@Test func spawnWithExplicitIDReturnsSameID() async throws {
    let manager = PTYManager()
    let expectedID = SessionID()
    let returnedID = try await manager.spawn(
        command: "/usr/bin/true",
        args: [],
        env: testEnv,
        id: expectedID
    )
    #expect(returnedID == expectedID)
}

@Test func shellReadWriteRoundTrip() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "read x; printf 'got %s\\n' \"$x\""],
            env: testEnv
        )

        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let outputStream = manager.outputStream(for: id)

        try await manager.write(Data("foo\n".utf8), to: id)

        let output = await collectOutput(from: outputStream) { $0.contains("got foo") }
        #expect(output.contains("got foo"))
    }
}

@Test func outputLargerThanReadBufferIsDeliveredCompletely() async throws {
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

        let output = await collectData(from: outputStream) { data in
            data.range(of: marker) != nil
        }

        #expect(output.count >= byteCount + marker.count)
        #expect(output.prefix(byteCount).allSatisfy { $0 == 65 })
        #expect(output.range(of: marker) != nil)

        let exitCode = await collectExitCode(from: exitStream)
        #expect(exitCode == 0)
    }
}

@Test func writeLargerThanReadBufferIsDeliveredCompletely() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let marker = Data("END_MARKER".utf8)
        let byteCount = 9_000
        let payload = Data(repeating: 66, count: byteCount)
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "stty raw -echo; dd bs=1 count=\(byteCount) 2>/dev/null; printf END_MARKER"],
            env: testEnv
        )

        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let outputStream = manager.outputStream(for: id)
        let exitStream = manager.exitStream(for: id)

        try await Task.sleep(for: .milliseconds(200))
        try await manager.write(payload, to: id)

        let output = await collectData(from: outputStream) { data in
            data.range(of: marker) != nil
        }

        #expect(output.count >= byteCount + marker.count)
        #expect(output.prefix(byteCount).allSatisfy { $0 == 66 })
        #expect(output.range(of: marker) != nil)

        let exitCode = await collectExitCode(from: exitStream)
        #expect(exitCode == 0)
    }
}

@Test func killTerminatesAndEmitsExitCode() async throws {
    try await withTimeout(seconds: 5) {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sleep",
            args: ["30"],
            env: testEnv
        )

        // stream は spawn 直後に取得する（終了後は StreamCache から削除されるため）
        let exitStream = manager.exitStream(for: id)

        // 子プロセスが SIGTERM を受け取れる状態になるまで待つ
        try await Task.sleep(for: .milliseconds(200))
        await manager.kill(id)

        // 既存の collectExitCode と同じパターン
        let code = await collectExitCode(from: exitStream)
        // SIGTERM 由来で 0 以外（macOS では 128+15=143 など）
        #expect(code != nil)
        #expect(code != 0)
    }
}

@Test func writeToUnknownSessionThrowsSessionNotFound() async throws {
    let manager = PTYManager()
    let bogusID = SessionID()
    await #expect(throws: PTYError.sessionNotFound) {
        try await manager.write(Data("x".utf8), to: bogusID)
    }
}

// MARK: - プロセスグループ kill (task-1)

/// kill(_:) は SIGTERM をプロセスグループ全体に送り、孫プロセスまで終了させる。
/// 孫を nohup で起動することで SIGHUP による偶発的終了を防ぎ、
/// killpg(SIGTERM) が届いた時だけ孫が終了することを検証する（真の回帰テスト）。
@Test func killTerminatesGrandchildProcess() async throws {
    try await withTimeout(seconds: 10) {
        let manager = PTYManager()
        // nohup で起動した孫は SIGHUP を無視するため、シェルへの kill(SIGTERM) だけでは消えない。
        // プロセスグループへの killpg(SIGTERM) が届いた場合のみ SIGTERM で消える。
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "/usr/bin/nohup /bin/sleep 30 >/dev/null 2>&1 & echo GRANDCHILD:$!; wait"],
            env: testEnv
        )
        let outputStream = manager.outputStream(for: id)

        // 孫の PID を出力から取得する
        let output = await collectOutput(from: outputStream) { $0.contains("GRANDCHILD:") }
        let grandchildPid: pid_t = try {
            let prefix = "GRANDCHILD:"
            guard let range = output.range(of: prefix) else {
                throw PTYError.spawnFailed(errno: EINVAL)
            }
            let after = String(output[range.upperBound...])
            let pidStr = after.components(separatedBy: .whitespacesAndNewlines).first ?? ""
            guard let pid = pid_t(pidStr) else {
                throw PTYError.spawnFailed(errno: EINVAL)
            }
            return pid
        }()

        // 孫が生きていることを確認してから kill
        #expect(Posix.isAlive(pid: grandchildPid) == true)
        try await Task.sleep(for: .milliseconds(200))
        await manager.kill(id)

        // 孫も終了していること（最大 2 秒ポーリング）
        var grandchildAlive = true
        for _ in 0..<20 {
            if !Posix.isAlive(pid: grandchildPid) {
                grandchildAlive = false
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(grandchildAlive == false, "kill(_:) should terminate grandchild process via SIGTERM to process group")
    }
}

// MARK: - 詰まりと滞留: stdin の大量 write・出力バッファの上限

/// stdin を読まない long-running な子へ maxBodyLength 級の大量 write をしている最中でも、
/// actor の別操作（別セッションの pid 取得・kill）が短時間で返ることを検証する。
///
/// write が actor 内でブロッキングすると、PTY の stdin バッファが埋まって write(2) が返らず
/// actor のエグゼキュータが固着し、後続の pid(for:)/kill が withTimeout 内に返らない。
@Test func largeWriteToStdinIgnoringChildDoesNotBlockActor() async throws {
    let manager = PTYManager()

    // stdin を一切読まず生き続ける子。master への write は slave 入力バッファが埋まると
    // ブロックする（未修正なら actor ごと固まる）。SIGTERM で後始末できるよう trap はしない。
    let blockerID = try await manager.spawn(
        command: "/bin/sleep",
        args: ["30"],
        env: testEnv
    )
    // 並行して操作する別セッション。
    let otherID = try await manager.spawn(
        command: "/bin/sleep",
        args: ["30"],
        env: testEnv
    )

    // PTY の stdin バッファ（数 KB）を遥かに超える payload。子が読まないので write は詰まる。
    let bigPayload = Data(repeating: 65, count: 4 * 1024 * 1024)
    let writeTask = Task {
        // 詰まる write。actor 外へオフロードされ、ここは suspend するだけ。
        try? await manager.write(bigPayload, to: blockerID)
    }

    // write が始まり PTY バッファを埋めて詰まるまで待つ。
    try await Task.sleep(for: .milliseconds(300))

    // 別セッションへの actor 操作が短時間で返ること（actor がフリーズしていない）。
    try await withTimeout(seconds: 3) {
        let pid = await manager.pid(for: otherID)
        #expect(pid != nil)
        await manager.kill(otherID)
    }

    // 後始末: blocker を落として詰まった write を EIO で解放する。
    writeTask.cancel()
    await manager.terminateAllAndWait(timeout: .seconds(2))
}

/// 消費側が output stream を読まないまま、上限を明確に超える量を子が出力しても、
/// バッファは上限で頭打ちになる（無制限蓄積しない）。
///
/// 最新 N 要素（`outputBufferLimit`）だけが残り、受信バイト数は
/// 上限（outputBufferLimit * readBufferSize）以下に頭打ちになる。
@Test func outputStreamDoesNotGrowUnboundedWhenConsumerNotConnected() async throws {
    try await withTimeout(seconds: 20) {
        let manager = PTYManager()

        let limit = PTYManager.outputBufferLimit
        let chunkSize = PTYManager.readBufferSize
        // 上限を確実に超える生成量（上限 + 余裕分）。
        let producedChunks = limit + 256
        let producedBytes = producedChunks * chunkSize

        // dd で /dev/zero を bulk 出力（stderr 統計は PTY に混ざるので /dev/null へ捨てる）。
        // 0 バイトは PTY 出力後処理（ONLCR 等）の影響を受けないのでバイト数が保存される。
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "dd if=/dev/zero bs=\(chunkSize) count=\(producedChunks) 2>/dev/null"],
            env: testEnv
        )

        // spawn 直後に stream を取得（終了後は StreamCache から消えるため）。
        let outputStream = manager.outputStream(for: id)
        let exitStream = manager.exitStream(for: id)

        // output を消費せずに、子の終了だけ待つ。この間 read source は出力を
        // バッファへ yield し続ける（上限付きなら古い要素が捨てられて頭打ち）。
        _ = await collectExitCode(from: exitStream)

        // 終了後に初めて output を全量ドレインしてバイト数を数える。
        var receivedBytes = 0
        for await chunk in outputStream {
            receivedBytes += chunk.count
        }

        // 頭打ち: 受信量は上限（要素数 * 1要素の最大バイト）以下。
        #expect(
            receivedBytes <= limit * chunkSize,
            "output buffer must be bounded: received \(receivedBytes) > cap \(limit * chunkSize)"
        )
        // 無制限蓄積していないこと: 生成量より確実に少ない。
        #expect(
            receivedBytes < producedBytes,
            "unbounded buffering leaked all output: received \(receivedBytes) == produced \(producedBytes)"
        )
        // サニティ: バッファ末尾は受け取れている。
        #expect(receivedBytes > 0)
    }
}

// EINTR (writeAll / waitpid) の retry は read 側（makeReadSource の `errno == EINTR { continue }`）と対称に実装している。
// 決定論的な回帰テストは書けない: macOS の signal() は既定で SA_RESTART 相当で EINTR がユーザ空間へ返らず、
// SA_RESTART を落とすとテストプロセス全体のシグナル挙動を汚染し、write 中への正確なシグナル注入は flaky になる。
