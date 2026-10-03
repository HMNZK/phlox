import AppKit
import AgentDomain
import Testing
@testable import DashboardFeature

@MainActor
struct TerminationConfirmationTests {
    @Test
    func unsavedRowsIdentifyFoldersAndOnlyRepeatProjectWithoutWindowHeadings() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["docs", "examples"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data("原文".utf8).write(to: root.appendingPathComponent("\(folder)/README.md"))
        }
        let registry = FileTabDocumentRegistry()
        let firstWindow = registryTestWindow("先頭")
        let secondWindow = registryTestWindow("次")
        let firstFiles = FileTabDocuments()
        let secondFiles = FileTabDocuments()
        let session = SessionID()
        registry.register(files: firstFiles, window: firstWindow,
                          context: { _ in UnsavedFileContext(project: "phlox-oss", session: "アザミ") }, name: { "phlox-oss" })
        registry.register(files: secondFiles, window: secondWindow,
                          context: { _ in UnsavedFileContext(project: "notes", session: "ツバキ") }, name: { "notes" })
        for folder in ["docs", "examples"] {
            let document = firstFiles.document(for: session, path: "\(folder)/README.md", root: root.path)
            await document.loadIfNeeded()
            document.draft = "変更"
        }
        let single = try #require(registry.unsavedWindows().first)
        #expect(single.files.map(\.name) == ["README.md", "README.md"])
        #expect(single.files.map(\.context) == ["phlox-oss · アザミ · docs/", "phlox-oss · アザミ · examples/"])
        let second = secondFiles.document(for: SessionID(), path: "docs/README.md", root: root.path)
        await second.loadIfNeeded()
        second.draft = "別の変更"
        let grouped = registry.unsavedWindows()
        let firstGroup = try #require(grouped.first { $0.name == "phlox-oss" })
        #expect(firstGroup.files.map(\.context) == ["アザミ · docs/", "アザミ · examples/"])
        #expect(grouped.first { $0.name == "notes" }?.files.first?.context == "ツバキ · docs/")
        #expect(registry.unsavedWindows(for: firstWindow).first?.files.first?.context == "phlox-oss · アザミ · docs/")
    }

    @Test(arguments: [false, true], [false, true])
    func unsavedAlertReportsFullCountAndWarnsForActiveEdits(terminating: Bool, editingBlock: Bool) {
        _ = NSApplication.shared
        for windowCount in [1, 2] {
            let windows = (0..<windowCount).map { index in
                UnsavedWindow(name: "ウィンドウ\(index)", files: (0..<3).map { fileIndex in
                    UnsavedFile(name: "\(fileIndex).md", context: "プロジェクト · セッション",
                        editingBlock: editingBlock && index == windowCount - 1 && fileIndex == 2)
                })
            }
            let alert = FileTabDocumentRegistry.alert(windows: windows, terminating: terminating)
            #expect(alert.messageText.contains("\(windowCount * 3) 件"))
            #expect(alert.messageText.contains(terminating ? "Phlox を終了" : "ウィンドウを閉じ"))
            #expect(alert.messageText.contains("保存せずに"))
            #expect(alert.informativeText.contains("元に戻せません"))
            #expect(alert.informativeText.contains("未確定") == editingBlock)
            #expect(alert.informativeText.contains("\(windowCount) つのウィンドウ") == (terminating && windowCount > 1))
            #expect(alert.accessoryView != nil)
        }
    }

    @Test
    func unsavedListLimitsFilesAcrossWindowsWithoutEmptyHeadings() {
        let file = UnsavedFile(name: "a.md", context: "プロジェクト · セッション", editingBlock: false)
        let windows = [
            UnsavedWindow(name: "先頭", files: Array(repeating: file, count: 4)),
            UnsavedWindow(name: "次", files: Array(repeating: file, count: 5)),
            UnsavedWindow(name: "最後", files: Array(repeating: file, count: 2)),
        ]
        let content = UnsavedChangesContent(windows: windows)
        #expect(content.count == 11)
        #expect(content.visibleWindows.map { $0.files.count } == [4, 1])
        #expect(content.visibleWindows.map(\.name) == ["先頭", "次"])
        #expect(content.omitted == "ほか 6 件（2 ウィンドウ）")
        #expect(!content.hasBlockEdit)
        let editing = UnsavedChangesContent(windows: [UnsavedWindow(name: "編集中", files: [
            UnsavedFile(name: "a.md", context: "", editingBlock: true),
        ])])
        #expect(editing.hasBlockEdit)
        #expect(editing.omitted == nil)
    }

    @Test(arguments: [false, true])
    func unsavedAlertDefaultsToCancellationAndMarksDiscard(terminating: Bool) throws {
        _ = NSApplication.shared
        let alert = FileTabDocumentRegistry.alert(windows: [UnsavedWindow(name: "確認用", files: [
            UnsavedFile(name: "a.txt", context: "プロジェクト · セッション", editingBlock: false),
        ])], terminating: terminating)
        #expect(alert.buttons.count == 2)
        let cancel = try #require(alert.buttons.first)
        let discard = try #require(alert.buttons.last)
        #expect(cancel.title == "キャンセル")
        #expect(cancel.keyEquivalent == "\r")
        #expect(!cancel.hasDestructiveAction)
        #expect(discard.title == (terminating ? "保存せず終了" : "保存せず閉じる"))
        #expect(discard.keyEquivalent == "\u{7f}")
        #expect(discard.keyEquivalentModifierMask == .command)
        #expect(discard.hasDestructiveAction)
        let escape = try #require(alert.window.contentView?.subviews.compactMap { $0 as? NSButton }
            .first { $0.keyEquivalent == "\u{1b}" })
        #expect(escape.target === cancel)
        #expect(escape.action == #selector(NSButton.performClick(_:)))
        #expect(escape.frame.isEmpty)
        #expect(!escape.isAccessibilityElement())
        alert.layout()
        #expect(alert.window.defaultButtonCell === cancel.cell)
        #expect(cancel.tag == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        #expect(discard.tag == NSApplication.ModalResponse.alertSecondButtonReturn.rawValue)
        let cancelFrame = cancel.convert(cancel.bounds, to: nil)
        let discardFrame = discard.convert(discard.bounds, to: nil)
        if cancelFrame.minX == discardFrame.minX {
            #expect(cancelFrame.minY > discardFrame.minY)
        }
    }

    @Test
    func cancellationKeepsDraftEditableAndAllowsAnotherTerminationRequest() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("原文".utf8).write(to: root.appendingPathComponent("a.txt"))
        let files = FileTabDocuments()
        let window = registryTestWindow("終了確認")
        let registry = FileTabDocumentRegistry()
        registry.register(files: files, window: window)
        let document = files.document(for: SessionID(), path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "変更"
        var confirmations = 0
        let canceled = registry.requestTermination { summary in
            #expect(registry.terminationConfirmationInProgress)
            confirmations += 1
            #expect(summary.contains("a.txt"))
            let duplicate = registry.requestTermination { _ in Issue.record("確認を重複表示した"); return true }
            #expect(!duplicate)
            return false
        }
        #expect(!canceled)
        #expect(!registry.terminationConfirmationInProgress)
        #expect(!document.invalidated)
        document.draft = "続けて編集"
        #expect(document.draft == "続けて編集")
        #expect(registry.requestTermination { _ in confirmations += 1; return true })
        #expect(!registry.terminationConfirmationInProgress)
        #expect(registry.terminationInProgress)
        #expect(confirmations == 2)
        await registry.invalidateAndWait()
        #expect(document.invalidated)
    }

    @Test
    func cleanTerminationDoesNotShowConfirmation() {
        let registry = FileTabDocumentRegistry()
        #expect(registry.requestTermination { _ in Issue.record("未保存がないのに確認した"); return false })
    }

    @Test
    func originalWindowDelegateCanRejectCloseBeforeInvalidation() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = FileTabDocumentRegistry()
        let files = FileTabDocuments()
        let window = registryTestWindow("既存delegate")
        let original = RejectingWindowDelegate()
        window.delegate = original
        registry.register(files: files, window: window)
        let document = files.document(for: SessionID(), path: "a.txt", root: root.path)
        #expect(window.delegate?.windowShouldClose?(window) == false)
        #expect(original.closeRequests == 1)
        #expect(!document.invalidated)
    }

    @Test
    func windowCloseSheetCancellationKeepsDraftEditable() async throws {
        let root = try registryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("原文".utf8).write(to: root.appendingPathComponent("a.txt"))
        let registry = FileTabDocumentRegistry()
        let files = FileTabDocuments()
        let window = registryTestWindow("ウィンドウを閉じる")
        registry.register(files: files, window: window)
        let document = files.document(for: SessionID(), path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "未保存"
        #expect(window.delegate?.windowShouldClose?(window) == false)
        let sheet = try #require(window.attachedSheet)
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        for _ in 0..<100 where window.attachedSheet != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(window.attachedSheet == nil)
        #expect(!document.invalidated)
        document.draft = "確認後も編集"
        #expect(document.draft == "確認後も編集")
        #expect(!registry.requestTermination { _ in false })
        #expect(!document.invalidated)
    }
}

@MainActor
private final class RejectingWindowDelegate: NSObject, NSWindowDelegate {
    var closeRequests = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequests += 1
        return false
    }
}
