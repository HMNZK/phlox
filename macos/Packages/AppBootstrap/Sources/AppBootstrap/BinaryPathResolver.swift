import Foundation
import AgentDomain

/// CLI バイナリ一括解決の結果。claude が見つからない場合は `claudeBinaryPath` が nil。
public struct ResolvedCLIBinaries: Sendable {
    public let claudeBinaryPath: String?
    public let pathEnvironment: String
    public let agentBinaryPaths: [AgentKind: String]

    public init(
        claudeBinaryPath: String?,
        pathEnvironment: String,
        agentBinaryPaths: [AgentKind: String]
    ) {
        self.claudeBinaryPath = claudeBinaryPath
        self.pathEnvironment = pathEnvironment
        self.agentBinaryPaths = agentBinaryPaths
    }
}

/// 子プロセスへ渡す PATH と CLI バイナリの絶対パスを解決するユーティリティ。
public enum BinaryPathResolver {
    /// login shell が利用できない場合に走査する典型的な候補ディレクトリ。
    static func candidatePathDirectories(home: String) -> [String] {
        [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    /// login shell の `$PATH` を取得する。失敗時は典型的な候補ディレクトリを `:` 連結して返す。
    public static func resolvePathEnvironment() -> String {
        if let path = resolvePathViaLoginShell(), !path.isEmpty {
            return path
        }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return candidatePathDirectories(home: home).joined(separator: ":")
    }

    /// `/bin/zsh -l -c` の login shell から PATH を取得する。
    private static func resolvePathViaLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        guard let path = runAndReadStdout(process)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }
        return path
    }

    /// Process を起動し stdout を全読み取りして返す。
    /// **stdout を `waitUntilExit()` より前に読み切る**ことで、子が stdout パイプ（既定 64KB）を
    /// 超えて書き込むと親が待ちに入り子が書き込みでブロックする Process+Pipe デッドロックを回避する。
    /// stderr は使わないので `nullDevice` へ捨てる（Pipe を未ドレインで残すと stderr 側で同じ
    /// デッドロックが起きうるため）。
    static func runAndReadStdout(_ process: Process) -> String? {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // wait より前に EOF まで読み切る（パイプが満杯でブロックしない）。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// claude（必須）と組込 CLI のバイナリを一括解決する。
    /// 重い login shell の起動は PATH 取得の 1 回だけで、各バイナリは取得済み PATH の走査で解決する。
    /// メインスレッドをブロックしないよう、呼び出し側はメインアクター外（Task.detached 等）で実行すること。
    public static func resolveCLIBinaries() -> ResolvedCLIBinaries {
        let pathEnv = resolvePathEnvironment()
        if let overrides = testBinaryOverrides(environment: ProcessInfo.processInfo.environment) {
            return ResolvedCLIBinaries(
                claudeBinaryPath: overrides[.claudeCode],
                pathEnvironment: pathEnv,
                agentBinaryPaths: overrides.filter { $0.key != .claudeCode }
            )
        }

        let claudePath = resolveBinary(AgentKind.claudeCode.binaryName, pathEnv: pathEnv)

        var agentBinaryPaths: [AgentKind: String] = [:]
        for kind in AgentRegistry.optionalBinaryKinds {
            if let path = resolveBinary(kind.binaryName, pathEnv: pathEnv) {
                agentBinaryPaths[kind] = path
            }
        }

        return ResolvedCLIBinaries(
            claudeBinaryPath: claudePath,
            pathEnvironment: pathEnv,
            agentBinaryPaths: agentBinaryPaths
        )
    }

    static func testBinaryOverrides(environment: [String: String]) -> [AgentKind: String]? {
        guard environment["PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN"] == "1",
              let raw = environment["PHLOX_TEST_AGENT_BINARY_PATHS"] else { return nil }
        guard let data = raw.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: AgentKind.allCases.compactMap { kind in
            guard let path = paths[kind.rawValue], FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return (kind, path)
        })
    }

    /// 任意のバイナリ名から絶対パスを解決する（`pathEnv` を `:` 分割して先頭から走査）。
    /// login shell はここでは起動しない（PATH 取得の 1 回に限定するため）。
    public static func resolveBinary(_ name: String, pathEnv: String) -> String? {
        let fm = FileManager.default
        for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
            let binary = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: binary) {
                return binary
            }
        }
        return nil
    }
}
