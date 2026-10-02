import AppKit
import AgentDomain
import Observation

/// 下書きは各ウィンドウが所有し、破棄の確認だけを全ウィンドウで集約する。
@MainActor
@Observable
public final class FileTabDocumentRegistry {
    public static let shared = FileTabDocumentRegistry()

    private final class Entry {
        weak var files: FileTabDocuments?
        weak var window: NSWindow?
        let delegate: WindowDelegate

        init(files: FileTabDocuments, window: NSWindow, delegate: WindowDelegate) {
            self.files = files
            self.window = window
            self.delegate = delegate
        }
    }

    private enum Confirmation { case idle, window, termination, terminating }
    @ObservationIgnored private var entries: [Entry] = []
    @ObservationIgnored private var confirmation = Confirmation.idle
    private var changingSessions: [SessionID: Int] = [:]

    public init() {}

    func isChangingSession(_ id: SessionID) -> Bool { changingSessions[id] != nil }

    func beginWorkspaceChange(_ id: SessionID) -> Bool {
        guard !isChangingSession(id) else { return false }
        beginSessionChanges(for: [id])
        return true
    }

    func endWorkspaceChange(_ id: SessionID) { endSessionChanges(for: [id]) }

    func beginSessionChanges(for ids: Set<SessionID>) {
        for id in ids { changingSessions[id, default: 0] += 1 }
    }

    func endSessionChanges(for ids: Set<SessionID>) {
        for id in ids {
            if let count = changingSessions[id], count > 1 { changingSessions[id] = count - 1 }
            else { changingSessions[id] = nil }
        }
    }

    public var terminationInProgress: Bool {
        confirmation == .termination || confirmation == .terminating
    }

    public var terminationConfirmationInProgress: Bool { confirmation == .termination }

    public func register(files: FileTabDocuments, window: NSWindow) {
        entries.removeAll { $0.window == nil }
        if let existing = entries.first(where: { $0.window === window }) {
            existing.files = files
            existing.delegate.files = files
            if window.delegate !== existing.delegate {
                existing.delegate.original = window.delegate
                window.delegate = existing.delegate
            }
            return
        }
        let delegate = WindowDelegate(registry: self, files: files, original: window.delegate)
        entries.append(Entry(files: files, window: window, delegate: delegate))
        window.delegate = delegate
    }

    public func dirtyFileNames(for sessionIDs: Set<SessionID>? = nil) -> [String] {
        entries.flatMap { $0.files?.documents(for: sessionIDs) ?? [] }
            .filter(\.hasUnsavedChanges).map(\.fileName).sorted()
    }

    func ownsKeyWindow(_ files: FileTabDocuments) -> Bool {
        let keyEntry = entries.first { $0.files != nil && $0.window?.isKeyWindow == true }
        return keyEntry == nil || keyEntry?.files === files
    }

    func hasUnsavedChanges(for sessionID: SessionID, path: String) -> Bool {
        entries.contains { $0.files?.existing(for: sessionID, path: path)?.hasUnsavedChanges == true }
    }

    func dirtySummary(for sessionID: SessionID, path: String) -> String {
        Self.summary(entries.compactMap { entry in
            guard let window = entry.window,
                  entry.files?.existing(for: sessionID, path: path)?.hasUnsavedChanges == true else { return nil }
            return (window.title.isEmpty ? "Phlox" : window.title, [path])
        })
    }

    func remove(for sessionID: SessionID, path: String) async {
        beginSessionChanges(for: [sessionID])
        defer { endSessionChanges(for: [sessionID]) }
        let files = entries.compactMap(\.files)
        for files in files { files.existing(for: sessionID, path: path)?.invalidate() }
        for files in files { await files.remove(for: sessionID, path: path) }
    }

    public func dirtySummary(for sessionIDs: Set<SessionID>? = nil) -> String {
        let groups = entries.compactMap { entry -> (String, [String])? in
            guard let files = entry.files, let window = entry.window else { return nil }
            let names = files.documents(for: sessionIDs).filter(\.hasUnsavedChanges).map(\.path).sorted()
            guard !names.isEmpty else { return nil }
            return (window.title.isEmpty ? "Phlox" : window.title, names)
        }
        return Self.summary(groups)
    }

    static func summary(_ groups: [(String, [String])]) -> String {
        var remaining = 5
        var lines: [String] = []
        var omitted = 0
        var omittedWindows = 0
        for (title, names) in groups where !names.isEmpty {
            let shown = Array(names.prefix(remaining))
            if !shown.isEmpty {
                lines.append(title)
                lines.append(contentsOf: shown.map { "  \($0)" })
                remaining -= shown.count
            }
            if names.count > shown.count {
                omitted += names.count - shown.count
                omittedWindows += 1
            }
        }
        if omitted > 0 { lines.append("ほか \(omitted) 件（\(omittedWindows) ウィンドウ）") }
        return lines.joined(separator: "\n")
    }

    public func invalidateAndWait(for sessionIDs: Set<SessionID>? = nil) async {
        let files = entries.compactMap(\.files)
        for files in files {
            for document in files.documents(for: sessionIDs) { document.invalidate() }
        }
        for files in files { await files.invalidateAndWait(for: sessionIDs) }
    }

    func waitForPendingSaves(for sessionIDs: Set<SessionID>) async {
        let documents = entries.flatMap { $0.files?.documents(for: sessionIDs) ?? [] }
        for document in documents { await document.waitForPendingSaves() }
    }

    /// キャンセルでは終了ガードも文書も変えない。
    public func confirmTermination() -> Bool {
        requestTermination { summary in
            Self.alert(summary: summary, terminating: true).runModal() == .alertSecondButtonReturn
        }
    }

    func requestTermination(confirm: (String) -> Bool) -> Bool {
        guard confirmation == .idle else { return false }
        confirmation = .termination
        let summary = dirtySummary()
        guard summary.isEmpty || confirm(summary) else {
            confirmation = .idle
            return false
        }
        confirmation = .terminating
        return true
    }

    static func alert(summary: String, terminating: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = terminating ? "未保存のファイルがあります。終了しますか？" : "未保存のファイルがあります。閉じますか？"
        alert.informativeText = summary
        alert.icon = NSApp.applicationIconImage
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\r"
        alert.addButton(withTitle: terminating ? "保存せず終了" : "保存せず閉じる").hasDestructiveAction = true
        // Esc を直接割り当てるとキャンセルが最下段に移るため、同じボタンへ転送する。
        let escape = NSButton(frame: .zero)
        escape.keyEquivalent = "\u{1b}"
        escape.target = cancel
        escape.action = #selector(NSButton.performClick(_:))
        escape.setAccessibilityElement(false)
        alert.window.contentView?.addSubview(escape)
        return alert
    }

    private func shouldClose(_ window: NSWindow, delegate: WindowDelegate) -> Bool {
        if delegate.approved {
            delegate.approved = false
            return true
        }
        if confirmation == .terminating { return delegate.original?.windowShouldClose?(window) ?? true }
        guard confirmation == .idle else { return false }
        guard delegate.original?.windowShouldClose?(window) ?? true else { return false }
        guard let files = delegate.files else { return true }
        confirmation = .window
        let names = files.documents(for: nil).filter(\.hasUnsavedChanges).map(\.path).sorted()
        if names.isEmpty {
            finishClosing(window, files: files, delegate: delegate)
        } else {
            let alert = Self.alert(summary: Self.summary([(window.title.isEmpty ? "Phlox" : window.title, names)]), terminating: false)
            alert.beginSheetModal(for: window) { [weak self, weak window, weak delegate] response in
                guard let self else { return }
                guard response == .alertSecondButtonReturn, let window, let delegate else {
                    self.confirmation = .idle
                    return
                }
                self.finishClosing(window, files: files, delegate: delegate)
            }
        }
        return false
    }

    private func finishClosing(_ window: NSWindow, files: FileTabDocuments, delegate: WindowDelegate) {
        Task { @MainActor in
            await files.invalidateAndWait(for: nil)
            self.confirmation = .idle
            delegate.approved = true
            window.performClose(nil)
        }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        weak var registry: FileTabDocumentRegistry?
        weak var files: FileTabDocuments?
        weak var original: (any NSWindowDelegate)?
        var approved = false

        init(registry: FileTabDocumentRegistry, files: FileTabDocuments, original: (any NSWindowDelegate)?) {
            self.registry = registry
            self.files = files
            self.original = original
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            registry?.shouldClose(sender, delegate: self) ?? (original?.windowShouldClose?(sender) ?? true)
        }

        func windowWillClose(_ notification: Notification) {
            original?.windowWillClose?(notification)
            guard let window = notification.object as? NSWindow else { return }
            registry?.entries.removeAll { $0.window === window }
            window.delegate = original
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original
        }
    }
}
