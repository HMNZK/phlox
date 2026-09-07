import AgentDomain
import Foundation
import Testing
@testable import ControlServer

@Suite("モデル部分一覧の保持")
struct ModelPartialCatalogRecoveryTests {
    @Test("fableだけ取得した後に作業フォルダが壊れても一覧を増やさずaliasを起動しない")
    func preservesPartialCatalogWhenAliasDirectoryPreparationFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-partial-model-" + UUID().uuidString)
        let data = root.appendingPathComponent("data")
        let logs = root.appendingPathComponent("logs")
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record("テスト所有フォルダの削除失敗: \(error)") }
        }
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("claude-probe")
        // 実Processで一覧を返した直後、alias照会に必要な場所を通常ファイルへ置き換える。
        let script = #"""
        #!/bin/sh
        set -eu
        printf '%s\000' "$(pwd -P)" "$@" > "$PHLOX_PARTIAL_MODEL_LOG/$$"
        [ "$1" = --bare ] && [ "$2" = -p ] || exit 23
        if [ -d "$PHLOX_DATA_DIR/model-catalog" ]; then
          rmdir "$PHLOX_DATA_DIR/model-catalog"
        fi
        printf '%s' blocked > "$PHLOX_DATA_DIR/model-catalog"
        printf '%s\n' '{"result":"Current model: Probe\nUsage: /model <name>. Available: fable, or a full model ID."}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin", "PHLOX_DATA_DIR": data.path,
                          "PHLOX_PARTIAL_MODEL_LOG": logs.path],
            commands: [.claudeCode: executable.path],
            timeout: 3
        )
        let originalDirectory = FileManager.default.currentDirectoryPath

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models.map(\.id) == ["fable"], "取得していない内蔵モデルを追加しない")
        let fallback = try #require(AgentModelCatalog.builtinModels(for: .claudeCode).first { $0.id == "fable" })
        #expect(models == [fallback], "表示名照会だけの失敗では取得済みの選択肢を保持する")
        #expect(FileManager.default.currentDirectoryPath == originalDirectory)
        let directory = data.appendingPathComponent("model-catalog")
        #expect(try directory.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
        let records = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
        #expect(records.count == 1, "フォルダ準備失敗後のalias照会は実Processを起動しない")
        let fields = try String(contentsOf: #require(records.first), encoding: .utf8)
            .split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        #expect(fields.last == "", "記録末尾のNUL区切りを確認する")
        let record = Array(fields.dropLast())
        let actualDirectory = URL(fileURLWithPath: try #require(record.first)).resolvingSymlinksInPath().path
        #expect(actualDirectory == directory.resolvingSymlinksInPath().path)
        #expect(Array(record.dropFirst()) == ["--bare", "-p", "/model", "--output-format", "json"])
    }
}
