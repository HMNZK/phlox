import AppKit
import SwiftUI
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("ファイルツリーの実操作経路") @MainActor
struct FileTreeInteractionTests {
    @Test("右クリックと Return で名前入力を表示し、確定後に未保存のタブを付け替える",
          arguments: [false, true], [false, true])
    func renameAfterMount(fromMenu: Bool, folder: Bool) async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".build/tree-interaction-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldPath = folder ? "docs/notes.txt" : "notes.txt"
        if folder { try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: false) }
        try Data("保存済み".utf8).write(to: root.appendingPathComponent(oldPath))
        if folder { try Data("別の文書".utf8).write(to: root.appendingPathComponent("docs/other.txt")) }
        let project = Project(name: "Test", directoryPath: root.path, createdAt: Date(), isManagedDirectory: false)
        let router = AppRouter(), files = FileTabDocuments()
        router.selectProject(project.id)
        router.tabs.updateLayout(for: project.id) { layout in
            if folder { layout.open(.file("docs/other.txt")) }
            layout.open(.file(oldPath))
        }
        router.showFilesInInspector()
        files.router = router
        let document = files.document(for: project.id, path: oldPath, root: root.path)
        await document.loadIfNeeded()
        document.draft = "未保存の本文"
        let undo = document.undoManager
        let other = folder ? files.document(for: project.id, path: "docs/other.txt", root: root.path) : nil
        if let other { await other.loadIfNeeded(); other.draft = "別の未保存" }
        let model = FileTreeModel(root: root.path, readBranch: { "" })
        await model.load("")
        if folder { await model.expand("docs") }
        let host = NSHostingView(rootView: FileTreeInspectorView(router: router, project: project,
            models: .constant([root.path: model]), files: files))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 440)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 280, height: 440),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        #expect(inputs(host).isEmpty)
        let source = folder ? "docs" : oldPath
        if fromMenu {
            let row = try #require(accessible("file-tree-row-" + source, in: host))
            let rect = (row as AnyObject).accessibilityFrame()
            let point = window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY))
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let menu = try #require(host.menu(for: event))
            let item = try #require(menu.items.first { $0.identifier?.rawValue == "file-tree-rename" || $0.title == "名前を変更" })
            menu.performActionForItem(at: menu.index(of: item))
            // メニューのアクション中に、そのメニューを所有する行を取り除かない。
            #expect(model.edit == nil)
            #expect(inputs(host).isEmpty)
        } else {
            if folder { try sendKey("\u{f700}", code: 126, window: window) }
            try sendKey("\r", code: 36, window: window)
        }
        try await settle(host)
        #expect(model.edit?.originalPath == source)
        let field = try #require(inputs(host).first)
        #expect(!field.isHidden && field.frame.width > 0)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 0, length: folder ? 4 : 5))
        try IntegrationFixImage.write(host, name: "rename-\(folder ? "folder" : "file")-\(fromMenu ? "menu" : "return")")
        editor.selectAll(nil)
        editor.insertText(folder ? "renamed" : "memo.txt", replacementRange: editor.selectedRange())
        try sendKey("\r", code: 36, window: window)
        let newPath = folder ? "renamed/notes.txt" : "memo.txt"
        let deadline = ContinuousClock.now + .seconds(5)
        while files.existing(for: project.id, path: newPath) == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.edit == nil)
        #expect(model.operationFailure == nil)
        #expect(files.existing(for: project.id, path: oldPath) == nil)
        #expect(files.existing(for: project.id, path: newPath) === document)
        #expect(document.path == newPath)
        #expect(document.draft == "未保存の本文")
        #expect(document.undoManager === undo)
        #expect(router.tabs.layout(for: project.id).selected == .file(newPath))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(newPath).path))
        #expect(try String(contentsOf: root.appendingPathComponent(newPath), encoding: .utf8) == "保存済み")
        if let other {
            #expect(files.existing(for: project.id, path: "renamed/other.txt") === other)
            #expect(other.draft == "別の未保存")
            #expect(router.tabs.layout(for: project.id).items.contains(.file("renamed/other.txt")))
        }
    }

    private func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
    private func sendKey(_ character: String, code: UInt16, window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
        window.sendEvent(event)
    }
    private func inputs(_ root: NSView) -> [NSTextField] {
        ([root] + root.subviews.flatMap(views)).compactMap { $0 as? NSTextField }
            .filter { $0.accessibilityIdentifier() == "file-tree-name-input" }
    }
    private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    private func accessible(_ identifier: String, in root: NSObject) -> NSObject? {
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
}
