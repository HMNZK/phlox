import Foundation
import Testing
@testable import StructuredChatKit

// MARK: - 受け入れテスト（loopflow task-2・PM 著・実装役は編集不可）
//
// 契約: OneShotProcessRunner にタイムアウトを持たせ、期限内にプロセスが終了しない場合は
// プロセスを kill して timeout エラーを throw する（永久ハングを防ぐウォッチドッグ）。
// タイムアウト未指定（nil）のときは従来どおり終了までブロックする（非退行）。
//
// 背景: Cursor の1ターン＝1回の使い捨て cursor-agent 起動を CursorChatClient が
// OneShotProcessRunner.run で待つが、cursor-agent が（シェルスナップショットのデッドロック等で）
// 終了しないと run が永久にブロックし、セッションが「Thinking…」のまま固着していた。

@Test func oneShotRunner_withTimeout_killsNonTerminatingProcessAndThrows() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let started = dir.appendingPathComponent("started")
    let done = dir.appendingPathComponent("done")

    let runner = OneShotProcessRunner(timeout: 1.0)
    let start = Date()

    // sleep 3 の非終了プロセス。1s タイムアウトで kill され、run() は速やかに throw するはず。
    await #expect(throws: (any Error).self) {
        _ = try await runner.run(
            command: "/bin/sh",
            arguments: ["-c", "echo x > '\(started.path)'; sleep 3; echo x > '\(done.path)'"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil
        )
    }

    // 30s 待たず、タイムアウト窓（1s）付近で throw している（永久ブロックしない）。
    #expect(Date().timeIntervalSince(start) < 2.5)

    // プロセスは開始した（started 生成）が、sleep 完了前に kill され done は生成されない。
    // child の sleep(3) 完了時刻を十分に過ぎてから確認する。
    try await Task.sleep(nanoseconds: 3_500_000_000)
    #expect(FileManager.default.fileExists(atPath: started.path))
    #expect(!FileManager.default.fileExists(atPath: done.path))
}

@Test func oneShotRunner_withoutTimeout_completesNormally() async throws {
    let runner = OneShotProcessRunner(timeout: nil)
    let result = try await runner.run(
        command: "/bin/echo",
        arguments: ["hello"],
        environment: ProcessInfo.processInfo.environment,
        workingDirectory: nil
    )
    #expect(result.exitCode == 0)
    #expect(!result.outputLines.isEmpty)
}

@Test func oneShotRunner_withTimeout_fastProcessCompletesBeforeTimeout() async throws {
    // 期限内に終わる通常プロセスは timeout 設定下でも正常完了する（誤爆しない）。
    let runner = OneShotProcessRunner(timeout: 5.0)
    let result = try await runner.run(
        command: "/bin/echo",
        arguments: ["ok"],
        environment: ProcessInfo.processInfo.environment,
        workingDirectory: nil
    )
    #expect(result.exitCode == 0)
}
