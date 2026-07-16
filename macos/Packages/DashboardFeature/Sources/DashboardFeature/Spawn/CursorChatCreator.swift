import Foundation

struct CursorChatCreator: Sendable {
    let command: String
    let pathEnvironment: String
    /// プロセス終了を待つ上限。超過したら terminate して nil を返す。
    var timeout: Duration = .seconds(10)

    func createChatID() async throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = ["create-chat"]
        process.environment = [
            "PATH": pathEnvironment,
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // 終了待ちは terminationHandler 経由で行い、Thread.sleep のビジーウェイトで
        // 協調スレッドプールを塞がない（P4）。handler は run() 前に設定し、
        // 即時終了プロセスの取りこぼしを防ぐ。
        let (terminations, terminationContinuation) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            terminationContinuation.yield(())
            terminationContinuation.finish()
        }

        try process.run()

        let exitedInTime = await Self.waitForTermination(terminations, timeout: timeout)
        if !exitedInTime, process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let chatID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return chatID.isEmpty ? nil : chatID
    }

    /// 終了通知とタイムアウトを競争させ、時間内に終了したかを返す。
    private static func waitForTermination(
        _ terminations: AsyncStream<Void>,
        timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in terminations {
                    return true
                }
                // タイムアウト側の勝利によるキャンセルで iteration が終了したケース。
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
