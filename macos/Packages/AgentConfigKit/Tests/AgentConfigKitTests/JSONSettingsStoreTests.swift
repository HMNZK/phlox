import Foundation
import Testing
@testable import AgentConfigKit

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-config-kit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("知らないキーを持つ settings.json を編集しても、他のキーは残る")
func settingsStore_preservesUnknownKeys() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")

    let original = """
    {
      "model": "opusplan",
      "cleanupPeriodDays": 30,
      "env": { "FOO": "bar" },
      "permissions": { "allow": ["Bash(git status)"], "defaultMode": "acceptEdits" }
    }
    """
    try Data(original.utf8).write(to: file)

    let store = JSONSettingsStore(fileURL: file)
    try store.update(key: "outputStyle", to: .string("Explanatory"))

    let reloaded = try store.load()
    #expect(reloaded["model"]?.stringValue == "opusplan")
    #expect(reloaded["cleanupPeriodDays"]?.intValue == 30)
    #expect(reloaded["env"]?["FOO"]?.stringValue == "bar")
    #expect(reloaded["permissions"]?["defaultMode"]?.stringValue == "acceptEdits")
    #expect(reloaded["outputStyle"]?.stringValue == "Explanatory")
}

@Test("設定ファイルが無い状態でも、書き込みでディレクトリごと作られる")
func settingsStore_createsFileAndDirectory() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("settings.json")

    let store = JSONSettingsStore(fileURL: file)
    #expect(store.exists == false)
    #expect(try store.load() == .object([:]))

    try store.update(key: "model", to: .string("sonnet"))

    #expect(store.exists)
    #expect(try store.load()["model"]?.stringValue == "sonnet")
}

@Test("値に nil を渡すとそのキーだけ消える")
func settingsStore_removesKeyWhenValueIsNil() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data(#"{"model":"sonnet","theme":"dark"}"#.utf8).write(to: file)

    let store = JSONSettingsStore(fileURL: file)
    try store.update(key: "model", to: nil)

    let reloaded = try store.load()
    #expect(reloaded["model"] == nil)
    #expect(reloaded["theme"]?.stringValue == "dark")
}

@Test("壊れた JSON は例外にする（黙って上書きしない）")
func settingsStore_throwsOnBrokenJSON() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data("{ this is not json".utf8).write(to: file)

    let store = JSONSettingsStore(fileURL: file)
    #expect(throws: (any Error).self) { try store.load() }
}
