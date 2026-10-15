import Testing
@testable import DashboardFeature

@Suite("ユーザー用端末の起動環境")
struct TerminalEnvironmentTests {
    @Test("GUI 起動で LANG が無くても UTF-8 を渡す")
    func defaultLanguage() {
        let environment = TerminalEnvironment.userShell(home: "/Users/test", path: "/usr/bin:/bin", appEnvironment: [:])
        #expect(environment == [
            "HOME": "/Users/test", "PATH": "/usr/bin:/bin",
            "TERM": "xterm-256color", "LANG": "en_US.UTF-8",
        ])
    }

    @Test("アプリ環境の LANG を優先する", arguments: ["ja_JP.UTF-8", "C", ""])
    func inheritedLanguage(language: String) {
        let environment = TerminalEnvironment.userShell(
            home: "/Users/test", path: "/usr/bin:/bin", appEnvironment: ["LANG": language]
        )
        #expect(environment["LANG"] == language)
    }
}
