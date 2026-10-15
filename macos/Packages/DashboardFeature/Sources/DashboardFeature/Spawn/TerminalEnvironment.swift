import Foundation

/// ユーザー用端末とエージェント用端末の文字コードの決まり。
public enum TerminalEnvironment {
    static func language(from appEnvironment: [String: String]) -> String {
        appEnvironment["LANG"] ?? "en_US.UTF-8"
    }

    public static func userShell(
        home: String,
        path: String,
        appEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        [
            "HOME": home,
            "PATH": path,
            "TERM": "xterm-256color",
            "LANG": language(from: appEnvironment),
        ]
    }
}
