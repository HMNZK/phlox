import Foundation
import Testing
@testable import StructuredChatKit

// task-5 白箱テスト（実装役 著）:
// OneShotProcessRunner.run が構造化 Task キャンセルを尊重し、実プロセスを terminate して
// 速やかに return/throw することを、実プロセス（/bin/sleep）で検証する。
// これは CursorChatClient.interrupt() が in-flight run を実際に止められる前提そのもの。

/// `pgrep -f <pattern>` にマッチする現存プロセス数を返す（自身は pgrep が既定で除外）。
private func pgrepCount(matching pattern: String) -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", pattern]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return -1
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    return text
        .split(separator: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .count
}

@Test func oneShotRunner_cancellation_terminatesProcessAndReturnsWithin2s() async throws {
    // 一意な秒数を marker にして pgrep -f で自分の sleep だけを識別する（他テストの sleep と衝突しない）。
    let marker = "30.\(UInt32.random(in: 100_000 ... 999_999))"
    let runner = OneShotProcessRunner() // timeout なし: キャンセル単独の挙動を分離して見る。

    let task = Task<Void, Never> {
        _ = try? await runner.run(
            command: "/bin/sleep",
            arguments: [marker],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil
        )
    }

    // まず実プロセスが起動したことを確認（run が本当に spawn したことの担保。
    // これがないと「起動失敗で即 return」を誤って合格にしてしまう）。
    var appeared = false
    let appearDeadline = Date().addingTimeInterval(3.0)
    while Date() < appearDeadline {
        if pgrepCount(matching: marker) >= 1 {
            appeared = true
            break
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    try #require(appeared, "/bin/sleep \(marker) が起動しなかった（run が spawn していない）")

    // キャンセルする。run は「プロセスが実際に終了したとき」だけ resume するため、
    // 2 秒以内に return できること自体が kill 到達の証拠になる。
    let cancelAt = Date()
    task.cancel()
    _ = await task.value
    let elapsed = Date().timeIntervalSince(cancelAt)
    #expect(elapsed < 2.0, "キャンセル後 2 秒以内に run が返らなかった: \(elapsed)s")

    // プロセスが残存しないこと（terminate 済み）。
    var gone = false
    let goneDeadline = Date().addingTimeInterval(2.0)
    while Date() < goneDeadline {
        if pgrepCount(matching: marker) == 0 {
            gone = true
            break
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(gone, "プロセス残存: /bin/sleep \(marker) がキャンセル後も生存している")
}

@Test func oneShotRunner_cancelledBeforeStart_throwsWithoutSpawning() async throws {
    let marker = "30.\(UInt32.random(in: 100_000 ... 999_999))"
    let runner = OneShotProcessRunner()

    // 開始前にキャンセル済みの Task。run 冒頭の checkCancellation で spawn せず throw する。
    let task = Task<Bool, Never> {
        // 自 Task を先にキャンセルしてから run を呼ぶことで pre-cancel 経路を通す。
        // （呼び出し側は cancel 済み状態を run に渡すのが自然な使い方）
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        do {
            _ = try await runner.run(
                command: "/bin/sleep",
                arguments: [marker],
                environment: ProcessInfo.processInfo.environment,
                workingDirectory: nil
            )
            return false // 例外を投げず戻ってきた = pre-cancel が効いていない
        } catch is CancellationError {
            return true
        } catch {
            return false
        }
    }
    task.cancel()
    let threwCancellation = await task.value
    #expect(threwCancellation, "キャンセル済みでの run は CancellationError を投げるべき")
    // spawn していないので該当プロセスは存在しない。
    #expect(pgrepCount(matching: marker) == 0, "pre-cancel なのにプロセスが起動している")
}
