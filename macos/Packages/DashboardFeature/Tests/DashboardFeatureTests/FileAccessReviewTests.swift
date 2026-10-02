import AppKit
import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@MainActor
struct FileAccessReviewTests {
    @Test("キーではない登録ウィンドウでも要求を受け取る")
    func handlesRequestWithoutRegisteredKeyWindow() {
        let registry = FileTabDocumentRegistry()
        let files = FileTabDocuments()
        let window = registryTestWindow("設定が前面")
        registry.register(files: files, window: window)
        #expect(!window.isKeyWindow)
        #expect(registry.ownsKeyWindow(files))
    }

    @Test("変更タブは巨大な未追跡・追跡済みファイルを読み取り専用で表示する", arguments: [false, true])
    func largeChangeRemainsSelected(tracked: Bool) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q"], in: root)
        let text = String(repeating: "a", count: 1_000_001)
        try Data(text.utf8).write(to: root.appendingPathComponent("large.txt"))
        if tracked { try git(["add", "large.txt"], in: root) }
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.select("large.txt")
        #expect(model.selectedPath == "large.txt")
        if tracked {
            guard case .diff = model.detail else { Issue.record("差分が表示されていない"); return }
        } else {
            let contentMatches = model.detail == .content(text)
            #expect(contentMatches)
        }
        #expect(!model.canEdit)
        #expect(model.readOnlyMessage == "このファイルは大きすぎるため、ここでは編集できません。")
    }

    @Test("削除されたファイルはルート内のリンク親でも上書きで作り直す", arguments: [false, true])
    func overwriteRecreatesDeletedFile(linkedParent: Bool) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("parent")
        let actual = root.appendingPathComponent("actual")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: actual)
        let path = linkedParent ? "parent/a.txt" : "a.txt"
        let file = root.appendingPathComponent(path)
        try Data("元".utf8).write(to: file)
        let document = FileTabDocument(path: path, root: root.path)
        await document.loadIfNeeded()
        document.draft = "保存内容"
        try FileManager.default.removeItem(at: file)
        #expect(try await document.save() == .conflictDetected)
        try await document.overwrite()
        #expect(try Data(contentsOf: file) == Data("保存内容".utf8))
    }

    @Test("親のリンクだけ解決しファイルのリンク名を保つ")
    func openingThroughLinkedParentKeepsFileLinkName() throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("actual")
        let parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try Data("元".utf8).write(to: actual.appendingPathComponent("a.txt"))
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: actual)
        try FileManager.default.createSymbolicLink(at: actual.appendingPathComponent("file-link"), withDestinationURL: actual.appendingPathComponent("a.txt"))
        #expect(FileTabOpening.relativePath(of: parent.appendingPathComponent("file-link"), under: actual.path) == "file-link")
    }

    @Test("二個の BOM を含むファイルは未編集のままバイト一致で往復する")
    func preservesTwoBOMs() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        let bom = Data([0xef, 0xbb, 0xbf])
        let bytes = bom + bom + Data("本文\r\n".utf8)
        try bytes.write(to: file)
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        #expect(!document.hasUnsavedChanges)
        #expect(Data(document.draft.utf8) == bom + Data("本文\r\n".utf8))
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("再登録で delegate を復元し新しい delegate にも転送する")
    func registrationRestoresDelegate() {
        let registry = FileTabDocumentRegistry()
        let files = FileTabDocuments()
        let window = registryTestWindow("再登録")
        registry.register(files: files, window: window)
        let wrapper = window.delegate
        let replacement = ReviewWindowDelegate()
        window.delegate = replacement
        registry.register(files: files, window: window)
        #expect(window.delegate === wrapper)
        #expect(window.delegate?.windowShouldClose?(window) == false)
        #expect(replacement.requests == 1)
        window.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        #expect(replacement.keyNotifications == 1)
    }

    @Test("保存前にリンクがルート外へ差し替わったら保存と上書きの両方を拒否する")
    func rejectsReplacedFileAndParentSymlinks() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = root.appendingPathComponent("inside"), outside = root.appendingPathComponent("outside")
        for directory in [inside, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("元".utf8).write(to: directory.appendingPathComponent("a.txt"))
        }
        for parentLink in [false, true] {
            let link = inside.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: parentLink ? inside : inside.appendingPathComponent("a.txt"))
            let document = FileTabDocument(path: parentLink ? "link/a.txt" : "link", root: inside.path)
            await document.loadIfNeeded()
            #expect(document.isLoaded)
            document.draft = "変更"
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: parentLink ? outside : outside.appendingPathComponent("a.txt"))
            await #expect(throws: WorkingTreeServiceError.self) { try await document.save() }
            await #expect(throws: WorkingTreeServiceError.self) { try await document.overwrite() }
            #expect(try Data(contentsOf: outside.appendingPathComponent("a.txt")) == Data("元".utf8))
            try FileManager.default.removeItem(at: outside.appendingPathComponent("a.txt"))
            await #expect(throws: WorkingTreeServiceError.self) { try await document.overwrite() }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("a.txt").path))
            try Data("元".utf8).write(to: outside.appendingPathComponent("a.txt"))
            try FileManager.default.removeItem(at: link)
        }
    }

    @Test("グリッドの編集入口と子タブ破棄も共通経路を使う")
    func dashboardUsesSharedPaths() throws {
        let source = try sourceFile("Dashboard/DashboardView.swift")
        // グリッドの編集入口は共通関数で文書も作る。
        let gridStart = try #require(source.range(of: "タイルでは中身を出さない"))
        let grid = String(source[gridStart.lowerBound..<source.index(gridStart.lowerBound, offsetBy: 1500)])
        #expect(grid.contains("fileTabs.openFileTab("))
        #expect(grid.contains("hasUnsavedChanges"))
        #expect(source.contains("FileTabDocumentRegistry.shared.remove(for: sessionID, path: path)"))
        #expect(source.contains("FileTabDocumentRegistry.shared.hasUnsavedChanges(for: sessionID, path: path)"))
    }

    @Test("終了確認中の再要求はキャンセルを返す")
    func appDelegateCancelsRepeatedTerminationDuringConfirmation() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: package.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/AppDelegate.swift"), encoding: .utf8)
        #expect(app.contains("terminationConfirmationInProgress { return .terminateCancel }"))
    }

    private func sourceFile(_ path: String) throws -> String {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: package.appendingPathComponent("Sources/DashboardFeature/" + path), encoding: .utf8)
    }

    private func git(_ arguments: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git 失敗: \(String(decoding: data, as: UTF8.self))")
    }
}

@MainActor
private final class ReviewWindowDelegate: NSObject, NSWindowDelegate {
    var requests = 0
    var keyNotifications = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool { requests += 1; return false }
    func windowDidBecomeKey(_ notification: Notification) { keyNotifications += 1 }
}
