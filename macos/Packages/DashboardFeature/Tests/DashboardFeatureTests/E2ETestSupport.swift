import Foundation

// MARK: - E2E test helpers (shared across Layer A integration tests)

/// PHLOX_E2E=1 のときだけ実 PTY テストを有効化する。
func isE2EEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PHLOX_E2E"] == "1"
}

/// CLI バイナリを PATH と既知の場所から解決する(login shell を経由しない)。
func resolveBinary(_ name: String) -> String? {
    var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        dirs += path.split(separator: ":").map(String.init)
    }
    for dir in dirs {
        let candidate = (dir as NSString).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

/// 子プロセスに渡す最小限の環境変数(PATH に homebrew/ollama を含める)。
func childEnvironment(extra: [String: String] = [:]) -> [String: String] {
    let basePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var env: [String: String] = [
        "PATH": inherited.isEmpty ? basePath : "\(basePath):\(inherited)",
        "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
        "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
        "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
        "TERM": "xterm-256color",
    ]
    for (k, v) in extra { env[k] = v }
    return env
}

/// 一時作業ディレクトリを作る(テスト後の本番データ汚染を避ける)。
func makeTempWorkingDirectory() -> String {
    let dir = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("phlox-e2e-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

@MainActor
func waitUntil(
    timeoutNanoseconds: UInt64,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else { return false }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
    return true
}

/// fake-agent.sh の絶対パスを返す。
func fakeAgentPath() -> String {
    if let url = Bundle.module.url(
        forResource: "fake-agent",
        withExtension: "sh",
        subdirectory: "Fixtures"
    ) {
        return url.path
    }
    let fixturesDir = (#filePath as NSString).deletingLastPathComponent + "/Fixtures"
    return (fixturesDir as NSString).appendingPathComponent("fake-agent.sh")
}
