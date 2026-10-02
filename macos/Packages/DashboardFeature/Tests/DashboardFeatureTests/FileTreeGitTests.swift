import Foundation
import Testing
@testable import DashboardFeature

@Suite("ファイルツリーのブランチ表示")
@MainActor
struct FileTreeGitTests {
    @Test("ブランチ名と detached HEAD の短縮コミット名を表示する")
    func branchLabels() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        func git(_ arguments: String...) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "-c", "core.hooksPath=/dev/null",
                                 "-c", "commit.gpgsign=false", "-c", "user.name=phlox-test",
                                 "-c", "user.email=test@phlox.local"] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            try #require(process.terminationStatus == 0, "Git 検証コマンド失敗: \(text)")
            return text
        }
        _ = try git("init", "-q", "-b", "topic")
        _ = try git("commit", "-q", "--allow-empty", "-m", "検証用の初期コミット")
        let model = FileTreeModel(root: root.path)
        await model.refresh()
        #expect(model.branch == "topic")
        let shortHead = try git("rev-parse", "--short", "HEAD")
        _ = try git("checkout", "-q", "--detach")
        await model.refresh()
        #expect(model.branch == "detached HEAD \(shortHead)")
    }
}
