import AppKit
import AgentDomain
import Observation
import SwiftUI
import DesignSystem

public struct UnsavedFileContext {
    let project: String
    let session: String

    public init(project: String = "", session: String = "") {
        self.project = project
        self.session = session
    }

    func description(folder: String, includeProject: Bool) -> String {
        [includeProject ? project : "", session, folder.isEmpty ? "" : folder + "/"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct UnsavedFile: Equatable {
    let name: String
    let context: String
    let editingBlock: Bool
}

struct UnsavedWindow: Equatable {
    let name: String
    let files: [UnsavedFile]
}

struct UnsavedChangesContent: View {
    let windows: [UnsavedWindow]
    var locale = Locale(identifier: "ja")
    @Environment(\.localizationBundle) private var localizationBundle

    private func localized(_ key: String) -> String {
        AppLocalizedString.string(key, locale: locale, bundle: localizationBundle)
    }

    var count: Int { windows.reduce(0) { $0 + $1.files.count } }
    var hasBlockEdit: Bool { windows.contains { $0.files.contains { $0.editingBlock } } }
    var visibleWindows: [UnsavedWindow] {
        var remaining = 5
        return windows.compactMap { window in
            let files = Array(window.files.prefix(remaining))
            remaining -= files.count
            return files.isEmpty ? nil : UnsavedWindow(name: window.name, files: files)
        }
    }
    func omitted(bundle: Bundle = .main) -> String? {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        guard count > 5 else { return nil }
        var remaining = 5
        var hiddenWindows = 0
        for window in windows {
            let shown = min(remaining, window.files.count)
            remaining -= shown
            if shown < window.files.count { hiddenWindows += 1 }
        }
        let files = String(format: localized("ほか %lld 件"), count - 5)
        guard windows.count > 1 else { return files }
        let windowCount = String(format: localized("%lld ウィンドウ"), hiddenWindows)
        return String(format: localized("%@（%@）"), files, windowCount)
    }

    var textSummary: String {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale) }
        var lines = visibleWindows.flatMap { window in
            [window.name] + window.files.map { file in
                "  " + file.name + (file.editingBlock ? localized("（編集中）") : "")
            }
        }
        if let omitted = omitted() { lines.append(omitted) }
        if hasBlockEdit { lines.append(localized("編集中のブロックの内容も保存されていません。")) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleWindows.enumerated()), id: \.offset) { index, window in
                    if windows.count > 1 {
                        Text(verbatim: String(format: localized("ウィンドウ %lld · %@"), index + 1, window.name))
                            .font(DSFont.meta.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.chip)
                    }
                    ForEach(Array(window.files.enumerated()), id: \.offset) { fileIndex, file in
                        if fileIndex > 0 { Rectangle().fill(DSColor.textPrimary.opacity(0.08)).frame(height: 1) }
                        HStack(alignment: .center, spacing: DSSpacing.s) {
                            Image(systemName: "doc").foregroundStyle(DSColor.textTertiary)
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                HStack(spacing: DSSpacing.s) {
                                    Text(verbatim: file.name).font(DSFont.auxiliary).lineLimit(1)
                                    Spacer(minLength: DSSpacing.xs)
                                }
                                Text(verbatim: file.context).font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                            if file.editingBlock {
                                Text(verbatim: localized("編集中のブロック"))
                                    .font(DSFont.meta)
                                    .padding(.horizontal, DSSpacing.xs)
                                    .frame(height: DSSpacing.l)
                                    .overlay(RoundedRectangle(cornerRadius: DSRadius.s).stroke(DSColor.border))
                                    .fixedSize()
                            }
                        }
                        .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.xs)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel([file.name, file.context, file.editingBlock ? localized("編集中のブロックあり") : ""].filter { !$0.isEmpty }.joined(separator: ", "))
                    }
                }
                if let omitted = omitted(bundle: localizationBundle) {
                    Rectangle().fill(DSColor.textPrimary.opacity(0.08)).frame(height: 1)
                    Text(omitted).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.s + DSSpacing.xxs)
                }
            }
            .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.row))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.row).stroke(DSColor.border, lineWidth: 0.5))
            .accessibilityLabel(String(format: localized("未保存のファイル %lld 件"), count))
            Text(verbatim: localized("保存するには、キャンセルしてそれぞれのタブで ⌘S を押します。"))
                .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(DSColor.textPrimary)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 下書きは各ウィンドウが所有し、破棄の確認だけを全ウィンドウで集約する。
@MainActor
@Observable
public final class FileTabDocumentRegistry {
    public static let shared = FileTabDocumentRegistry()

    private final class Entry {
        weak var files: FileTabDocuments?
        weak var window: NSWindow?
        let delegate: WindowDelegate
        var context: (SessionID) -> UnsavedFileContext
        var name: () -> String
        var locale: Locale

        init(files: FileTabDocuments, window: NSWindow, delegate: WindowDelegate, context: @escaping (SessionID) -> UnsavedFileContext, name: @escaping () -> String, locale: Locale) {
            self.files = files
            self.window = window
            self.delegate = delegate
            self.context = context
            self.name = name
            self.locale = locale
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

    public func register(files: FileTabDocuments, window: NSWindow, context: @escaping (SessionID) -> UnsavedFileContext = { _ in UnsavedFileContext() }, name: @escaping () -> String = { "" }, locale: Locale = Locale(identifier: "ja")) {
        entries.removeAll { $0.window == nil }
        if let existing = entries.first(where: { $0.window === window }) {
            existing.files = files
            existing.context = context
            existing.name = name
            existing.locale = locale
            existing.delegate.files = files
            if !fileTabWindowDelegateChainContains(existing.delegate, in: window.delegate) {
                existing.delegate.original = window.delegate
                window.delegate = existing.delegate
            }
            return
        }
        let delegate = WindowDelegate(registry: self, files: files, original: window.delegate)
        entries.append(Entry(files: files, window: window, delegate: delegate, context: context, name: name, locale: locale))
        window.delegate = delegate
    }

    public func dirtyFileNames(for sessionIDs: Set<SessionID>? = nil) -> [String] {
        entries.flatMap { $0.files?.documents(for: sessionIDs) ?? [] }
            .filter(\.hasUnsavedChanges).map(\.unsavedDisplayName).sorted()
    }

    func ownsKeyWindow(_ files: FileTabDocuments) -> Bool {
        let keyEntry = entries.first { $0.files != nil && $0.window?.isKeyWindow == true }
        return keyEntry == nil || keyEntry?.files === files
    }

    func hasUnsavedChanges(for sessionID: SessionID, path: String) -> Bool {
        entries.contains { $0.files?.existing(for: sessionID, path: path)?.hasUnsavedChanges == true }
    }

    func dirtySummary(for sessionID: SessionID, path: String) -> String {
        dirtySummary(for: [sessionID], path: path)
    }

    func remove(for sessionID: SessionID, path: String) async {
        beginSessionChanges(for: [sessionID])
        defer { endSessionChanges(for: [sessionID]) }
        let files = entries.compactMap(\.files)
        for files in files { files.existing(for: sessionID, path: path)?.invalidate() }
        for files in files { await files.remove(for: sessionID, path: path) }
    }

    public func dirtySummary(for sessionIDs: Set<SessionID>? = nil) -> String {
        dirtySummary(for: sessionIDs, path: nil)
    }

    private func dirtySummary(for sessionIDs: Set<SessionID>?, path: String?) -> String {
        let windows = entries.compactMap { entry -> UnsavedWindow? in
            guard let files = entry.files, let window = entry.window else { return nil }
            let dirty = files.documents(for: sessionIDs)
                .filter { $0.hasUnsavedChanges && (path == nil || $0.path == path) }
                .sorted { $0.path < $1.path }
            guard !dirty.isEmpty else { return nil }
            return UnsavedWindow(name: window.title.isEmpty ? "Phlox" : window.title,
                files: dirty.map { UnsavedFile(name: $0.path, context: "", editingBlock: $0.activeBlockEdit != nil) })
        }
        return UnsavedChangesContent(windows: windows,
            locale: entries.first { $0.window?.isKeyWindow == true }?.locale ?? entries.first?.locale ?? Locale(identifier: "ja")).textSummary
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
        requestTermination {
            Self.alert(windows: unsavedWindows(), terminating: true, locale: entries.first { $0.window?.isKeyWindow == true }?.locale ?? entries.first?.locale ?? Locale(identifier: "ja")).runModal() == .alertSecondButtonReturn
        }
    }

    func unsavedWindows(for window: NSWindow? = nil) -> [UnsavedWindow] {
        let ordered = NSApp.orderedWindows
        let relevant = entries.filter { (window == nil || $0.window === window) && $0.files?.documents(for: nil).contains(where: \.hasUnsavedChanges) == true }
        return relevant
            .sorted { first, second in
                (ordered.firstIndex { $0 === first.window } ?? Int.max) < (ordered.firstIndex { $0 === second.window } ?? Int.max)
            }.compactMap { entry in
                guard let files = entry.files, let window = entry.window else { return nil }
                let dirty = files.documentEntries().filter { $0.1.hasUnsavedChanges }
                    .sorted { $0.1.path < $1.1.path }.map { id, document in
                        let folder = (document.path as NSString).deletingLastPathComponent
                        let context = entry.context(id)
                        let fileContext = UnsavedFileContext(project: context.project.isEmpty ? URL(fileURLWithPath: document.root).lastPathComponent : context.project, session: context.session)
                        return UnsavedFile(name: document.fileName,
                            context: fileContext.description(folder: folder, includeProject: relevant.count == 1),
                            editingBlock: document.activeBlockEdit != nil)
                    }
                let name = entry.name()
                return dirty.isEmpty ? nil : UnsavedWindow(name: name.isEmpty ? (window.title.isEmpty ? "Phlox" : window.title) : name, files: dirty)
            }
    }

    func requestTermination(confirm: () -> Bool) -> Bool {
        guard confirmation == .idle else { return false }
        confirmation = .termination
        guard !entries.contains(where: { $0.files?.documents().contains(where: \.hasUnsavedChanges) == true }) || confirm() else {
            confirmation = .idle
            return false
        }
        confirmation = .terminating
        return true
    }

    static func alert(windows: [UnsavedWindow], terminating: Bool, locale: Locale = Locale(identifier: "ja"), bundle: Bundle = .main) -> NSAlert {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        let content = UnsavedChangesContent(windows: windows, locale: locale)
        let alert = NSAlert()
        alert.messageText = String(format: localized(terminating
            ? "未保存のファイル %lld 件を保存せずに Phlox を終了しますか？"
            : "未保存のファイル %lld 件を保存せずにウィンドウを閉じますか？"), content.count)
        if terminating, windows.count > 1 {
            alert.informativeText = String(format: localized("%lld つのウィンドウに保存していない変更があります。変更は失われ、元に戻せません。"), windows.count)
            if content.hasBlockEdit { alert.informativeText += " " + localized("編集中（未確定）のブロックも含まれます。") }
        } else {
            alert.informativeText = content.hasBlockEdit
                ? localized("保存していない変更は、編集中（未確定）のブロックも含めて失われます。元に戻せません。")
                : localized("保存していない変更は失われ、元に戻せません。")
        }
        let accessory = NSHostingView(rootView: content.environment(\.localizationBundle, bundle))
        accessory.setFrameSize(accessory.fittingSize)
        alert.accessoryView = accessory
        alert.icon = NSApp.applicationIconImage
        let cancel = alert.addButton(withTitle: localized("キャンセル"))
        cancel.keyEquivalent = "\r"
        let discard = alert.addButton(withTitle: localized(terminating ? "保存せず終了" : "保存せず閉じる"))
        discard.hasDestructiveAction = true
        discard.keyEquivalent = "\u{7f}"
        discard.keyEquivalentModifierMask = .command
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
        let names = files.documents(for: nil).filter(\.hasUnsavedChanges).map(\.unsavedDisplayName).sorted()
        if names.isEmpty {
            finishClosing(window, files: files, delegate: delegate)
        } else {
            let alert = Self.alert(windows: unsavedWindows(for: window), terminating: false, locale: entries.first { $0.window === window }?.locale ?? Locale(identifier: "ja"))
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

    private final class WindowDelegate: NSObject, FileTabWindowDelegateChain {
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
