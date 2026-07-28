import Foundation
import Testing
@testable import AgentConfigKit

private func decode(_ json: String) throws -> JSONValue {
    try JSONValueCoder.decode(Data(json.utf8))
}

@Test("statusLine を読み書きし、未知キーは残す")
func statusLine_roundTripsPreservingUnknownKeys() throws {
    let root = try decode(#"{"statusLine":{"type":"command","command":"~/bin/line.sh","padding":0,"custom":true}}"#)
    var settings = ClaudeStatusLineSettings.extract(from: root)
    #expect(settings.isEnabled)
    #expect(settings.command == "~/bin/line.sh")
    #expect(settings.padding == 0)

    settings.command = "~/bin/other.sh"
    settings.padding = 2
    let updated = settings.apply(to: root)
    #expect(updated["statusLine"]?["command"]?.stringValue == "~/bin/other.sh")
    #expect(updated["statusLine"]?["padding"]?.intValue == 2)
    #expect(updated["statusLine"]?["custom"]?.boolValue == true)
}

@Test("statusLine を無効にするとキーごと消える")
func statusLine_removesKeyWhenDisabled() throws {
    let root = try decode(#"{"model":"sonnet","statusLine":{"type":"command","command":"a.sh"}}"#)
    var settings = ClaudeStatusLineSettings.extract(from: root)
    settings.isEnabled = false
    let updated = settings.apply(to: root)
    #expect(updated["statusLine"] == nil)
    #expect(updated["model"]?.stringValue == "sonnet")
}

@Test("コマンド未入力なら有効にしても書き込まない")
func statusLine_ignoresBlankCommand() throws {
    let root = try decode("{}")
    let settings = ClaudeStatusLineSettings(isEnabled: true, command: "   ")
    #expect(settings.apply(to: root)["statusLine"] == nil)
}

@Test("outputStyle の設定と解除")
func outputStyle_applyAndClear() throws {
    let root = try decode(#"{"model":"sonnet"}"#)
    let set = ClaudeOutputStyleSettings.apply("Explanatory", to: root)
    #expect(ClaudeOutputStyleSettings.extract(from: set) == "Explanatory")

    let cleared = ClaudeOutputStyleSettings.apply(nil, to: set)
    #expect(cleared["outputStyle"] == nil)
    #expect(cleared["model"]?.stringValue == "sonnet")
}

@Test("output-styles ディレクトリの .md がカスタム候補として並ぶ")
func outputStyle_listsCustomStyles() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-output-styles-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let stylesDirectory = home
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("output-styles", isDirectory: true)
    try FileManager.default.createDirectory(at: stylesDirectory, withIntermediateDirectories: true)
    try Data("# hi".utf8).write(to: stylesDirectory.appendingPathComponent("Terse.md"))
    try Data("noise".utf8).write(to: stylesDirectory.appendingPathComponent("README.txt"))

    let options = ClaudeOutputStyleSettings.availableOptions(paths: ClaudeConfigPaths(homeDirectory: home))
    #expect(options.contains { $0.value == "Terse" })
    #expect(options.contains { $0.value == nil })          // 既定
    #expect(options.contains { $0.value == "Explanatory" }) // 組み込み
    #expect(options.contains { $0.displayName == "README.txt" } == false)
}
