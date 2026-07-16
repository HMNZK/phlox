import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

private let testDispatcher = "/tmp/agent-dashboard-test-dispatcher.sh"

@Test func cursorHookCommand_isDispatcherPlusKindWithoutEnvPrefix() {
    let command = CursorHooksManager.hookCommand(
        dispatcherPath: testDispatcher,
        kind: "preToolUse"
    )

    #expect(command == "'\(testDispatcher)' preToolUse")
    #expect(!command.contains("PHLOX_SESSION_ID="))
    #expect(!command.contains("CLAUDE_HOOKS_URL="))
}

@Test func cursorHooksSettings_version1_andFourCursorEvents() throws {
    let settings = CursorHooksManager.hooksSettings(dispatcherPath: testDispatcher)

    #expect(settings["version"] as? Int == 1)

    let hooks = try #require(settings["hooks"] as? [String: Any])
    let expectedEvents = [
        "beforeShellExecution",
        "afterShellExecution",
        "beforeSubmitPrompt",
        "stop",
    ]
    #expect(Set(hooks.keys) == Set(expectedEvents))

    let preToolEntries = try #require(hooks["beforeShellExecution"] as? [[String: Any]])
    let preToolCommand = try #require(preToolEntries.first?["command"] as? String)
    #expect(preToolCommand == "'\(testDispatcher)' preToolUse")
    #expect(!preToolCommand.contains("PHLOX_SESSION_ID="))

    let postToolEntries = try #require(hooks["afterShellExecution"] as? [[String: Any]])
    let postToolCommand = try #require(postToolEntries.first?["command"] as? String)
    #expect(postToolCommand == "'\(testDispatcher)' postToolUse")

    let promptEntries = try #require(hooks["beforeSubmitPrompt"] as? [[String: Any]])
    let promptCommand = try #require(promptEntries.first?["command"] as? String)
    #expect(promptCommand == "'\(testDispatcher)' userPromptSubmit")

    let stopEntries = try #require(hooks["stop"] as? [[String: Any]])
    let stopCommand = try #require(stopEntries.first?["command"] as? String)
    #expect(stopCommand == "'\(testDispatcher)' stop")
}

@Test func cursorInstall_writesHooksJSON_andCleanup_removesGeneratedFile() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let result = try CursorHooksManager.install(
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
    #expect(json?["version"] as? Int == 1)
    let hooks = try #require(json?["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["stop"] as? [[String: Any]])
    let stopCommand = try #require(stopEntries.first?["command"] as? String)
    #expect(stopCommand == "'\(testDispatcher)' stop")

    try CursorHooksManager.cleanup(installation, fileManager: fm)
    #expect(!fm.fileExists(atPath: installation.hooksFileURL.path))
}

/// ユーザー既存の hooks.json がある場合はスキップし、ファイルを一切変更しない。
@Test func cursorInstall_skipsExistingUserHooks_andLeavesFileUnchanged() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cursorDir = root.appendingPathComponent(".cursor", isDirectory: true)
    try fm.createDirectory(at: cursorDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let userHooksURL = cursorDir.appendingPathComponent("hooks.json")
    let userContent = Data("{\"user\": true}".utf8)
    try userContent.write(to: userHooksURL)

    let result = try CursorHooksManager.install(
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
    let backupURL = cursorDir.appendingPathComponent(CursorHooksManager.backupFileName)
    #expect(!fm.fileExists(atPath: backupURL.path))
}
