import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("ファイルツリーの表示状態")
@MainActor
struct FileTreeModelTests {
    @Test("未オープンのファイルを右に分割して開く")
    func splitUnopened() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        #expect(files.openFileTab(sessionID: id, root: "/A", relativePath: "new.txt", split: true,
                                  router: router, requestedWorkingDirectory: "/A", currentWorkingDirectory: "/A"))
        let layout = router.tabs.layout(for: id)
        #expect(layout.tabs == [.conversation, .file("new.txt")])
        #expect(layout.left == .conversation)
        #expect(layout.right == .file("new.txt"))
        #expect(layout.selected == .file("new.txt"))
    }

    @Test("更新・展開・保存が進行中の同じフォルダの読み込みに相乗りする", arguments: ["refresh", "expand", "save"])
    func coalesces(_ request: String) async throws {
        let gate = FileTreeReadGate()
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = FileTreeModel(root: root.path, loader: FileTreeLoader(root: root.path, read: { _, _ in try await gate.read() }))
        let seed = Task { await model.load("") }
        await gate.started(1)
        await gate.finish(1, name: "dir", kind: .directory)
        await seed.value
        let path = request == "expand" ? "dir" : ""
        let first = Task { await model.load(path) }
        await gate.started(2)
        let second = Task {
            switch request {
            case "expand": await model.expand("dir")
            case "save": await model.fileSaved(root: root.path, relativePath: "new.txt")
            default: await model.refresh()
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let calls = await gate.calls
        await gate.finish(2, name: "new.txt")
        if calls > 2 { await gate.finish(3, name: "duplicate.txt") }
        await first.value
        await second.value
        #expect(await gate.calls == 2)
        #expect(model.childrenByDir[path]?.map(\.name) == ["new.txt"])
        #expect(model.loading.isEmpty)
    }

    @Test("フォルダの失敗理由は日本語で表示し、他の行は残す")
    func japaneseErrors() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("a.txt"))
        let model = FileTreeModel(root: root.path)
        await model.refresh()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        await model.expand("locked")
        #expect(model.errorsByDir["locked"] == "アクセス権がないため読み込めません。")
        #expect(model.rows.map(\.id) == ["locked", "a.txt"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try FileManager.default.removeItem(at: locked)
        await model.refresh()
        #expect(model.errorsByDir["locked"] == "ファイルまたはフォルダが見つかりません。")
    }

    @Test("表示・更新・展開・保存の読み直しとルートごとの展開保持")
    func refreshAndSave() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = FileTreeModel(root: root.path)
        await model.refresh()
        #expect(model.branch == "Git 管理外")
        await model.expand("dir")
        try Data().write(to: dir.appendingPathComponent("a.txt"))
        await model.fileSaved(root: "/other", relativePath: "dir/a.txt")
        #expect(model.rows.map(\.id) == ["dir"])
        await model.fileSaved(root: root.path, relativePath: "dir/a.txt")
        #expect(model.rows.map(\.id) == ["dir", "dir/a.txt"])
        #expect(model.rows[1].isOpen("dir/a.txt"))
        #expect(!model.rows[1].isOpen("other.txt"))
        await model.refresh()
        #expect(model.expanded == ["dir"])
        model.collapse("dir")
        try Data().write(to: dir.appendingPathComponent("b.txt"))
        await model.expand("dir")
        #expect(model.rows.map(\.id) == ["dir", "dir/a.txt", "dir/b.txt"])
        #expect(model.errorsByDir.isEmpty)
        #expect(model.loading.isEmpty)
    }

    @Test("同じルートへ戻ると展開状態を再利用し、別ルートは新規になる")
    func rootReuse() async throws {
        let root = try fileTreeFixture()
        let other = try fileTreeFixture()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        for base in [root, other] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent("dir"), withIntermediateDirectories: true)
            try Data().write(to: base.appendingPathComponent("dir/a.txt"))
        }
        var models: [String: FileTreeModel] = [:]
        let first = FileTreeModel.model(for: root.path, in: models)
        models[root.path] = first
        await first.refresh()
        await first.expand("dir")
        let different = FileTreeModel.model(for: other.path, in: models)
        models[other.path] = different
        await different.refresh()
        #expect(different.expanded.isEmpty)
        #expect(different.rows.map(\.id) == ["dir"])
        let returned = FileTreeModel.model(for: root.path, in: models)
        await returned.refresh()
        #expect(returned.expanded == ["dir"])
        #expect(returned.rows.map(\.id) == ["dir", "dir/a.txt"])
        returned.collapse("dir")
        #expect(first.rows.map(\.id) == ["dir"])
        #expect(models.count == 2)
    }

    @Test("更新ボタンの再読込で新しいファイルが現れる")
    func refreshNewFile() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = FileTreeModel(root: root.path)
        await model.refresh()
        #expect(model.rows.isEmpty)
        try Data().write(to: root.appendingPathComponent("new.txt"))
        #expect(model.rows.isEmpty)
        await model.refresh()
        #expect(model.rows.map(\.id) == ["new.txt"])
    }

    @Test("保存成功通知にルートと相対パスが入り、親フォルダを再読込できる")
    func saveNotification() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("before".utf8).write(to: directory.appendingPathComponent("a.txt"))
        let model = FileTreeModel(root: root.path)
        await model.refresh()
        await model.expand("dir")
        let document = FileTabDocument(path: "dir/a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "after"
        @MainActor final class Received {
            var root: String?
            var path: String?
            var count = 0
        }
        let received = Received()
        let token = NotificationCenter.default.addObserver(forName: .fileTreeFileSaved, object: nil, queue: nil) { notification in
            let root = notification.userInfo?["root"] as? String
            let path = notification.userInfo?["path"] as? String
            MainActor.assumeIsolated {
                received.root = root
                received.path = path
                received.count += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try Data().write(to: directory.appendingPathComponent("new.txt"))
        #expect(try await document.save() == .saved)
        #expect(received.count == 1)
        #expect(received.root == root.path)
        #expect(received.path == "dir/a.txt")
        await model.fileSaved(root: try #require(received.root), relativePath: try #require(received.path))
        #expect(model.rows.map(\.id) == ["dir", "dir/a.txt", "dir/new.txt"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("a.txt")) == Data("after".utf8))
        try Data("external".utf8).write(to: directory.appendingPathComponent("a.txt"))
        document.draft = "conflict"
        #expect(try await document.save() == .conflictDetected)
        #expect(received.count == 1)
    }

    @Test("ルート解決後に作業場所が変わった要求は開かない")
    func changedWorkingDirectory() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        #expect(!files.openFileTab(sessionID: id, root: "/old", relativePath: "a.txt", router: router,
                                   requestedWorkingDirectory: "/old", currentWorkingDirectory: "/new"))
        #expect(router.tabs.layout(for: id).tabs == [.conversation])
    }

    @Test("古い読込が新しい表示を上書きせず、削除時は理由を表示する")
    func staleAndErrors() async throws {
        let gate = FileTreeReadGate()
        let model = FileTreeModel(root: "/", loader: FileTreeLoader(root: "/", read: { _, _ in try await gate.read() }))
        let old = Task { await model.load("", refresh: true) }
        await gate.started(1)
        let new = Task { await model.load("", refresh: true) }
        await gate.started(2)
        await gate.finish(2, name: "new")
        await new.value
        await gate.finish(1, name: "old")
        await old.value
        #expect(model.rows.map(\.id) == ["new"])
        #expect(model.loading.isEmpty)
        let root = try fileTreeFixture()
        try FileManager.default.removeItem(at: root)
        let missing = FileTreeModel(root: root.path)
        await missing.refresh()
        #expect(missing.errorsByDir[""] != nil)
        #expect(missing.branch.isEmpty)
    }

    @Test("ショートカットの要求はインスペクタを開きファイルを選ぶ")
    func showFiles() {
        let router = AppRouter()
        router.showFilesInInspector()
        #expect(router.inspectorVisible)
        #expect(router.inspectorTab == .files)
    }
}
