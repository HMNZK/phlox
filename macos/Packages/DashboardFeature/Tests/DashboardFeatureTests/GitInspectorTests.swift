import Foundation
import Testing
import DesignSystem
import AgentDomain
import SessionFeature
@testable import DashboardFeature

@Suite("Git インスペクタ")
struct GitInspectorTests {
    @Test func multipleFileDiffResetsHunkBeforeHeaders() {
        let patch = "diff --git a/a b/a\n@@ -1 +1 @@\n-x\n+y\n"
            + "diff --git a/b b/b\n--- a/b\n+++ b/b\n@@ -1 +1 @@\n-u\n+v\n"
        let preview = GitPreview.make(.diff(patch))
        #expect(preview.lines.map(\.text) == ["@@ -1 +1 @@", "x", "y", "@@ -1 +1 @@", "u", "v"])
        #expect(preview.lines.map(\.number) == [nil, 1, 1, nil, 1, 1])
    }

    @Test func lineNumbersAppearAt300Points() {
        for width in [260.0, 280.0, 299.0] { #expect(!GitTabPolicy.showsLineNumbers(width: width)) }
        for width in [300.0, 340.0] { #expect(GitTabPolicy.showsLineNumbers(width: width)) }
    }
    @Test(arguments: [WorkingTreeChange.Kind.added, .modified, .deleted, .renamed, .untracked])
    func kindLetters(_ kind: WorkingTreeChange.Kind) {
        let expected: String
        switch kind {
        case .added: expected = "A"
        case .modified: expected = "M"
        case .deleted: expected = "D"
        case .renamed: expected = "R"
        case .untracked: expected = "U"
        }
        #expect(GitTabPolicy.letter(kind) == expected)
        #expect(GitTabPolicy.kindKey(kind).count > 1)
    }

    @Test func previewUsesRealHunkLineNumbersAndDropsHeaders() {
        let text = "diff --git a/a b/a\nindex 12..34\n--- a/a\n+++ b/a\n@@ -8,2 +10,2 @@\n unchanged\n-old\n+new\n@@ -30 +40 @@\n-x\n+y\n"
        let preview = GitPreview.make(.diff(text))
        #expect(preview.lines.map(\.number) == [nil, 10, 9, 11, nil, 30, 40])
        #expect(preview.lines[2].kind == .deleted)
        #expect(preview.lines[3].text == "new")
        #expect(preview.remaining == 0)
    }

    @Test func untrackedPreviewAndTruncation() {
        let text = (1...86).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let preview = GitPreview.make(.untrackedContent(text))
        #expect(preview.lines.count == 60)
        #expect(preview.remaining == 27)
        #expect(preview.lines.first?.text == "@@ -0,0 +1,86 @@")
        #expect(preview.lines.first?.kind == .hunk)
        #expect(preview.lines.last?.number == 59)
        #expect(preview.lines.dropFirst().allSatisfy { $0.kind == .added })
        #expect(GitPreview.make(.binary).lines.isEmpty)
        #expect(GitPreview.make(.untrackedContent("")).lines.isEmpty)
        #expect(GitPreview.make(.untrackedContent("a\n\n")).lines.map(\.text) == ["@@ -0,0 +1,2 @@", "a", ""])
    }

    @Test func headerLikeContentInsideHunkIsPreserved() {
        let preview = GitPreview.make(.diff("@@ -1 +1 @@\n----\n+++value\n context\n"))
        #expect(preview.lines.map(\.kind) == [.hunk, .deleted, .added, .context])
        #expect(preview.lines.map(\.text) == ["@@ -1 +1 @@", "---", "++value", "context"])
        #expect(preview.lines.map(\.number) == [nil, 1, 1, 2])
    }

    @Test @MainActor func lateSelectionCannotReplaceNewPathOrSource() async throws {
        let parent = FileManager.default.temporaryDirectory
        let fixture = try GitWorkflowRenderFixture(parent: parent)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        for samePath in [false, true] {
            let model = fixture.model()
            var finish: CheckedContinuation<WorkingTreeDetail, Never>?
            model.detailLoader = { _, _ in await withCheckedContinuation { finish = $0 } }
            let old = Task { await model.select("Sources/Workflow.swift", source: .worktree) }
            while finish == nil { await Task.yield() }
            model.detailLoader = nil
            let path = samePath ? "Sources/Workflow.swift" : "notes.md"
            let source: WorkingTreeSource = samePath ? .staged : .worktree
            await model.select(path, source: source)
            let detail = model.detail
            let draft = model.draft
            finish?.resume(returning: .diff("古い差分"))
            await old.value
            #expect(model.gitSelection == .init(path: path, source: source))
            #expect(model.selectedPath == path)
            #expect(model.detail == detail)
            #expect(model.draft == draft)
            #expect(model.isReadOnly == samePath)
        }
    }

    @Test @MainActor func changesExpansionIsRestoredWhenViewIsRecreated() {
        let key = "phlox.inspector.git.changesExpanded"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let model = EditorPanelViewModel(service: nil)
        defaults.removeObject(forKey: key)
        let first = GitInspectorView(model: model, workingDirectory: "", openChanges: { _, _, _ in }, openFile: { _ in })
        #expect(first.changesExpanded)
        first.changesExpanded = false
        let restored = GitInspectorView(model: model, workingDirectory: "", openChanges: { _, _, _ in }, openFile: { _ in })
        #expect(!restored.changesExpanded)
        #expect(!defaults.bool(forKey: key))
    }

    @Test func gitStringsHaveJapaneseAndEnglishTranslations() throws {
        var macos = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { macos.deleteLastPathComponent() }
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: macos.appendingPathComponent("App/Localizable.xcstrings"))) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let root = macos.appendingPathComponent("Packages/DashboardFeature/Sources/DashboardFeature")
        let regex = try NSRegularExpression(pattern: #""([^"\n]*[ぁ-龠][^"\n]*)""#)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("git-localization-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: fixture) }
        var english: [String: String] = [:]
        for file in ["WorkingTree/GitInspectorView.swift", "WorkingTree/GitTabPolicy.swift", "Dashboard/InspectorView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8) as NSString
            for match in regex.matches(in: source as String, range: NSRange(location: 0, length: source.length)) {
                let key = source.substring(with: match.range(at: 1))
                if key.contains("\\") { continue }
                let locales = try #require(strings[key]?["localizations"] as? [String: [String: Any]], "未登録: \(key)")
                for language in ["ja", "en"] {
                    let unit = try #require(locales[language]?["stringUnit"] as? [String: String], "訳なし: \(key) / \(language)")
                    let value = try #require(unit["value"])
                    #expect(!value.isEmpty)
                    if language == "en" { english[key] = value }
                }
            }
        }
        let resources = fixture.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: english, format: .xml, options: 0).write(to: resources.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: fixture))
        #expect(AppLocalizedString.string("ファイルを開く", locale: Locale(identifier: "en"), bundle: bundle) == "Open File")
        #expect(AppLocalizedString.string("パスをコピー", locale: Locale(identifier: "en"), bundle: bundle) == "Copy Path")
    }

    @Test func renameAndBinaryNumstat() {
        let data = Data("12\t3\tsrc/a.swift\0-\t-\timg.png\03\t3\t\0old.swift\0new.swift\0".utf8)
        let counts = WorkingTreeService.parseLineCounts(data)
        #expect(counts["src/a.swift"] == .init(added: 12, deleted: 3))
        #expect(counts["new.swift"] == .init(added: 3, deleted: 3))
        #expect(counts["img.png"] == nil)
    }

    @Test @MainActor func sharedSnapshotSortsAndTracksNewPaths() {
        let model = EditorPanelViewModel(service: nil)
        let a = WorkingTreeChange(path: "a.swift", kind: .modified, isBinary: false)
        let b = WorkingTreeChange(path: "b.swift", kind: .added, isBinary: false)
        let c = WorkingTreeChange(path: "c.swift", kind: .untracked, isBinary: false)
        model.acceptSnapshot(.init(branch: "main", changes: [b, a], lineCounts: [:]))
        #expect(model.changes.map(\.path) == ["a.swift", "b.swift"])
        #expect(model.freshPaths.isEmpty)
        model.acceptSnapshot(.init(branch: "main", changes: [c, b], lineCounts: [:]))
        #expect(model.freshPaths == ["c.swift"])
        model.markGitPathSeen("c.swift")
        #expect(model.freshPaths.isEmpty)
        #expect(model.newChangeCount == 1)
        model.acceptSnapshot(.init(branch: "main", changes: [c, b], lineCounts: [:]))
        #expect(model.freshPaths.isEmpty)
        #expect(model.newChangeCount == 0)
    }

    @Test @MainActor func commitFocusRequestIsConsumedOnce() {
        let model = EditorPanelViewModel(service: nil)
        #expect(!model.takeCommitFocusRequest())
        model.requestCommitFocus()
        #expect(model.takeCommitFocusRequest())
        #expect(!model.takeCommitFocusRequest())
    }

    @Test func statesDistinguishFailureFromNonRepository() {
        #expect(GitTabPolicy.state(list: .noProject, refreshing: true, error: nil, count: 0) == .loading)
        #expect(GitTabPolicy.state(list: .noProject, refreshing: false, error: nil, count: 0) == .noProject)
        #expect(GitTabPolicy.state(list: .notARepository, refreshing: false, error: nil, count: 0) == .notRepository)
        #expect(GitTabPolicy.state(list: .ready, refreshing: false, error: nil, count: 0) == .clean)
        #expect(GitTabPolicy.state(list: .ready, refreshing: false, error: "fatal", count: 0) == .failed("fatal"))
        #expect(GitTabPolicy.state(list: .ready, refreshing: true, error: nil, count: 1) == .changes)
    }

    @Test func refreshEventsAreScopedToProject() {
        for event in [GitTabPolicy.RefreshEvent.shown, .foreground, .manual, .turnEnded(projectMatches: true), .fileChanged(root: "/project")] {
            #expect(GitTabPolicy.shouldRefresh(event, projectRoot: "/project"))
            #expect(!GitTabPolicy.shouldRefresh(event, projectRoot: nil))
        }
        #expect(!GitTabPolicy.shouldRefresh(.turnEnded(projectMatches: false), projectRoot: "/project"))
        #expect(!GitTabPolicy.shouldRefresh(.fileChanged(root: "/other"), projectRoot: "/project"))
        #expect(!GitTabPolicy.shouldRefresh(.fileChanged(root: "/project-x"), projectRoot: "/project"))
        #expect(GitTabPolicy.shouldRefresh(.fileChanged(root: "/project"), projectRoot: "/project/subfolder"))
        #expect(GitTabPolicy.shouldRefresh(.fileChanged(root: "/project/subfolder"), projectRoot: "/project"))
    }

    @Test @MainActor func shortcutsOpenAndPersistTab() throws {
        let name = "GitInspectorTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let router = AppRouter(inspectorDefaults: defaults)
        #expect(router.inspectorTab == .files)
        router.showGitInInspector()
        #expect(router.inspectorVisible && router.inspectorTab == .git)
        let restored = AppRouter(inspectorDefaults: defaults)
        #expect(restored.inspectorTab == .git)
        restored.showFilesInInspector()
        #expect(restored.inspectorVisible && restored.inspectorTab == .files)
    }
}

@Suite("Git インスペクタ実データ", .serialized)
@MainActor
struct GitInspectorServiceTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-git-inspector-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult private func git(_ args: [String], root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "user.name=phlox-test", "-c", "user.email=test@phlox.local", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git failed: \(String(decoding: data, as: UTF8.self))")
        return String(decoding: data, as: UTF8.self)
    }

    @Test func headBasedSnapshotSharesListWithoutChangingIndex() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-b", "fixture", "-q"], root: root)
        try Data("old\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("renamed\n".utf8).write(to: root.appendingPathComponent("old.txt"))
        try git(["add", "."], root: root)
        try git(["commit", "-qm", "初期状態"], root: root)
        try Data("staged\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try git(["add", "a.txt"], root: root)
        try Data("final\nsecond\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try FileManager.default.moveItem(at: root.appendingPathComponent("old.txt"), to: root.appendingPathComponent("renamed.txt"))
        try git(["add", "-A"], root: root)
        try Data("one\ntwo".utf8).write(to: root.appendingPathComponent("untracked.txt"))
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary.dat"))
        let index = root.appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        let modified = try index.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let service = WorkingTreeService(repositoryRoot: root)
        let snapshot = try await service.snapshot()
        #expect(snapshot.branch == "fixture")
        #expect(snapshot.changes.map(\.path) == ["a.txt", "binary.dat", "renamed.txt", "untracked.txt"])
        #expect(snapshot.changes.first?.kind == .modified)
        #expect(snapshot.changes.first { $0.path == "renamed.txt" }?.kind == .renamed)
        #expect(snapshot.changes.first { $0.path == "binary.dat" }?.isBinary == true)
        #expect(snapshot.lineCounts["a.txt"] == .init(added: 2, deleted: 1))
        #expect(snapshot.lineCounts["untracked.txt"] == .init(added: 2, deleted: 0))
        if case .diff(let diff) = try await service.detail(for: "renamed.txt") {
            #expect(diff.contains("rename from old.txt"))
            #expect(diff.contains("rename to renamed.txt"))
        } else { Issue.record("名前変更の差分が取得できない") }
        #expect(try Data(contentsOf: index) == before)
        #expect(try index.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        let model = EditorPanelViewModel(service: service)
        await model.refresh()
        #expect(model.changes == snapshot.changes)
        await model.select("a.txt")
        model.draft = "unsaved edit"
        _ = try await model.gitDetail(for: "untracked.txt")
        #expect(model.selectedPath == "a.txt")
        #expect(model.draft == "unsaved edit" && model.isDirty)
        try Data("new\n".utf8).write(to: root.appendingPathComponent("new.txt"))
        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        _ = await (first, second)
        #expect(model.changes.contains { $0.path == "new.txt" })
        #expect(model.draft == "unsaved edit" && model.isDirty)
    }

    @Test func failedProbeIsNotReportedAsNonRepositoryAndRetryRecovers() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        #expect(model.listState == .notARepository && model.listErrorMessage == nil)
        try Data("invalid git file\n".utf8).write(to: root.appendingPathComponent(".git"))
        await model.refresh()
        #expect(model.listState == .ready)
        #expect(model.listErrorMessage?.contains("invalid gitfile format") == true)
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        try git(["init", "-b", "retry", "-q"], root: root)
        await model.refresh()
        #expect(model.listErrorMessage == nil && model.changes.isEmpty)
        #expect(model.branchLabel == "retry")
    }

    @Test func untrackedCountFailureAndSizeLimitKeepList() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q"], root: root)
        try Data("one\ntwo".utf8).write(to: root.appendingPathComponent("small.txt"))
        try Data(repeating: 10, count: 1024 * 1024).write(to: root.appendingPathComponent("limit.txt"))
        try Data(repeating: 10, count: 1024 * 1024 + 1).write(to: root.appendingPathComponent("large.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside.txt").path, withDestinationPath: "/dev/null")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("missing.txt").path, withDestinationPath: "gone.txt")
        let snapshot = try await WorkingTreeService(repositoryRoot: root).snapshot()
        #expect(snapshot.changes.map(\.path) == ["large.txt", "limit.txt", "missing.txt", "outside.txt", "small.txt"])
        #expect(snapshot.lineCounts["small.txt"] == .init(added: 2, deleted: 0))
        #expect(snapshot.lineCounts["limit.txt"] == .init(added: 1024 * 1024, deleted: 0))
        for path in ["large.txt", "outside.txt", "missing.txt"] { #expect(snapshot.lineCounts[path] == nil) }
        #expect(snapshot.unstagedChanges == snapshot.changes)
        #expect(snapshot.unstagedLineCounts["small.txt"] == .init(added: 2, deleted: 0))
        #expect(snapshot.unstagedLineCounts["limit.txt"] == .init(added: 1024 * 1024, deleted: 0))
        for path in ["large.txt", "outside.txt", "missing.txt"] { #expect(snapshot.unstagedLineCounts[path] == nil) }
    }

    @Test func failedListRefreshPreservesUnsavedDraft() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q"], root: root)
        try Data("disk\n".utf8).write(to: root.appendingPathComponent("draft.txt"))
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        await model.select("draft.txt")
        model.draft = "未保存"
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        try Data("invalid git file\n".utf8).write(to: root.appendingPathComponent(".git"))
        await model.refresh()
        #expect(model.listErrorMessage?.contains("invalid gitfile format") == true)
        #expect(model.selectedPath == "draft.txt" && model.draft == "未保存" && model.isDirty)
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        await model.refresh()
        #expect(model.listState == .notARepository)
        #expect(model.selectedPath == "draft.txt" && model.draft == "未保存" && model.isDirty)
    }

    @Test(arguments: ["", "sub"]) func fileSaveNotificationRefreshesSharedList(folder: String) async throws {
        let root = try fixture().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root), changeScope: .unavailable)
        await model.refresh()
        #expect(model.listState == .notARepository)
        try git(["init", "-q"], root: root)
        await model.refresh()
        #expect(model.listState == .ready)
        #expect(model.changes.isEmpty)
        // ファイルタブの実際の保存が送る通知から、一覧更新までを検査する。
        let projectRoot = folder.isEmpty ? root : root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try Data("disk\n".utf8).write(to: projectRoot.appendingPathComponent("saved.txt"))
        let document = FileTabDocument(path: "saved.txt", root: projectRoot.path)
        await document.loadIfNeeded()
        document.draft = "saved\nsecond\n"
        #expect(try await document.save() == .saved)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let path = folder.isEmpty ? "saved.txt" : folder + "/saved.txt"
        while !model.changes.contains(where: { $0.path == path }), clock.now < deadline { await Task.yield() }
        #expect(model.changes.map(\.path) == [path])
        #expect(model.lineCounts[path] == .init(added: 2, deleted: 0))
    }

    @Test func actualTurnCompletionRefreshesOnlyItsProject() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q"], root: root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        let projectID = ProjectID()
        let client = CharacterizationFakeClient()
        let session = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.cursor), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path)
        session.projectID = projectID
        try await session.startNew(approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        let nodes: [SessionNode] = [.appServer(session)]
        let old = GitTabPolicy.turnCompletions(sessions: nodes, projectID: projectID)
        let otherProject = ProjectID()
        let otherOld = GitTabPolicy.turnCompletions(sessions: nodes, projectID: otherProject)
        try Data("turn output\n".utf8).write(to: root.appendingPathComponent("turn.txt"))
        try await session.sendText("更新", submit: true)
        client.yield(.turnStarted)
        client.yield(.turnCompleted(nativeSessionId: nil))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while session.lastTurnCompletedAt == nil, clock.now < deadline { await Task.yield() }
        try #require(session.lastTurnCompletedAt != nil)
        let revision = model.refreshRevision
        await GitTabPolicy.refreshAfterTurnCompletions(old: otherOld,
            new: GitTabPolicy.turnCompletions(sessions: nodes, projectID: otherProject), model: model)
        #expect(model.refreshRevision == revision && model.changes.isEmpty)
        let new = GitTabPolicy.turnCompletions(sessions: nodes, projectID: projectID)
        await GitTabPolicy.refreshAfterTurnCompletions(old: old, new: new, model: model)
        #expect(model.refreshRevision == revision + 1)
        #expect(model.changes.map(\.path) == ["turn.txt"])
        #expect(model.lineCounts["turn.txt"] == .init(added: 1, deleted: 0))
        await GitTabPolicy.refreshAfterTurnCompletions(old: new, new: new, model: model)
        #expect(model.refreshRevision == revision + 1)
        await client.close()
    }
}
