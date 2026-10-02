import AppKit
import AgentDomain
import Testing
@testable import DashboardFeature

@MainActor
struct CrossWindowDraftTests {
    @Test("子タブ破棄は別ウィンドウの同じセッション・パスだけを確認し保存待ちで失効させる")
    func closingFileCollectsAndRemovesMatchingDraftsAcrossWindows() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["a.txt", "b.txt"] { try Data("原文".utf8).write(to: root.appendingPathComponent(path)) }
        let registry = FileTabDocumentRegistry()
        let first = FileTabDocuments(), second = FileTabDocuments()
        let firstWindow = registryTestWindow("操作元"), secondWindow = registryTestWindow("別ウィンドウ")
        registry.register(files: first, window: firstWindow)
        registry.register(files: second, window: secondWindow)
        let target = SessionID(), other = SessionID()
        let clean = first.document(for: target, path: "a.txt", root: root.path)
        let dirty = second.document(for: target, path: "a.txt", root: root.path)
        let otherPath = second.document(for: target, path: "b.txt", root: root.path)
        let otherSession = second.document(for: other, path: "a.txt", root: root.path)
        for document in [clean, dirty, otherPath, otherSession] { await document.loadIfNeeded() }
        for document in [dirty, otherPath, otherSession] { document.draft = "未保存" }
        #expect(!clean.hasUnsavedChanges)
        #expect(registry.hasUnsavedChanges(for: target, path: "a.txt"))
        #expect(registry.dirtySummary(for: target, path: "a.txt") == "別ウィンドウ\n  a.txt")
        // 確認をキャンセルしている間は文書を保つ。
        #expect(!clean.invalidated && !dirty.invalidated)
        let saving = try dirty.enqueueSave(overwrite: false)
        await registry.remove(for: target, path: "a.txt")
        #expect(try await saving.value == .saved)
        #expect(try Data(contentsOf: root.appendingPathComponent("a.txt")) == Data("未保存".utf8))
        #expect(clean.invalidated && dirty.invalidated)
        #expect(first.existing(for: target, path: "a.txt") == nil)
        #expect(second.existing(for: target, path: "a.txt") == nil)
        #expect(!otherPath.invalidated && !otherSession.invalidated)
        #expect(otherPath.hasUnsavedChanges && otherSession.hasUnsavedChanges)
        #expect(!registry.hasUnsavedChanges(for: target, path: "a.txt"))
    }

    @Test("全ウィンドウの失効でも受け付け済みの保存を書き終える")
    func invalidationWaitsForQueuedSavesAcrossWindows() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = FileTabDocumentRegistry()
        let first = FileTabDocuments(), second = FileTabDocuments()
        let firstWindow = registryTestWindow("一番目"), secondWindow = registryTestWindow("二番目")
        registry.register(files: first, window: firstWindow)
        registry.register(files: second, window: secondWindow)
        let id = SessionID()
        var saves: [Task<FileTabDocument.SaveResult, Error>] = []
        var documents: [FileTabDocument] = []
        for (files, path) in [(first, "a.txt"), (second, "b.txt")] {
            try Data("元".utf8).write(to: root.appendingPathComponent(path))
            let document = files.document(for: id, path: path, root: root.path)
            await document.loadIfNeeded()
            document.draft = "一回目"
            saves.append(try document.enqueueSave(overwrite: false))
            document.draft = "二回目"
            saves.append(try document.enqueueSave(overwrite: false))
            documents.append(document)
        }
        await registry.invalidateAndWait(for: [id])
        for save in saves { #expect(try await save.value == .saved) }
        for document in documents {
            #expect(document.invalidated)
            #expect(try Data(contentsOf: root.appendingPathComponent(document.path)) == Data("二回目".utf8))
        }
    }
    @Test
    func collectsAndInvalidatesOnlyTheRequestedSessionAcrossWindows() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("原文".utf8).write(to: root.appendingPathComponent("a.txt"))
        let registry = FileTabDocumentRegistry()
        let first = FileTabDocuments(), second = FileTabDocuments()
        let firstWindow = registryTestWindow("一番目"), secondWindow = registryTestWindow("二番目")
        let target = SessionID(), other = SessionID()
        registry.register(files: first, window: firstWindow)
        registry.register(files: second, window: secondWindow)
        let firstDraft = first.document(for: target, path: "a.txt", root: root.path)
        let secondDraft = second.document(for: target, path: "a.txt", root: root.path)
        let unaffected = second.document(for: other, path: "a.txt", root: root.path)
        for document in [firstDraft, secondDraft, unaffected] {
            await document.loadIfNeeded()
            document.draft = "変更"
        }
        #expect(registry.dirtyFileNames(for: [target]) == ["a.txt", "a.txt"])
        #expect(registry.dirtySummary(for: [target]).contains("一番目"))
        #expect(registry.dirtySummary(for: [target]).contains("二番目"))
        await registry.invalidateAndWait(for: [target])
        #expect(firstDraft.invalidated && secondDraft.invalidated)
        #expect(!unaffected.invalidated)
        #expect(registry.dirtyFileNames(for: [target]).isEmpty)
        #expect(registry.dirtyFileNames() == ["a.txt"])
    }

    @Test
    func registrationDoesNotOwnWindowDrafts() {
        let registry = FileTabDocumentRegistry()
        let window = registryTestWindow("弱参照")
        weak var reference: FileTabDocuments?
        do {
            let files = FileTabDocuments()
            reference = files
            registry.register(files: files, window: window)
            registry.register(files: files, window: window)
        }
        #expect(reference == nil)
        #expect(registry.dirtyFileNames().isEmpty)
    }

    @Test
    func targetSummaryFindsDirtyDraftInOtherWindowWhenOriginIsClean() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("原文".utf8).write(to: root.appendingPathComponent("a.txt"))
        let registry = FileTabDocumentRegistry()
        let clean = FileTabDocuments(), dirty = FileTabDocuments()
        let first = registryTestWindow("操作元"), second = registryTestWindow("別ウィンドウ")
        let target = SessionID()
        registry.register(files: clean, window: first)
        registry.register(files: dirty, window: second)
        let cleanDocument = clean.document(for: target, path: "a.txt", root: root.path)
        let dirtyDocument = dirty.document(for: target, path: "a.txt", root: root.path)
        await cleanDocument.loadIfNeeded()
        await dirtyDocument.loadIfNeeded()
        dirtyDocument.draft = "別ウィンドウの変更"
        #expect(registry.dirtySummary(for: [target]) == "別ウィンドウ\n  a.txt")
    }

    @Test
    func summaryCapsFilesAndCountsOmittedWindowsWithoutEmptyHeadings() {
        let summary = FileTabDocumentRegistry.summary([
            ("一番目", ["1", "2", "3", "4"]),
            ("二番目", ["5", "6"]),
            ("三番目", ["7", "8"]),
            ("空", [])
        ])
        #expect(summary == "一番目\n  1\n  2\n  3\n  4\n二番目\n  5\nほか 3 件（2 ウィンドウ）")
    }
}

@MainActor
func registryTestWindow(_ title: String) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = title
    return window
}

func registryTestDirectory() throws -> URL {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = package.appendingPathComponent(".build/registry-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
