import Foundation
import Testing
@testable import DashboardFeature

@Suite("Editor panel VM white-box (task-4)")
@MainActor
struct EditorPanelVMWhiteboxTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-whitebox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-c", "user.name=phlox-test",
            "-c", "user.email=test@phlox.local",
            "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null",
        ] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        try #require(process.terminationStatus == 0)
        return data
    }

    private func repository() throws -> URL {
        let root = try temporaryDirectory()
        try git(["init", "-q"], in: root)
        try "base\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try git(["add", "note.txt"], in: root)
        try git(["commit", "-q", "-m", "base"], in: root)
        try "on-disk\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("読み込み内容へ戻した draft は未保存扱いを解除する")
    func revertingDraftToLoadedContentClearsDirtyState() async throws {
        let root = try repository()
        let viewModel = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await viewModel.refresh()
        await viewModel.select("note.txt")

        viewModel.draft = "user edit\n"
        #expect(viewModel.isDirty)

        viewModel.draft = "on-disk\n"
        #expect(!viewModel.isDirty)
    }

    @Test("非 UTF-8 の未追跡ファイルを選んでも公開状態は安全な空状態になる")
    func selectingNonUTF8FileLeavesSafeEmptyDetail() async throws {
        let root = try repository()
        try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("invalid.txt"))
        let viewModel = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await viewModel.refresh()

        await viewModel.select("invalid.txt")

        #expect(viewModel.selectedPath == nil)
        #expect(viewModel.detail == .none)
        #expect(viewModel.draft.isEmpty)
        #expect(!viewModel.isDirty)
    }

    @Test("削除済みの追跡ファイルは diff を表示したまま編集不可になる")
    func selectingDeletedTrackedFileKeepsDiffVisibleAndReadOnly() async throws {
        let root = try repository()
        try FileManager.default.removeItem(at: root.appendingPathComponent("note.txt"))
        let viewModel = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await viewModel.refresh()

        await viewModel.select("note.txt")

        #expect(viewModel.selectedPath == "note.txt")
        guard case .diff(let diff) = viewModel.detail else {
            Issue.record("削除済みの追跡ファイルの detail は diff であるべき")
            return
        }
        #expect(diff.contains("-base"))
        #expect(viewModel.draft.isEmpty)
        #expect(!viewModel.canEdit)
        #expect(!viewModel.isDirty)
        #expect(viewModel.readOnlyMessage != nil)
    }

    @Test("非 UTF-8 の追跡ファイルは diff を表示したまま編集不可になる")
    func selectingNonUTF8TrackedFileKeepsDiffVisibleAndReadOnly() async throws {
        let root = try temporaryDirectory()
        try git(["init", "-q"], in: root)
        let fileURL = root.appendingPathComponent("shift-jis.txt")
        try Data([0x82, 0xA0]).write(to: fileURL)
        try git(["add", "shift-jis.txt"], in: root)
        try git(["commit", "-q", "-m", "base"], in: root)
        try Data([0x82, 0xA2]).write(to: fileURL)

        let viewModel = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await viewModel.refresh()
        await viewModel.select("shift-jis.txt")

        #expect(viewModel.selectedPath == "shift-jis.txt")
        guard case .diff(let diff) = viewModel.detail else {
            Issue.record("非 UTF-8 の追跡ファイルの detail は diff であるべき")
            return
        }
        #expect(!diff.isEmpty)
        #expect(viewModel.draft.isEmpty)
        #expect(!viewModel.canEdit)
        #expect(!viewModel.isDirty)
        #expect(viewModel.readOnlyMessage != nil)
    }
}
