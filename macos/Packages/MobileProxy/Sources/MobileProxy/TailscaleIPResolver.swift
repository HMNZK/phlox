import Foundation

/// 外部コマンドの実行結果(終了コードと標準出力)。
public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String

    public init(exitCode: Int32, standardOutput: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
    }
}

/// `tailscale ip -4` を実行して Tailscale の IPv4 アドレスを解決する。
/// コマンドが無い / 非 0 終了 / 出力が IPv4 でない場合は nil を返し、
/// 呼び出し側を「全インターフェースへフォールバック」へ倒す。
public struct TailscaleIPResolver: Sendable {
    public enum CommandError: Error, Sendable {
        case launchFailed
    }

    /// 引数列を受け取り CommandResult を返すコマンド実行クロージャ(DI シーム)。
    public typealias Runner = @Sendable ([String]) throws -> CommandResult

    private let runner: Runner

    public init(runner: @escaping Runner = TailscaleIPResolver.defaultRunner) {
        self.runner = runner
    }

    /// Tailscale の IPv4 を解決する。解決不可なら nil。
    public func resolveIPv4() -> String? {
        let result: CommandResult
        do {
            result = try runner(["ip", "-4"])
        } catch {
            return nil
        }

        guard result.exitCode == 0 else {
            return nil
        }

        for line in result.standardOutput.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if Self.isIPv4(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// ドット区切り 4 オクテット(各 0..255)を IPv4 とみなす。
    static func isIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let value = Int(part), value >= 0, value <= 255,
                  part.allSatisfy(\.isNumber)
            else {
                return false
            }
        }
        return true
    }

    /// 実環境での既定 Runner: PATH 上の `tailscale` をいくつかの定番パスから探して実行する。
    public static let defaultRunner: Runner = { arguments in
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw CommandError.launchFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, standardOutput: output)
    }
}
