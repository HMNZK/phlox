// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — エディタパネル VM（一覧→選択→表示→編集→保存／競合）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面:
// - EditorPanelViewModel(service:)
// - ListState { noProject, notARepository, ready } / listState
// - Detail { none, diff(String), content(String), binary } / detail
// - changes / selectedPath / draft / isDirty
// - refresh() / select(_:) / save() -> SaveResult { saved, conflictDetected } / overwrite()
//
// ゲート①決定: 保存競合は「警告後にユーザー版で上書き」= save が conflictDetected を
// 返したら UI が警告し、ユーザーの確認後に overwrite() で上書きする二段構え。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Editor panel VM acceptance (task-4)", .timeLimit(.minutes(1)))
@MainActor
struct AcceptanceEditorPanelVMTests {

    // MARK: - fixture harness（AcceptanceWorkingTreeTests と同型の最小版）

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-acceptance-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - acceptance

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
}
