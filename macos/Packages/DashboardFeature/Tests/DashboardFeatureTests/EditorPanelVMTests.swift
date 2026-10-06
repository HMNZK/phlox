// エディタパネル VM（一覧→選択→表示→編集→保存／競合）。
//
// 保存競合は「警告後にユーザー版で上書き」: save が conflictDetected を返したら UI が警告し、
// ユーザーの確認後に overwrite() で上書きする二段構え。
// 変更パネルも FileTab と同じ 色付け・編集・閲覧 の三段階のサイズ上限を共有する。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Editor panel VM", .timeLimit(.minutes(1)))
@MainActor
struct EditorPanelVMTests {

    // MARK: - fixture harness

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ args: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=phlox-test", "-c", "user.email=test@phlox.local",
                             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        try #require(process.terminationStatus == 0,
                     "git failed: \(String(decoding: data, as: UTF8.self))")
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ content: String, to name: String, in root: URL) throws {
        try content.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// fixture: a.txt（変更あり）・c.txt（未追跡）・bin.dat（未追跡バイナリ）を持つリポジトリ。
    private func makeFixtureRepo() throws -> URL {
        let root = try makeTempDir()
        try git(["init", "-q"], cwd: root)
        try write("old-a\n", to: "a.txt", in: root)
        try git(["add", "."], cwd: root)
        try git(["commit", "-q", "-m", "base"], cwd: root)
        try write("new-a\n", to: "a.txt", in: root)
        try write("hello-c\n", to: "c.txt", in: root)
        try Data([0x00, 0x01, 0xFF]).write(to: root.appendingPathComponent("bin.dat"))
        return root
    }

    // MARK: - 一覧・選択・編集・保存・競合

    @Test("サービス無し（プロジェクト未選択）では noProject の空状態")
    func noServiceMeansNoProject() async throws {
        let vm = EditorPanelViewModel(service: nil)
        await vm.refresh()
        #expect(vm.listState == .noProject)
        #expect(vm.changes.isEmpty)
    }

    @Test("git リポジトリでないプロジェクトでは notARepository")
    func nonRepositoryIsReported() async throws {
        let plain = try makeTempDir()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: plain))
        await vm.refresh()
        #expect(vm.listState == .notARepository)
        #expect(vm.changes.isEmpty)
    }

    @Test("refresh で変更一覧が並ぶ")
    func refreshPopulatesChanges() async throws {
        let root = try makeFixtureRepo()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await vm.refresh()
        #expect(vm.listState == .ready)
        #expect(vm.changes.map(\.path) == ["a.txt", "bin.dat", "c.txt"])
    }

    @Test("追跡ファイルを選ぶと diff が表示され、draft に現内容がロードされる")
    func selectTrackedFileLoadsDiffAndDraft() async throws {
        let root = try makeFixtureRepo()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await vm.refresh()
        await vm.select("a.txt")

        #expect(vm.selectedPath == "a.txt")
        guard case .diff(let text) = vm.detail else {
            Issue.record("a.txt の detail は .diff であるべきだが \(vm.detail) だった")
            return
        }
        #expect(text.contains("+new-a"))
        #expect(vm.draft == "new-a\n")
        #expect(vm.isDirty == false)
    }

    @Test("未追跡テキストは content、バイナリは binary で編集不可")
    func selectUntrackedAndBinary() async throws {
        let root = try makeFixtureRepo()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await vm.refresh()

        await vm.select("c.txt")
        #expect(vm.detail == .content("hello-c\n"))
        #expect(vm.draft == "hello-c\n")

        await vm.select("bin.dat")
        #expect(vm.detail == .binary)
        #expect(vm.draft.isEmpty)
        #expect(vm.isDirty == false)
    }

    @Test("draft の編集で isDirty になり、save で保存されて dirty が解ける")
    func editAndSave() async throws {
        let root = try makeFixtureRepo()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await vm.refresh()
        await vm.select("a.txt")

        vm.draft = "edited-by-user\n"
        #expect(vm.isDirty == true)

        let result = try await vm.save()
        #expect(result == .saved)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(onDisk == "edited-by-user\n")
        #expect(vm.isDirty == false)
    }

    @Test("外部（エージェント）がディスクを変えていたら save は書かずに conflictDetected")
    func saveDetectsExternalChange() async throws {
        let root = try makeFixtureRepo()
        let vm = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await vm.refresh()
        await vm.select("a.txt")
        vm.draft = "mine\n"

        // エージェントによる外部変更をシミュレート。
        try write("agent-wrote-this\n", to: "a.txt", in: root)

        let result = try await vm.save()
        #expect(result == .conflictDetected)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(onDisk == "agent-wrote-this\n")

        // ユーザーが警告を確認して上書きを選んだ。
        try await vm.overwrite()
        let after = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(after == "mine\n")
        #expect(vm.isDirty == false)
    }

    // MARK: - 変更パネルのサイズ上限・読み取り専用・非 UTF-8

    private func makeSingleFileRepo() throws -> URL {
        let root = try makeTempDir()
        try git(["init", "-q"], cwd: root)
        try "base\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try git(["add", "note.txt"], cwd: root)
        try git(["commit", "-q", "-m", "base"], cwd: root)
        try "on-disk\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("読み込み内容へ戻した draft は未保存扱いを解除する")
    func revertingDraftToLoadedContentClearsDirtyState() async throws {
        let root = try makeSingleFileRepo()
        let viewModel = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await viewModel.refresh()
        await viewModel.select("note.txt")

        viewModel.draft = "user edit\n"
        #expect(viewModel.isDirty)

        viewModel.draft = "on-disk\n"
        #expect(!viewModel.isDirty)
    }

    @Test("変更パネルも色付け・編集・閲覧の三段階の上限を共有する", arguments: [1_000_000, 1_000_001,
        5_000_000, 5_000_001, 20_000_000, 20_000_001])
    func sharesFileTabLimits(bytes: Int) async throws {
        let root = try makeSingleFileRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.txt")
        let original = Data([0xef, 0xbb, 0xbf]) + Data(repeating: 65, count: bytes - 3)
        try original.write(to: file)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.select("note.txt")
        #expect(model.selectedPath == "note.txt")
        #expect(model.canEdit == (bytes <= WorkingTreeText.maximumEditableFileSize))
        #expect(model.canViewContent == (bytes <= WorkingTreeText.maximumReadableFileSize))
        guard case .diff = model.detail else { Issue.record("追跡ファイルの変更は差分を表示する"); return }
        #expect(model.syntaxHighlightingEnabled, "差分は本文のサイズ上限と無関係に色付けする")
        #expect(model.shouldHighlightPreview(isDiff: false) == (bytes <= WorkingTreeText.maximumHighlightedFileSize),
                "内容へ切り替えると本文の色付け境界を使う")
        if model.canEdit {
            model.draft = "B" + model.draft.dropFirst()
            #expect(model.isDirty)
            #expect(try await model.save() == .saved)
            #expect(try Data(contentsOf: file) == Data("B".utf8) + Data(repeating: 65, count: bytes - 3))
        } else {
            #expect(model.draft.isEmpty == (bytes > WorkingTreeText.maximumReadableFileSize))
            #expect(model.readOnlyMessage != nil)
            if model.canViewContent {
                let initial = model.draft
                #expect(model.isReadOnly)
                model.draft = "変更"
                #expect(model.draft == initial)
                #expect(!model.isDirty)
                await #expect(throws: EditorPanelError.noEditableSelection) { try await model.save() }
                await #expect(throws: EditorPanelError.noEditableSelection) { try await model.overwrite() }
                #expect(try Data(contentsOf: file) == original)
            }
        }
    }

    @Test("削除・非UTF-8・編集上限超のファイルでも差分の色付けを保つ", arguments: ["deleted", "invalid", "oversized"])
    func unreadableFileDiffKeepsHighlighting(kind: String) async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q"], cwd: root)
        let file = root.appendingPathComponent("gone.swift")
        try Data("let value = 42\n".utf8).write(to: file)
        try git(["add", "gone.swift"], cwd: root)
        try git(["commit", "-q", "-m", "初期状態"], cwd: root)
        switch kind {
        case "deleted": try FileManager.default.removeItem(at: file)
        case "invalid": try Data([0xff, 0xfe]).write(to: file)
        default: try Data(repeating: 65, count: WorkingTreeText.maximumEditableFileSize + 1).write(to: file)
        }
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.select("gone.swift")
        guard case .diff = model.detail else { Issue.record("差分表示になる前提"); return }
        #expect(!model.canEdit)
        #expect(model.syntaxHighlightingEnabled)
    }

    @Test("非 UTF-8 の未追跡ファイルを選んでも公開状態は安全な空状態になる")
    func selectingNonUTF8FileLeavesSafeEmptyDetail() async throws {
        let root = try makeSingleFileRepo()
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
        let root = try makeSingleFileRepo()
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
        let root = try makeTempDir()
        try git(["init", "-q"], cwd: root)
        let fileURL = root.appendingPathComponent("shift-jis.txt")
        try Data([0x82, 0xA0]).write(to: fileURL)
        try git(["add", "shift-jis.txt"], cwd: root)
        try git(["commit", "-q", "-m", "base"], cwd: root)
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
