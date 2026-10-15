import AppKit
import Foundation
import AgentDomain
import Testing
import SwiftUI
@testable import DashboardFeature

@Suite("ツリーのファイル操作")
struct FileTreeOperationsTests {
    @Test("一時ファイルをゴミ箱へ移し、本文を保持する")
    func trashSuccess() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("phlox-trash-\(UUID().uuidString).txt")
        try Data("ゴミ箱でも保持".utf8).write(to: file)
        let reference = try FileTreeOperations.fileReference(for: file)
        #expect(reference.contains("/.file/id="))
        #expect(try await FileTreeOperations(root: root.path).execute(.trash(path: file.lastPathComponent)) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let trashed = try FileTreeOperations.filePath(for: reference)
        #expect(trashed.path != file.path)
        #expect(try String(contentsOf: trashed, encoding: .utf8) == "ゴミ箱でも保持")
        try FileManager.default.moveItem(at: trashed, to: file)
    }

    @Test("参照取得後に外へ移動して元パスを作り直しても外の実体を削除しない")
    func trashMovedReference() async throws {
        let base = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("a.txt"), outside = base.appendingPathComponent("outside.txt")
        try Data("元の実体".utf8).write(to: original)
        let reference = try FileTreeOperations.fileReference(for: original)
        try FileManager.default.moveItem(at: original, to: outside)
        try Data("別の実体".utf8).write(to: original)
        #expect(try FileTreeOperations.filePath(for: reference).path == outside.path)
        await #expect(throws: WorkingTreeServiceError.self) {
            try await FileTreeOperations(root: root.path).trash(reference: reference)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "元の実体")
        #expect(try String(contentsOf: original, encoding: .utf8) == "別の実体")
    }

    @Test("文書のない復元タブへの付け替えでも同じタブを重複させない")
    func restoredTabCollision() {
        var layout = ProjectTabLayout()
        layout.open(.file("a.md"))
        layout.open(.file("b.md"))
        layout.splitRight(.file("a.md"))
        layout.retargetFiles(from: "a.md", to: "b.md")
        #expect(Set(layout.items).count == layout.items.count)
        #expect(layout.items == [.file("b.md")])
        #expect(layout.left == .file("b.md"))
        #expect(layout.right == nil)
    }

    @Test("保存待ち中に別ウィンドウで文書が増える・未保存になると再確認する", arguments: [false, true]) @MainActor
    func recheckAfterPendingSave(addDocument: Bool) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        for name in ["a.txt", "b.txt"] { try Data("元の本文".utf8).write(to: root.appendingPathComponent("docs/" + name)) }
        let registry = FileTabDocumentRegistry(), first = FileTabDocuments(), second = FileTabDocuments(), id = ProjectID()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let firstRouter = AppRouter(), secondRouter = AppRouter()
        first.router = firstRouter; second.router = secondRouter
        registry.register(files: second, window: window)
        let document = first.document(for: id, path: "docs/a.txt", root: root.path)
        await document.loadIfNeeded()
        if !addDocument {
            let other = second.document(for: id, path: "docs/b.txt", root: root.path)
            await other.loadIfNeeded()
            second.router?.tabs.updateLayout(for: id) { $0.open(.file("docs/b.txt")) }
        }
        document.draft = "保存する本文"
        let state = registry.trashState(root: root.path, path: "docs", projectID: id, including: first)
        #expect(registry.trashStateMatches(state, root: root.path, path: "docs", projectID: id, including: first))
        let saving = try document.enqueueSave(overwrite: false)
        document.fileOperationInProgress = true
        defer { document.fileOperationInProgress = false }
        let change = Task { @MainActor in
            #expect(document.hasPendingSaves)
            let other = second.document(for: id, path: "docs/b.txt", root: root.path)
            other.draft = "確認していない未保存の変更"
            second.router?.tabs.updateLayout(for: id) { $0.open(.file("docs/b.txt")) }
        }
        #expect(!(await registry.trashStateMatchesAfterSaves(state, root: root.path, path: "docs", projectID: id, including: first)))
        await change.value
        #expect(try await saving.value == .saved)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/a.txt").path))
        #expect(!document.invalidated)
        #expect(second.existing(for: id, path: "docs/b.txt")?.draft == "確認していない未保存の変更")
    }

    @Test("確認済みの未保存文書とは別の文書が未保存になると再確認する") @MainActor
    func newlyDirtyDocument() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = FileTabDocumentRegistry(), files = FileTabDocuments(), id = ProjectID()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        for name in ["a.txt", "b.txt"] { try Data("元".utf8).write(to: root.appendingPathComponent("docs/" + name)) }
        let first = files.document(for: id, path: "docs/a.txt", root: root.path)
        let second = files.document(for: id, path: "docs/b.txt", root: root.path)
        await first.loadIfNeeded(); await second.loadIfNeeded()
        first.draft = "確認済み"
        let state = registry.trashState(root: root.path, path: "docs", projectID: id, including: files)
        second.draft = "新しい未保存"
        #expect(!registry.trashStateMatches(state, root: root.path, path: "docs", projectID: id, including: files))
    }

    @Test("保存で未保存が減るだけなら再確認せず、文書のない復元タブも対象に含む") @MainActor
    func savedStateAndRestoredPaths() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        try Data("元".utf8).write(to: root.appendingPathComponent("docs/a.txt"))
        let registry = FileTabDocumentRegistry(), files = FileTabDocuments(), id = ProjectID()
        let router = AppRouter()
        files.router = router
        files.router?.tabs.updateLayout(for: id) { $0.open(.file("docs/a.txt")); $0.open(.file("docs/b.txt")) }
        let document = files.document(for: id, path: "docs/a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "保存する本文"
        let state = registry.trashState(root: root.path, path: "docs", projectID: id, including: files)
        #expect(state.paths == ["docs/a.txt", "docs/b.txt"])
        #expect(files.existing(for: id, path: "docs/b.txt") == nil)
        #expect(registry.operationTabPaths(root: root.path, path: "docs/b.txt", projectID: id, including: files) == ["docs/b.txt"])
        let saving = try document.enqueueSave(overwrite: false)
        document.fileOperationInProgress = true
        defer { document.fileOperationInProgress = false }
        #expect(await registry.trashStateMatchesAfterSaves(state, root: root.path, path: "docs", projectID: id, including: files))
        #expect(try await saving.value == .saved)
        #expect(!document.hasUnsavedChanges)
    }

    @Test("キーボードで移した選択が実際の行の読み上げ属性に反映される") @MainActor
    func keyboardSelectionAccessibility() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data().write(to: root.appendingPathComponent(name)) }
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let model = FileTreeModel(root: root.path, readBranch: { "" })
        await model.load("")
        let host = NSHostingView(rootView: FileTreeView(model: model, openPath: "a.txt", open: { _, _ in }, keyboardPath: "a.txt"))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 440)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.contentView = host
        defer { window.close() }
        var selected = "a.txt"
        for key in [FileTreeRows.Key.down, .up] {
            guard case .select(let path) = FileTreeRows.action(for: selected, key: key, rows: model.rows, expanded: []) else {
                Issue.record("上下キーで選択が移らなかった"); return
            }
            selected = path
            host.rootView = FileTreeView(model: model, openPath: "a.txt", open: { _, _ in }, keyboardPath: selected)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            for name in ["a.txt", "b.txt"] {
                let row = try #require(accessibleObject(identifier: "file-tree-row-" + name, in: host))
                #expect((row as AnyObject).isAccessibilitySelected() == (name == selected))
            }
        }
    }

    @MainActor private func accessibleObject(identifier: String, in root: NSObject) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            let id = NSSelectorFromString("accessibilityIdentifier")
            if object.responds(to: id), object.perform(id)?.takeUnretainedValue() as? String == identifier { return object }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                for child in values { if let found = visit(child) { return found } }
            }
            if let view = object as? NSView {
                for child in view.subviews { if let found = visit(child) { return found } }
            }
            return nil
        }
        return visit(root)
    }
    private func fixture() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".build/file-operations-tests/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    @Test("使えない名前は理由を返す", arguments: [
        ("", "名前を入力してください"), ("a/b", "名前に / は使えません"),
        (".", "「.」と「..」は名前に使えません"), ("..", "「.」と「..」は名前に使えません"),
        ("a\u{0}b", "名前に NUL は使えません"), (".git", "この名前はファイル操作の対象外です"),
        (".DS_Store", "この名前はファイル操作の対象外です")
    ])
    func invalidName(_ value: (String, String)) {
        #expect(FileTreeOperations.nameError(value.0, siblings: [])?.key == value.1)
    }

    @Test("衝突相手の種類を言い分け、大文字小文字だけの変更を許す")
    func collisions() {
        let siblings: [FileTreeEntry] = [.init(relativePath: "readme.md", name: "readme.md", kind: .file),
                                          .init(relativePath: "docs", name: "docs", kind: .directory)]
        #expect(FileTreeOperations.nameError("readme.md", siblings: siblings)?.key == "同じ名前のファイルがあります")
        #expect(FileTreeOperations.nameError("docs", siblings: siblings)?.key == "同じ名前のフォルダがあります")
        #expect(FileTreeOperations.nameError("README.md", siblings: siblings, renaming: "readme.md") == nil)
        #expect(FileTreeOperations.nameError("readme.md", siblings: siblings, renaming: "readme.md") == nil)
        #expect(FileTreeOperations.nameError("", siblings: siblings, submitted: false) == nil)
        #expect(FileTreeOperations.nameError("README.md", siblings: siblings, caseSensitive: false)?.key == "同じ名前のファイルがあります")
        #expect(FileTreeOperations.nameError("README.md", siblings: siblings, renaming: "readme.md", caseSensitive: false) == nil)
    }

    @Test("拡張子より前をUTF-16範囲で選択し、隠し名・フォルダは全体を選ぶ")
    func selection() {
        #expect(FileTreeOperations.nameSelection("📄資料.md", folder: false) == NSRange(location: 0, length: 4))
        #expect(FileTreeOperations.nameSelection(".gitignore", folder: false).length == 10)
        #expect(FileTreeOperations.nameSelection("docs.v2", folder: true).length == 7)
        #expect(FileTreeOperations.nameSelection("LICENSE", folder: false).length == 7)
    }

    @Test("新規・名前変更は実ディスクへ反映し、既存ファイルを上書きしない")
    func createRename() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = FileTreeOperations(root: root.path)
        #expect(try await operations.execute(.create(parent: "", name: "docs", folder: true)) == "docs")
        #expect(try await operations.execute(.create(parent: "docs", name: "readme.md", folder: false)) == "docs/readme.md")
        try Data("本文".utf8).write(to: root.appendingPathComponent("docs/readme.md"))
        await #expect(throws: FileTreeNameError(key: "同じ名前のファイルがあります")) {
            try await operations.execute(.create(parent: "docs", name: "readme.md", folder: false))
        }
        #expect(try await operations.execute(.rename(path: "docs/readme.md", name: "README.md")) == "docs/README.md")
        #expect(try String(contentsOf: root.appendingPathComponent("docs/README.md"), encoding: .utf8) == "本文")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("docs").path)
        #expect(names == ["README.md"])
        try Data("他の本文".utf8).write(to: root.appendingPathComponent("docs/other.md"))
        await #expect(throws: FileTreeNameError(key: "同じ名前のファイルがあります")) {
            try await operations.execute(.rename(path: "docs/README.md", name: "other.md"))
        }
        #expect(try String(contentsOf: root.appendingPathComponent("docs/other.md"), encoding: .utf8) == "他の本文")
    }

    @Test("ルート・相対パス逸脱・外向きリンク・差し替えられた親を拒否する")
    func containment() async throws {
        let base = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("保持".utf8).write(to: outside.appendingPathComponent("keep"))
        let operations = FileTreeOperations(root: root.path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        for operation in [FileTreeOperation.rename(path: "", name: "root2"), .trash(path: ""),
                          .create(parent: "../outside", name: "bad", folder: false),
                          .rename(path: "link", name: "other"), .trash(path: "link"),
                          .create(parent: "link", name: "bad", folder: false)] {
            await #expect(throws: (any Error).self) { try await operations.execute(operation) }
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        let stale = try FileTreeLoader.readDirectory(root: root, path: "").entries.first { $0.name == "docs" }
        #expect(stale?.kind == .directory)
        try FileManager.default.removeItem(at: root.appendingPathComponent("docs"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs"), withDestinationURL: outside)
        await #expect(throws: (any Error).self) {
            try await operations.execute(.create(parent: "docs", name: "bad", folder: false))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["keep"])
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("git-link"), withDestinationURL: root.appendingPathComponent(".git"))
        let gitLink = try #require(FileTreeLoader.readDirectory(root: root, path: "").entries.first { $0.name == "git-link" })
        #expect(!gitLink.canCreate)
        #expect(gitLink.canModify)
        let reference = try #require((root.appendingPathComponent("git-link") as NSURL).fileReferenceURL())
        #expect(try reference.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @Test("件数は子孫も含めて1,000で止め、リンクの先は数えない", arguments: [0, 12, 1_000, 1_001])
    func counts(_ count: Int) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        for index in 0..<count { try Data().write(to: dir.appendingPathComponent("item-\(index)")) }
        let result = try await FileTreeOperations(root: root.path).countItems(in: "docs")
        #expect(result.total == min(count, 1_000))
        #expect(result.limited == (count > 1_000))
    }

    @Test("フォルダ内の件数とリンクの非追跡")
    func nestedCounts() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("docs/sub/a"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/loop"), withDestinationURL: root.appendingPathComponent("docs"))
        let count = try await FileTreeOperations(root: root.path).countItems(in: "docs")
        #expect(count == FileTreeItemCount(folders: 1, files: 2, limited: false))
    }

    @Test("失敗でもディスクを再読込し、直前にできた同名を表示する") @MainActor
    func failureReload() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = FileTreeModel(root: root.path)
        await model.load("")
        #expect(model.rows.isEmpty)
        await model.beginCreate(at: nil, folder: false)
        #expect(model.edit?.error == nil)
        model.updateName("race.txt")
        let operation = try #require(model.submitEdit())
        try Data("既存".utf8).write(to: root.appendingPathComponent("race.txt"))
        let result = await model.perform(operation)
        if case .success = result { Issue.record("同名競合を成功扱いにした") }
        #expect(model.rows.map(\.id) == ["race.txt"])
        #expect(model.operationFailure?.reason == "同じ名前のファイルがあります")
        #expect(try String(contentsOf: root.appendingPathComponent("race.txt"), encoding: .utf8) == "既存")
        await model.refresh()
        #expect(model.operationFailure == nil)
    }

    @Test("新規入力は種類の先頭に固定され、確定後に名前順へ移る") @MainActor
    func inlineOrder() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("a.txt"))
        let model = FileTreeModel(root: root.path)
        await model.load("")
        await model.beginCreate(at: nil, folder: false)
        let editID = try #require(model.edit?.rowID)
        #expect(model.rows.map(\.id) == ["docs", editID, "a.txt"])
        model.updateName("z.txt")
        #expect(model.rows.map(\.id) == ["docs", editID, "a.txt"])
        let operation = try #require(model.submitEdit())
        _ = await model.perform(operation)
        #expect(model.rows.map(\.id) == ["docs", "a.txt", "z.txt"])
        #expect(model.operationSelection == "z.txt")
    }

    @Test("付け替えはパスの境界で判定する")
    func pathBoundaries() {
        #expect(FileTreeOperations.renamedPath("docs/a.md", from: "docs", to: "notes") == "notes/a.md")
        #expect(FileTreeOperations.renamedPath("docs2/a.md", from: "docs", to: "notes") == nil)
        #expect(FileTreeOperations.renamedPath("docs", from: "docs", to: "notes") == "notes")
    }

    @Test("5,000件の表示上限でも作成した行を表示して選択する") @MainActor
    func revealBeyondDisplayLimit() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<5_000 { try Data().write(to: root.appendingPathComponent(String(format: "a-%04d", index))) }
        let model = FileTreeModel(root: root.path)
        _ = await model.perform(.create(parent: "", name: "z-new", folder: false))
        #expect(model.operationSelection == "z-new")
        #expect(model.rows.count == 5_000)
        #expect(model.rows.last?.id == "z-new")
        #expect(model.omittedByDir[""] == 1)
        await model.load("")
        #expect(model.rows.last?.id == "z-new")
        await model.beginCreate(at: nil, folder: false)
        model.updateName("a-4999")
        #expect(model.edit?.error == "同じ名前のファイルがあります")
    }

    @Test("文書実体・未保存の編集・編集中のブロック・分割配置を保って付け替える") @MainActor
    func retargetTabs() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false)
        try Data("元の本文\n".utf8).write(to: root.appendingPathComponent("docs/a.md"))
        let files = FileTabDocuments(), router = AppRouter(), id = ProjectID()
        files.router = router
        let document = files.document(for: id, path: "docs/a.md", root: root.path)
        await document.loadIfNeeded()
        document.draft = "未保存\n"
        let block = try #require(document.markdownBlocks.first)
        #expect(document.beginBlockEdit(range: block.range))
        let edit = try #require(document.activeBlockEdit)
        let undo = document.undoManager
        document.updateActiveBlockEdit(id: edit.id, current: "未確定")
        router.tabs.updateLayout(for: id) {
            $0.open(.changes); $0.open(.file("docs/a.md")); $0.splitRight(.file("docs/a.md"))
        }
        _ = try await FileTreeOperations(root: root.path).execute(.rename(path: "docs", name: "notes"))
        FileTabDocumentRegistry().retargetOperationTabs(root: root.path, from: "docs", to: "notes", projectID: id, including: files)
        #expect(files.existing(for: id, path: "docs/a.md") == nil)
        #expect(files.existing(for: id, path: "notes/a.md") === document)
        #expect(document.path == "notes/a.md")
        #expect(document.draft == "未保存\n")
        #expect(document.activeBlockEdit?.id == edit.id)
        #expect(document.activeBlockEdit?.current == "未確定")
        #expect(document.hasUnsavedChanges)
        #expect(document.undoManager === undo)
        #expect(router.tabs.layout(for: id).right == .file("notes/a.md"))
        #expect(try await document.save() == .saved)
        #expect(try String(contentsOf: root.appendingPathComponent("notes/a.md"), encoding: .utf8) == "未確定")
    }

    @Test("Returnは名前変更、⌘↓はファイルだけを開く")
    func keyboardActions() {
        let file = FileTreeRows.Row(entry: .init(relativePath: "a", name: "a", kind: .file), depth: 0)
        let folder = FileTreeRows.Row(entry: .init(relativePath: "docs", name: "docs", kind: .directory), depth: 0)
        let outside = FileTreeRows.Row(entry: .init(relativePath: "outside", name: "outside", kind: .symlinkOutsideRoot), depth: 0)
        let rows = [file, folder, outside]
        #expect(FileTreeRows.action(for: "a", key: .rename, rows: rows, expanded: []) == .rename("a"))
        #expect(FileTreeRows.action(for: "docs", key: .rename, rows: rows, expanded: []) == .rename("docs"))
        #expect(FileTreeRows.action(for: "outside", key: .rename, rows: rows, expanded: []) == nil)
        #expect(FileTreeRows.action(for: "a", key: .open, rows: rows, expanded: []) == .open("a"))
        #expect(FileTreeRows.action(for: "docs", key: .open, rows: rows, expanded: []) == nil)
        let renamedRows = [FileTreeRows.Row(entry: .init(relativePath: "notes", name: "notes", kind: .directory), depth: 0),
            .init(entry: .init(relativePath: "notes/a", name: "a", kind: .file), depth: 1),
            .init(entry: .init(relativePath: "notes/b", name: "b", kind: .file), depth: 1)]
        #expect(FileTreeRows.selection(openPath: "notes/a", selectedPath: "notes", rows: renamedRows,
            previousOpenPath: "docs/a", renamed: ("docs", "notes")) == "notes")
        #expect(FileTreeRows.selection(openPath: "notes/b", selectedPath: "notes", rows: renamedRows,
            previousOpenPath: "notes/a", renamed: ("docs", "notes")) == "notes/b")
    }

    @Test("操作中は編集と新しい保存を拒否し、読込済みの本文は保持する") @MainActor
    func operationLock() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("保持する本文".utf8).write(to: root.appendingPathComponent("a.md"))
        let document = FileTabDocument(path: "a.md", root: root.path)
        document.fileOperationInProgress = true
        await document.loadIfNeeded()
        #expect(document.draft == "保持する本文")
        document.draft = "入力中"
        #expect(document.draft == "保持する本文")
        await #expect(throws: FileTabDocument.DocumentError.fileOperationInProgress) { try await document.save() }
        document.fileOperationInProgress = false
        document.draft = "変更"
        let block = try #require(document.markdownBlocks.first)
        #expect(document.beginBlockEdit(range: block.range))
        let edit = try #require(document.activeBlockEdit)
        document.updateActiveBlockEdit(id: edit.id, current: "編集中")
        document.fileOperationInProgress = true
        #expect(!document.commitActiveBlockEdit())
        document.discardActiveBlockEdit(id: edit.id)
        #expect(document.activeBlockEdit?.id == edit.id)
        #expect(document.activeBlockEdit?.current == "編集中")
        document.fileOperationInProgress = false
        #expect(try await document.save() == .saved)
        #expect(document.undoManager.canUndo)
        document.fileOperationInProgress = true
        document.undoManager.undo()
        #expect(document.draft == "編集中")
        document.fileOperationInProgress = false
        #expect(document.undoManager.canUndo)
        document.undoManager.undo()
        #expect(document.draft == "変更")
    }

    @Test("全ウィンドウの対象タブを付け替え、削除時は無関係なタブを残す") @MainActor
    func crossWindowTabs() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = ProjectID(), registry = FileTabDocumentRegistry()
        let first = FileTabDocuments(), second = FileTabDocuments()
        let routers = [AppRouter(), AppRouter()]
        let stores = [first, second]
        let windows = (0..<2).map { _ in NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                                                styleMask: [.borderless], backing: .buffered, defer: false) }
        defer { for window in windows { window.close() } }
        for index in 0..<2 {
            windows[index].isReleasedWhenClosed = false
            stores[index].router = routers[index]
            registry.register(files: stores[index], window: windows[index])
            _ = stores[index].document(for: id, path: "docs/a.md", root: root.path)
            routers[index].tabs.updateLayout(for: id) { $0.open(.file("docs/a.md")); $0.open(.file("docs2/b.md")) }
        }
        #expect(registry.operationTabPaths(root: root.path, path: "docs", projectID: id, including: first) == ["docs/a.md"])
        registry.retargetOperationTabs(root: root.path, from: "docs", to: "notes", projectID: id, including: first)
        for router in routers { #expect(router.tabs.layout(for: id).items == [.file("notes/a.md"), .file("docs2/b.md")]) }
        let documents = registry.operationDocuments(root: root.path, path: "notes", including: first)
        #expect(documents.count == 2)
        await registry.closeOperationTabs(root: root.path, path: "notes", projectID: id, including: first)
        for router in routers { #expect(router.tabs.layout(for: id).items == [.file("docs2/b.md")]) }
        #expect(documents.allSatisfy { $0.invalidated })
    }

    @Test("未保存だけを破壊的表示にし、Return・Esc・⌘⌫を安全に設定する", arguments: [false, true]) @MainActor
    func alertDefaults(_ dirty: Bool) throws {
        _ = NSApplication.shared
        let confirmation = FileTreeTrashConfirmation(entry: .init(relativePath: "a.md", name: "a.md", kind: .file),
            root: "/project", count: nil, openItems: [.init(path: "a.md", dirty: dirty)])
        let alert = FileTreeTrashAlert.make(confirmation, locale: Locale(identifier: "ja"), bundle: .main)
        #expect(alert.buttons[0].title == (dirty ? "キャンセル" : "ゴミ箱に入れる"))
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[0].keyEquivalentModifierMask.isEmpty)
        #expect(alert.buttons[1].keyEquivalent.isEmpty)
        #expect(alert.buttons[dirty ? 1 : 0].hasDestructiveAction == dirty)
        #expect(alert.informativeText.contains("開いているタブを閉じます"))
        #expect(alert.informativeText.contains("未保存の変更は失われます") == dirty)
        let hidden = alert.window.contentView?.subviews.compactMap { $0 as? NSButton } ?? []
        let escape = try #require(hidden.first { $0.keyEquivalent == "\u{1b}" })
        #expect(escape.target as? NSButton === alert.buttons[dirty ? 0 : 1])
        #expect(escape.keyEquivalentModifierMask.isEmpty)
        #expect(escape.action == #selector(NSButton.performClick(_:)))
        let delete = try #require(hidden.first { $0.keyEquivalent == "\u{7f}" })
        #expect(delete.keyEquivalentModifierMask == .command)
        #expect(delete.action == nil)
        alert.window.close()
    }

    @Test("日本語の確認本文には文間の半角空白を入れない", arguments: [1, 2])
    func japaneseTrashMessage(count: Int) {
        let confirmation = FileTreeTrashConfirmation(entry: .init(relativePath: "docs", name: "docs", kind: .directory),
            root: "/project", count: .init(folders: 1, files: 2),
            openItems: (0..<count).map { .init(path: "docs/\($0).md", dirty: true) })
        let message = confirmation.message(locale: Locale(identifier: "ja"), bundle: .main)
        #expect(!message.contains("。 "))
        #expect(message.hasSuffix("閉じます。未保存の変更は失われます。"))
    }
}
