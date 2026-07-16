import Foundation
import Testing
@testable import DashboardFeature

private let userHooksDispatcher = "/tmp/phlox-user-hooks-dispatcher.sh"

@Test func codexUserHooks_installCreatesDeterministicUserHooks() throws {
    let fm = FileManager.default
    let codexHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fm.removeItem(at: codexHome) }

    let url = try CodexUserHooksManager.install(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    )

    #expect(url == CodexUserHooksManager.hooksFileURL(codexHome: codexHome))
    #expect(CodexUserHooksManager.status(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    ) == .installed)

    let firstWrite = try Data(contentsOf: url)
    _ = try CodexUserHooksManager.install(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    )
    let secondWrite = try Data(contentsOf: url)
    #expect(firstWrite == secondWrite)

    let json = try JSONSerialization.jsonObject(with: secondWrite) as? [String: Any]
    let hooks = try #require(json?["hooks"] as? [String: Any])
    let expected: [(String, String)] = [
        ("Stop", "stop"),
        ("PreToolUse", "preToolUse"),
        ("PostToolUse", "postToolUse"),
        ("UserPromptSubmit", "userPromptSubmit"),
    ]
    for (event, kind) in expected {
        let groups = try #require(hooks[event] as? [[String: Any]])
        #expect(groups.count == 1)
        let handlers = try #require(groups.first?["hooks"] as? [[String: Any]])
        #expect(handlers.first?["command"] as? String == "'\(userHooksDispatcher)' \(kind)")
    }
}

@Test func codexUserHooks_preservesUserHooksAndRemovesOnlyPhloxHooks() throws {
    let fm = FileManager.default
    let codexHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: codexHome) }

    let url = CodexUserHooksManager.hooksFileURL(codexHome: codexHome)
    let existing = """
    {
      "hooks": {
        "Stop": [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": "/usr/bin/true" }
            ]
          }
        ]
      },
      "other": true
    }
    """
    try Data(existing.utf8).write(to: url)

    try CodexUserHooksManager.install(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    )
    #expect(CodexUserHooksManager.status(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    ) == .installed)

    let removed = try CodexUserHooksManager.remove(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    )
    #expect(removed)
    #expect(CodexUserHooksManager.status(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    ) == .notInstalled)

    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["other"] as? Bool == true)
    let hooks = try #require(json?["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
    let handlers = try #require(stopEntries.first?["hooks"] as? [[String: Any]])
    #expect(handlers.first?["command"] as? String == "/usr/bin/true")
    #expect(hooks["PreToolUse"] == nil)
}

@Test func codexUserHooks_reportsInvalidHooksJSON() throws {
    let fm = FileManager.default
    let codexHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: codexHome) }

    let url = CodexUserHooksManager.hooksFileURL(codexHome: codexHome)
    try Data("{".utf8).write(to: url)

    #expect(CodexUserHooksManager.status(
        dispatcherPath: userHooksDispatcher,
        codexHome: codexHome,
        fileManager: fm
    ) == .invalid)
    #expect(throws: CodexUserHooksManagerError.self) {
        try CodexUserHooksManager.install(
            dispatcherPath: userHooksDispatcher,
            codexHome: codexHome,
            fileManager: fm
        )
    }
}
