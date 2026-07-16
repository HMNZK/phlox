import Foundation
import Testing
@testable import DashboardFeature

private let testDispatcher = "/tmp/agent-dashboard-test-dispatcher.sh"

@Test func hookCommand_isDispatcherPlusKindWithoutEnvPrefix() {
    let command = CodexHooksManager.hookCommand(
        dispatcherPath: testDispatcher,
        kind: "preToolUse"
    )

    #expect(command == "'\(testDispatcher)' preToolUse")
    #expect(!command.contains("PHLOX_SESSION_ID="))
    #expect(!command.contains("CLAUDE_HOOKS_URL="))
}

@Test func hooksSettings_allEventCommandsAreSessionIndependent() throws {
    let settings = CodexHooksManager.hooksSettings(dispatcherPath: testDispatcher)

    let hooks = try #require(settings["hooks"] as? [String: Any])
    let expectedEvents = ["Stop", "PreToolUse", "PostToolUse", "UserPromptSubmit"]
    #expect(Set(hooks.keys) == Set(expectedEvents))
    #expect(hooks["Notification"] == nil)

    for event in expectedEvents {
        let entries = try #require(hooks[event] as? [[String: Any]])
        let inner = try #require(entries.first?["hooks"] as? [[String: Any]])
        let command = try #require(inner.first?["command"] as? String)
        #expect(command.contains(testDispatcher))
        #expect(!command.contains("PHLOX_SESSION_ID="))
        #expect(!command.contains("CLAUDE_HOOKS_URL="))
    }
}

@Test func install_writesHooksJSON_andCleanup_removesGeneratedFile() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let result = try CodexHooksManager.install(
        workingDirectory: root,
        dispatcherPath: testDispatcher,
        fileManager: fm
    )

    // 新ファイルの場合は .installed が返る
    guard case .installed(let installation) = result else {
        Issue.record("新規ディレクトリへの install は .installed を返すべき"); return
    }

    #expect(fm.fileExists(atPath: installation.hooksFileURL.path))

    let data = try Data(contentsOf: installation.hooksFileURL)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let hooks = try #require(json?["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
    let stopHooks = try #require(stopEntries.first?["hooks"] as? [[String: Any]])
    let stopCommand = try #require(stopHooks.first?["command"] as? String)
    #expect(stopCommand == "'\(testDispatcher)' stop")

    try CodexHooksManager.cleanup(installation, fileManager: fm)
    #expect(!fm.fileExists(atPath: installation.hooksFileURL.path))
}

/// ユーザー既存の hooks.json がある場合はスキップし、ファイルを一切変更しない。
@Test func install_skipsExistingUserHooks_andLeavesFileUnchanged() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexDir = root.appendingPathComponent(".codex", isDirectory: true)
    try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let userHooksURL = codexDir.appendingPathComponent("hooks.json")
    let userContent = Data("{\"user\": true}".utf8)
    try userContent.write(to: userHooksURL)

    let result = try CodexHooksManager.install(
        workingDirectory: root,
        dispatcherPath: testDispatcher,
        fileManager: fm
    )

    // ユーザー既存ファイルがある場合は .skippedExistingUserFile を返す
    guard case .skippedExistingUserFile = result else {
        Issue.record("ユーザー既存ファイルがある場合は .skippedExistingUserFile を返すべき"); return
    }

    // ユーザーファイルが変更されていない
    let afterContent = try Data(contentsOf: userHooksURL)
    #expect(afterContent == userContent)

    // バックアップファイルが生成されていない
    let backupURL = codexDir.appendingPathComponent(CodexHooksManager.backupFileName)
    #expect(!fm.fileExists(atPath: backupURL.path))
}
