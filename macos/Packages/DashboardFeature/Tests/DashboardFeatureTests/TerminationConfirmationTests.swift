import AppKit
import AgentDomain
import Testing
@testable import DashboardFeature

@MainActor
struct TerminationConfirmationTests {
    @Test(arguments: [false, true])
    func unsavedAlertDefaultsToCancellationAndMarksDiscard(terminating: Bool) throws {
        _ = NSApplication.shared
        let alert = FileTabDocumentRegistry.alert(summary: "確認用\n  a.txt", terminating: terminating)
        #expect(alert.buttons.count == 2)
        let cancel = try #require(alert.buttons.first)
        let discard = try #require(alert.buttons.last)
        #expect(cancel.title == "キャンセル")
        #expect(cancel.keyEquivalent == "\r")
        #expect(!cancel.hasDestructiveAction)
        #expect(discard.title == (terminating ? "保存せず終了" : "保存せず閉じる"))
        #expect(discard.keyEquivalent.isEmpty)
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
