import Foundation
import Testing
@testable import TerminalUI

/// dumpForDebug が注入された出力先へ dump ファイルを書き出すことの検証。
/// 書き込みはバックグラウンドで完了するため、ファイル出現をポーリングで待つ。
@MainActor
@Suite struct TerminalCoordinatorDumpForDebugTests {
    @Test func dumpForDebug_writesDumpFileIntoInjectedDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumpForDebugTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("hello".utf8))

        coordinator.dumpForDebug(
            sessionLabel: "abc123",
            label: "T1",
            ptyWinsize: (cols: 80, rows: 24),
            outputDirectory: directory
        )

        let file = directory.appendingPathComponent("terminal-dump-abc123-T1.txt")
        var waited = 0
        while !FileManager.default.fileExists(atPath: file.path), waited < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        let body = try String(contentsOf: file, encoding: .utf8)
        #expect(body.contains("# label=T1"))
        #expect(body.contains("ptyCols=80 ptyRows=24"))
        #expect(body.contains("'h'"))
    }
}
