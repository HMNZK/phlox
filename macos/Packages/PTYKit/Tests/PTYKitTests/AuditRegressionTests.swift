import AgentDomain
import Darwin
import Foundation
import Testing
@testable import PTYKit

// task-6 監査ハザードの回帰テスト。
// I6: actor 内ブロッキング write が actor 全体を停止させない。
// I7: 出力 AsyncStream が消費側未接続でも無制限蓄積しない（上限で頭打ち）。
// S : terminateAllAndWait のキャンセル時ホットスピン → 即 SIGKILL で早期復帰。
// EINTR (writeAll/waitpid) の決定論的回帰は不能。理由は本ファイル末尾のコメントと
// docs/agent-output/task-6.md を参照。実装は read 側と対称に修正済み。

private let testEnv: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
]

private struct TimeoutError: Error {}

/// 与えられた操作を制限時間内に走らせ、超過したら TimeoutError を投げる。
/// 既存テスト（PTYManagerIntegrationTests 等）の同名ヘルパーと同じ実装。
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

private func collectOutput(
    from stream: AsyncStream<Data>,
    until: @escaping @Sendable (String) -> Bool,
    limit: Int = 64
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

private func collectExitCode(from stream: AsyncStream<Int32>) async -> Int32? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

// MARK: - I6: actor 内ブロッキング write が actor を停止させない

/// stdin を読まない long-running な子へ maxBodyLength 級の大量 write をしている最中でも、
/// actor の別操作（別セッションの pid 取得・kill）が短時間で返ることを検証する。
///
/// 未修正コード（write が actor 内で Posix.writeAll をブロッキング呼び出し）では、
/// PTY の stdin バッファが埋まって write(2) が返らず actor のエグゼキュータが固着し、
/// 後続の pid(for:)/kill が withTimeout 内に返らずタイムアウトで失敗する。
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
        // 詰まる write。修正後は actor 外へオフロードされ、ここは suspend するだけ。
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

// MARK: - I7: 出力 AsyncStream の上限（消費側未接続でも無制限蓄積しない）

/// 消費側が output stream を読まないまま、上限を明確に超える量を子が出力しても、
/// バッファは上限で頭打ちになる（無制限蓄積しない）。
///
/// 未修正（`.unbounded`）では全出力がバッファに溜まり、消費開始後に全量を受け取る。
/// 修正後（`.bufferingNewest(outputBufferLimit)`）では最新 N 要素だけが残り、
/// 受信バイト数は上限（outputBufferLimit * readBufferSize）以下に頭打ちになる。
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
        // 無制限蓄積していないこと: 生成量より確実に少ない（未修正なら全量 = 生成量が返る）。
        #expect(
            receivedBytes < producedBytes,
            "unbounded buffering leaked all output: received \(receivedBytes) == produced \(producedBytes)"
        )
        // サニティ: バッファ末尾は受け取れている。
        #expect(receivedBytes > 0)
    }
}

// MARK: - S: terminateAllAndWait キャンセル時のホットスピン回避

/// 長い timeout で terminateAllAndWait を走らせ途中でキャンセルすると、
/// 未修正コードは `while { try? await Task.sleep }` が CancellationError を握りつぶして
/// deadline まで（ここでは ~10 秒）ビジーループする。修正後はキャンセルを検知して即
/// SIGKILL パスへ抜け、短時間で復帰する。
@Test func terminateAllAndWaitEscalatesPromptlyOnCancellationInsteadOfHotSpinning() async throws {
    let manager = PTYManager()
    // SIGTERM を無視して生き続ける子。SIGKILL でのみ死ぬ。
    let id = try await manager.spawn(
        command: "/bin/sh",
        args: ["-c", "trap '' TERM; echo READY; sleep 30"],
        env: testEnv
    )
    let pid = try #require(await manager.pid(for: id))
    let ready = await collectOutput(from: manager.outputStream(for: id)) { $0.contains("READY") }
    #expect(ready.contains("READY"))

    // 長い timeout で起動し、SIGTERM grace ループに入ったところでキャンセルする。
    let start = ContinuousClock.now
    let task = Task {
        await manager.terminateAllAndWait(timeout: .seconds(10))
    }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    await task.value
    let elapsed = ContinuousClock.now - start

    // 未修正: ホットスピンで deadline（~10s）まで返らない。修正後: 即 SIGKILL で速やかに復帰。
    #expect(
        elapsed < .seconds(3),
        "terminateAllAndWait must escalate to SIGKILL promptly on cancellation, not hot-spin until timeout (elapsed=\(elapsed))"
    )

    // キャンセル経路でも SIGKILL が送られ、子は最終的に死ぬ（reap まで少し待つ）。
    var alive = true
    for _ in 0..<50 {
        if !Posix.isAlive(pid: pid) { alive = false; break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(alive == false, "cancellation must escalate to SIGKILL")

    await manager.terminateAllAndWait(timeout: .seconds(2))
}

// MARK: - EINTR (writeAll / waitpid) について
//
// EINTR retry（read 側と対称に writeAll と waitpid を continue）は実装済みだが、
// 決定論的な回帰テストは書けない。理由:
//   - macOS/BSD の signal() は既定で SA_RESTART 相当のため、シグナルで割り込まれた
//     write(2)/waitpid(2) は自動再開され EINTR がユーザ空間へ返らない。EINTR を強制
//     するには sigaction で SA_RESTART を落とす必要があるが、それは Swift ランタイムや
//     posix_spawn のシグナル設定（Posix.spawn の setsigdefault/setsigmask）と衝突し、
//     テストプロセス全体のシグナル挙動を汚染する。
//   - さらに write を EINTR させるにはブロッキング write 中に正確なタイミングで
//     シグナルを差し込む必要があり、本質的に競合的で flaky。
// よって修正の正しさは read 側（makeReadSource の `errno == EINTR { continue }`）との
// 対称性で担保し、既存の write/waitpid 経路（正常 write 往復・exit code 取得）が緑の
// ままであることで回帰していないことを確認する。
