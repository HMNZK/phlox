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

    @Test("実アプリ環境の継承・空文字・明示override優先を別プロセスで検査する")
    func runtimeEnvironmentPrecedence() async throws {
        let environment = ProcessInfo.processInfo.environment
        if let childRoot = environment["PHLOX_MODEL_PROBE_CHILD_ROOT"] {
            let fixture = try ModelDirectoryFixture(existingRoot: URL(fileURLWithPath: childRoot))
            let mode = try #require(environment["PHLOX_MODEL_PROBE_CHILD_MODE"])
            let appRoot = URL(fileURLWithPath: try #require(environment["PHLOX_DATA_DIR"]))
            let explicitRoot = fixture.root.appendingPathComponent("provider-B")
            let provider = fixture.provider(dataRoot: mode == "explicit" ? explicitRoot : nil, emptyOverride: mode == "empty")
            for kind in [AgentKind.claudeCode, .cursor, .codex] {
                #expect(try await !provider.fetchModels(for: kind).isEmpty)
            }
            let records = try fixture.records()
            #expect(records.count == 8)
            let expected = (mode == "explicit" ? explicitRoot : appRoot)
                .appendingPathComponent("model-catalog").resolvingSymlinksInPath().path
            for record in records { #expect(record.first == expected) }
            return
        }

        // SwiftPMが実際に使ったヘルパーを再利用し、ビルドロックを取らずにテストを別プロセスで実行する。
        let bundleFlag = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
        let testBundle = CommandLine.arguments[bundleFlag + 1]
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for mode in ["inherit", "empty", "explicit"] {
            let fixture = try ModelDirectoryFixture()
            defer { fixture.remove() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--test-bundle-path", testBundle, "--package-path", package.path,
                "--filter", "AcceptanceModelWorkingDirectoryTests.runtimeEnvironmentPrecedence",
                testBundle, "--testing-library", "swift-testing"]
            var childEnvironment = environment
            childEnvironment["PHLOX_DATA_DIR"] = fixture.root.appendingPathComponent("application-A").path
            childEnvironment["PHLOX_MODEL_PROBE_CHILD_ROOT"] = fixture.root.path
            childEnvironment["PHLOX_MODEL_PROBE_CHILD_MODE"] = mode
            process.environment = childEnvironment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(mode)の隔離プロセス検査:\n\(log)")
        }
    }

    @Test("alias途中でcwdが使えなくても誤起動せず取得済み一覧を保持する")
    func invalidDirectoryDuringAliasesDoesNotStartAliases() async throws {
        let fixture = try ModelDirectoryFixture()
        defer { fixture.remove() }
        let provider = fixture.provider(dataRoot: fixture.root.appendingPathComponent("data"), blockAliases: true)

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models == AgentModelCatalog.builtinModels(for: .claudeCode), "表示名取得失敗時は既存の一覧維持を守る")
        let records = try fixture.records()
        #expect(records.count == 1, "専用cwdが通常ファイルになった後はaliasのCLIを起動しない")
        #expect(records.first.map { Array($0.dropFirst()) } == ["--bare", "-p", "/model", "--output-format", "json"])
    }
}

private struct ModelDirectoryFixture {
    let root: URL
    let executable: URL
    let logs: URL

    init(existingRoot: URL? = nil) throws {
        root = existingRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("phlox-model-cwd-" + UUID().uuidString)
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
            if [ "${PHLOX_MODEL_PROBE_BLOCK_ALIAS:-0}" = 1 ] && [ "$2" = -p ]; then
              mkdir -p "$PHLOX_DATA_DIR"
              if [ -d "$PHLOX_DATA_DIR/model-catalog" ]; then
                rmdir "$PHLOX_DATA_DIR/model-catalog"
              fi
              printf '%s' blocked > "$PHLOX_DATA_DIR/model-catalog"
            fi
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

    func provider(dataRoot: URL?, emptyOverride: Bool = false, blockAliases: Bool = false) -> LiveAgentModelProvider {
        var environment = ["PATH": "/usr/bin:/bin", "PHLOX_MODEL_PROBE_LOG": logs.path]
        if let dataRoot { environment["PHLOX_DATA_DIR"] = dataRoot.path }
        else if emptyOverride { environment["PHLOX_DATA_DIR"] = "" }
        if blockAliases { environment["PHLOX_MODEL_PROBE_BLOCK_ALIAS"] = "1" }
        return LiveAgentModelProvider(
            environment: environment,
            commands: [.claudeCode: executable.path, .cursor: executable.path, .codex: executable.path],
            timeout: 3
        )
    }

    func records() throws -> [[String]] {
        try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
            .map {
                var record = try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init)
                // pwd -Pと期待値で、/private/varと/varなど同じ場所の表記を揃える。
                if let directory = record.first {
                    record[0] = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
                }
                return record
            }
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("テスト所有の一時フォルダ削除失敗: \(error)") }
    }
}
