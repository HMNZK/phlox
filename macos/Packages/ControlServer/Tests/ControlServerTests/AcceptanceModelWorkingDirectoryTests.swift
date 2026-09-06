import AgentDomain
import Foundation
import Testing
@testable import ControlServer

@Suite("モデル取得プロセスの作業フォルダ", .serialized)
struct AcceptanceModelWorkingDirectoryTests {
    @Test("実CLI境界の全モデル取得は専用フォルダで実行する", arguments: [AgentKind.claudeCode, .cursor, .codex])
    func modelProcessesUseIsolatedDirectory(kind: AgentKind) async throws {
        let fixture = try ModelDirectoryFixture()
        defer { fixture.remove() }
        let originalDirectory = FileManager.default.currentDirectoryPath
        let provider = fixture.provider(dataRoot: fixture.root.appendingPathComponent("分離 データ"))

        let models = try await provider.fetchModels(for: kind)

        #expect(!models.isEmpty)
        #expect(FileManager.default.currentDirectoryPath == originalDirectory)
        let records = try fixture.records()
        #expect(records.count == (kind == .claudeCode ? 6 : 1))
        let expected = fixture.root.appendingPathComponent("分離 データ/model-catalog").resolvingSymlinksInPath().path
        for record in records {
            #expect(record.first == expected, "呼出元cwdでなくPHLOX_DATA_DIR配下のモデル専用ディレクトリを使う")
        }
        let arguments = records.map { Array($0.dropFirst()) }
        switch kind {
        case .claudeCode:
            let expectedArguments = [["--bare", "-p", "/model", "--output-format", "json"]]
                + ["default", "opus[1m]", "fable", "sonnet", "haiku"].map {
                    ["--bare", "--model", $0, "-p", "/model", "--output-format", "json"]
                }
            #expect(Set(arguments) == Set(expectedArguments))
        case .cursor:
            #expect(arguments == [["models"]])
        case .codex:
            #expect(arguments == [["app-server"]])
            #expect(models.map(\.id) == ["probe-codex"])
        }
    }

    @Test("専用ディレクトリを準備できない場合はCLIを起動しない", arguments: [AgentKind.claudeCode, .cursor, .codex])
    func invalidDirectoryDoesNotStartProcess(kind: AgentKind) async throws {
        let fixture = try ModelDirectoryFixture()
        defer { fixture.remove() }
        let notDirectory = fixture.root.appendingPathComponent("regular-file")
        try Data("not a directory".utf8).write(to: notDirectory)
        let provider = fixture.provider(dataRoot: notDirectory)
        var failed = false

        do { _ = try await provider.fetchModels(for: kind) }
        catch { failed = true }

        #expect(failed, "フォルダ準備失敗を既存の取得失敗として返す")
        #expect(try fixture.records().isEmpty, "失敗後にcwd未指定で実行するフォールバックは禁止")
    }
}

private struct ModelDirectoryFixture {
    let root: URL
    let executable: URL
    let logs: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-model-cwd-" + UUID().uuidString)
        logs = root.appendingPathComponent("logs")
        executable = root.appendingPathComponent("model-probe")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let script = #"""
        #!/bin/sh
        set -eu
        {
          pwd -P
          printf '%s\n' "$@"
        } > "$PHLOX_MODEL_PROBE_LOG/$$"
        case "$1" in
          --bare)
            printf '%s\n' '{"result":"Current model: Probe\nUsage: /model <name>. Available: default, opus[1m], fable, sonnet, haiku, or a full model ID."}'
            ;;
          models)
            printf '%s\n' 'Available models' 'auto - Auto'
            ;;
          app-server)
            while IFS= read -r request; do
              case "$request" in
                *'"method":"model/list"'*)
                  printf '%s\n' '{"id":2,"result":{"data":[{"id":"probe-codex"}]}}'
                  exit 0
                  ;;
              esac
            done
            exit 1
            ;;
          *) exit 2 ;;
        esac
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func provider(dataRoot: URL) -> LiveAgentModelProvider {
        LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin", "PHLOX_DATA_DIR": dataRoot.path, "PHLOX_MODEL_PROBE_LOG": logs.path],
            commands: [.claudeCode: executable.path, .cursor: executable.path, .codex: executable.path],
            timeout: 3
        )
    }

    func records() throws -> [[String]] {
        try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("テスト所有の一時フォルダ削除失敗: \(error)") }
    }
}
