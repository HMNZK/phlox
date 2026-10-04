import AppKit
import AgentDomain
import SessionFeature
import SwiftUI
import TerminalUI
import Testing
@testable import DashboardFeature

struct FilePathDisplayTests {
    @Test @MainActor
    func presentationControlsShrinkAfterTheReadablePathAtNarrowWidths() async throws {
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = try enhancedUserInterfaceValue()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: attribute)
        defer { NSApplication.shared.accessibilitySetValue(previous, forAttribute: attribute) }
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("元の段落".utf8).write(to: root.appendingPathComponent("docs/file-tree.md"))
        var document = FileTabDocument(path: "docs/file-tree.md", root: root.path)
        await document.loadIfNeeded()
        document.draft = "未保存の段落"

        func controlsWidth(at width: CGFloat) async throws -> CGFloat {
            let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
                isFocused: true, openFile: { _, _ in }).environment(\.locale, Locale(identifier: "ja")))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 200),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: width, height: 200)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let controls = try #require(accessibleFrame(named: "ファイルの表示", in: host))
            let visible = window.convertToScreen(host.bounds)
            #expect(controls.minX >= visible.minX)
            #expect(controls.maxX <= visible.maxX)
            #expect(!window.isVisible)
            return controls.width
        }

        let wide = try await controlsWidth(at: 560)
        let middle = try await controlsWidth(at: 400)
        let narrow = try await controlsWidth(at: 320)
        #expect(middle <= wide)
        #expect(narrow < wide)

        let longName = String(repeating: "長いファイル名", count: 10) + ".md"
        try Data("元の段落".utf8).write(to: root.appendingPathComponent(longName))
        document = FileTabDocument(path: longName, root: root.path)
        await document.loadIfNeeded()
        document.draft = "未保存の段落"
        _ = try await controlsWidth(at: 320)
    }

    @Test(arguments: [false, true]) @MainActor
    func selectedTabAndAddButtonRemainVisibleAtMinimumPaneWidth(includesChanges: Bool) async throws {
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = try enhancedUserInterfaceValue()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: attribute)
        defer { NSApplication.shared.accessibilitySetValue(previous, forAttribute: attribute) }
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let node = SessionNode.pty(SessionViewModel(id: SessionID(), ptyManager: MockPTYManager(), hookEvents: events,
            terminalCoordinator: TerminalCoordinator(), spawnRequest: .init(command: "/bin/sh", args: [], env: [:],
                workingDirectory: "/very/long/worktree/path/that/must/shrink/first", kind: .claudeCode, statusBootstrap: .viaHook)))
        var layout = SessionTabLayout()
        layout.open(.terminal)
        if includesChanges { layout.open(.changes) }
        layout.open(.file("docs/file-tree.md"))
        for tab in [ChildTab.file("docs/file-tree.md"), .conversation] {
            layout.select(tab)
            let host = NSHostingView(rootView: ChildTabBar(router: AppRouter(), node: node, layout: layout,
                changeCount: 4, files: FileTabDocuments(), agentConsoleWindowID: nil))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 32),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 32)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let selected = try #require(accessibleFrame(named: tab == .conversation ? "会話" : "file-tree.md", in: host))
            let add = try #require(accessibleFrame(named: "このセッションにタブを追加", in: host))
            let visible = window.convertToScreen(host.bounds)
            #expect(selected.minX >= visible.minX)
            #expect(selected.maxX <= visible.maxX)
            #expect(add.minX >= visible.minX)
            #expect(add.maxX <= visible.maxX)
            if !includesChanges {
                for title in ["会話", "ターミナル", "file-tree.md"] {
                    let frame = try #require(accessibleFrame(named: title, in: host))
                    #expect(frame.minX >= visible.minX)
                    #expect(frame.maxX <= visible.maxX)
                }
            }
            if tab == layout.tabs.last {
                #expect(add.minX >= selected.maxX)
                #expect(add.minX - selected.maxX <= 4)
            }
            #expect(!window.isVisible)
        }
    }

    @Test @MainActor
    func childTabsKeepConversationAndAddButtonBesideTheLastTabAt480And1000Points() async throws {
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = try enhancedUserInterfaceValue()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: attribute)
        defer { NSApplication.shared.accessibilitySetValue(previous, forAttribute: attribute) }
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let node = SessionNode.pty(SessionViewModel(id: SessionID(), ptyManager: MockPTYManager(), hookEvents: events,
            terminalCoordinator: TerminalCoordinator(), spawnRequest: .init(command: "/bin/sh", args: [], env: [:],
                workingDirectory: "/very/long/worktree/path/that/must/shrink/first", kind: .claudeCode, statusBootstrap: .viaHook)))
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.open(.file("docs/file-tree.md"))
        for width in [CGFloat(480), 1_000] {
            let host = NSHostingView(rootView: ChildTabBar(router: AppRouter(), node: node, layout: layout,
                changeCount: 0, files: FileTabDocuments(), agentConsoleWindowID: nil))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 32),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: width, height: 32)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let conversation = try #require(accessibleFrame(named: "会話", in: host))
            let file = try #require(accessibleFrame(named: "file-tree.md", in: host))
            let add = try #require(accessibleFrame(named: "このセッションにタブを追加", in: host))
            let visible = window.convertToScreen(host.bounds)
            #expect(conversation.minX >= visible.minX)
            #expect(add.maxX <= visible.maxX)
            #expect(add.minX >= file.maxX)
            #expect(add.minX - file.maxX <= 4)
            #expect(!window.isVisible)
        }
    }

    @Test
    func preservesWholeFoldersWhenTheAvailableWidthShrinks() {
        let path = "macos/Packages/DashboardFeature/docs/guides/file-tree.md"
        #expect(FilePathDisplay.abbreviated(path, width: 1_000) == path)
        #expect(FilePathDisplay.abbreviated(path, width: 150) == "…/guides/file-tree.md")
        #expect(FilePathDisplay.abbreviated(path, width: 100) == "…/file-tree.md")
        #expect(FilePathDisplay.abbreviated("README.md", width: 20) == "README.md")
    }

    @Test
    func minimumReadableWidthKeepsTheNearestFolderAndFileName() {
        let path = "macos/Packages/DashboardFeature/docs/file-tree.md"
        let width = FilePathDisplay.minimumReadableWidth(path)
        #expect(FilePathDisplay.abbreviated(path, width: width) == "…/docs/file-tree.md")
        #expect(FilePathDisplay.abbreviated(path, width: width - 1) == "…/file-tree.md")
        #expect(FilePathDisplay.minimumReadableWidth("file-tree.md") < width)
    }

    @Test
    func minimumReadableWidthFollowsFileNameAndFontMeasurements() {
        let path = "a/b/long-file-name.md"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let expected = ceil(("…/b/long-file-name.md" as NSString).size(withAttributes: [.font: font]).width)
        #expect(FilePathDisplay.minimumReadableWidth(path, font: font) == expected)
        #expect(FilePathDisplay.minimumReadableWidth(path) > FilePathDisplay.minimumReadableWidth("a/b/f.md"))
        #expect(FilePathDisplay.minimumReadableWidth(path, font: .monospacedSystemFont(ofSize: 18, weight: .regular)) > expected)
    }

    @Test
    func abbreviatesOnlyPathsWithinTheActualHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(FilePathDisplay.homeRelative(home + "/docs/a.md") == "~/docs/a.md")
        #expect(FilePathDisplay.homeRelative(home + "-other/docs/a.md") == home + "-other/docs/a.md")
    }

    @MainActor
    private func enhancedUserInterfaceValue() throws -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        try #require(NSApplication.shared.responds(to: selector))
        return NSApplication.shared.perform(selector, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
    }

    @MainActor
    private func accessibleFrame(named name: String, in root: NSObject) -> NSRect? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSRect? {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            let label = NSSelectorFromString("accessibilityLabel")
            if object.responds(to: label), object.perform(label)?.takeUnretainedValue() as? String == name,
               object.responds(to: NSSelectorFromString("accessibilityFrame")) {
                return (object as AnyObject).accessibilityFrame()
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let elements = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                for child in elements { if let frame = visit(child) { return frame } }
            }
            if let view = object as? NSView {
                for child in view.subviews { if let frame = visit(child) { return frame } }
            }
            return nil
        }
        return visit(root)
    }
}
