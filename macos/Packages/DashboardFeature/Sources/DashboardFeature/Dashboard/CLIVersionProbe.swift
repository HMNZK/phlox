import Foundation

/// 起動カードの 2 行目に出す CLI の版を `--version` で読む（08 S3・S4）。
/// 5 秒で返らなければ打ち切る。組込の CLI にだけ使う（カスタムは `--version` を解さないことがあるため）。
enum CLIVersionProbe {
    static func version(executable: String, pathEnvironment: String) async -> String? {
        await Task.detached { run(executable: executable, pathEnvironment: pathEnvironment) }.value
    }

    private static func run(executable: String, pathEnvironment: String) -> String? {
        // 出力はパイプではなく一時ファイルへ。孫プロセスが出力を握ったままでも EOF 待ちで止まらない。
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-version-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.environment = ProcessInfo.processInfo.environment.merging(["PATH": pathEnvironment]) { $1 }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return nil }
        // 5 秒で返らなければ強制終了して版は出さない（終了信号を無視する CLI もあるため SIGKILL）。
        guard exited.wait(timeout: .now() + 5) == .success else {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }
        return parse((try? String(contentsOf: output, encoding: .utf8)) ?? "")
    }

    /// 出力の最初の版番号（`2.1.220 (Claude Code)`・`codex-cli 0.144.6` → `2.1.220`・`0.144.6`）。
    static func parse(_ output: String) -> String? {
        guard let range = output.range(of: #"\d+(\.\d+)+[0-9A-Za-z.\-]*"#, options: .regularExpression) else { return nil }
        return String(output[range])
    }
}
