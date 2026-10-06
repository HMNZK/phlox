import Foundation
import Testing
import AppBootstrap

@Suite struct ClaudeSettingsGeneratorTests {
    private func makeSettings(
        defaultMode: String = "bypassPermissions",
        dispatcher: String = "/repo/scripts/hook-dispatcher.sh",
        statusLineCommand: String = "/bin/sh '/wrapper.sh'"
    ) -> [String: Any] {
        ClaudeSettingsGenerator.settings(
            defaultMode: defaultMode,
            dispatcher: dispatcher,
            statusLineCommand: statusLineCommand
        )
    }

    @Test func containsAllSixHookEventsWithDispatcherCommand() throws {
        let dispatcher = "/repo/scripts/hook-dispatcher.sh"
        let settings = makeSettings(dispatcher: dispatcher)

        let hooks = try #require(settings["hooks"] as? [String: [[String: Any]]])
        let expectedEvents: [String: String] = [
            "SessionStart": "sessionStart",
            "Notification": "notification",
            "Stop": "stop",
            "PreToolUse": "preToolUse",
            "PostToolUse": "postToolUse",
            "UserPromptSubmit": "userPromptSubmit",
        ]
        #expect(Set(hooks.keys) == Set(expectedEvents.keys))
        for (event, argument) in expectedEvents {
            let entries = try #require(hooks[event])
            let entry = try #require(entries.first)
            #expect(entry["matcher"] as? String == "")
            let inner = try #require((entry["hooks"] as? [[String: Any]])?.first)
            #expect(inner["type"] as? String == "command")
            #expect(inner["command"] as? String == "'\(dispatcher)' \(argument)")
            if event == "PreToolUse" {
                #expect(inner["timeout"] as? Int == 600)
            } else {
                #expect(inner["timeout"] == nil)
            }
        }
    }

    @Test func permissionsCarryGivenDefaultMode() throws {
        let settings = makeSettings(defaultMode: "default")

        let permissions = try #require(settings["permissions"] as? [String: String])
        #expect(permissions == ["defaultMode": "default"])
    }

    @Test func statusLineUsesGivenCommand() throws {
        let settings = makeSettings(statusLineCommand: "/bin/sh '/path/wrapper.sh'")

        let statusLine = try #require(settings["statusLine"] as? [String: String])
        #expect(statusLine == ["type": "command", "command": "/bin/sh '/path/wrapper.sh'"])
    }

    @Test func settingsSerializeToValidJSON() throws {
        let settings = makeSettings()

        #expect(JSONSerialization.isValidJSONObject(settings))
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        #expect(!data.isEmpty)
    }

    /// dispatcher のパスにシングルクォートが含まれても、クォートを閉じずに連結する形でエスケープする。
    @Test func settingsEscapesSingleQuotesInDispatcherPath() throws {
        let dispatcher = "/Users/x/it's a/dir/hook-dispatcher.sh"
        let settings = makeSettings(dispatcher: dispatcher, statusLineCommand: "sl")
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let matchers = try #require(hooks["SessionStart"] as? [[String: Any]])
        let inner = try #require(matchers.first?["hooks"] as? [[String: Any]])
        let command = try #require(inner.first?["command"] as? String)

        #expect(command == "\(ShellQuoting.singleQuoted(dispatcher)) sessionStart")
        #expect(command.contains("'\\''"))
        #expect(!command.contains("'it's a'"))
    }
}
