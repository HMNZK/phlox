import AppKit
import SwiftUI
import DesignSystem

struct FileTreeNameInput: NSViewRepresentable {
    let edit: FileTreeEdit
    let label: String
    let update: (String) -> Void
    let submit: () -> Void
    let cancel: () -> Void
    var requestsFocus = true
    var placeholder = ""

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: DSFont.bodyPointSize)
        field.textColor = NSColor(DSColor.textPrimary)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("file-tree-name-input")
        field.setAccessibilityLabel(label)
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: NSColor(DSColor.textTertiary)])
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        if field.stringValue != edit.name { field.stringValue = edit.name }
        field.setAccessibilityLabel(label)
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: NSColor(DSColor.textTertiary)])
        if requestsFocus, context.coordinator.focusedID != edit.id {
            context.coordinator.focusedID = edit.id
            DispatchQueue.main.async {
                guard let window = field.window else { context.coordinator.focusedID = nil; return }
                window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.setSelectedRange(
                    FileTreeOperations.nameSelection(edit.name, folder: edit.folder))
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FileTreeNameInput
        var focusedID: UUID?
        init(_ parent: FileTreeNameInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.update(field.stringValue)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.cancel(); return true }
            return false
        }
    }
}

struct FileTreeNameErrorView: View {
    let message: String
    @Environment(\.localizationBundle) private var bundle
    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(DSColor.attentionMark(.error))
            Text(LocalizedStringKey(message), bundle: bundle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(DSFont.auxiliary).foregroundStyle(DSColor.textPrimary)
        .padding(DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: DSRadius.m))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.m).stroke(DSColor.popoverEdge, lineWidth: DSLayout.controlBorderWidth))
        .dsShadow(.popover)
        .accessibilityLabel(Text("使えない名前", bundle: bundle) + Text(verbatim: ": ") + Text(LocalizedStringKey(message), bundle: bundle))
        .accessibilityIdentifier("file-tree-name-error")
    }
}

struct FileTreeFailureBanner: View {
    let failure: FileTreeFailure
    let dismiss: () -> Void
    @Environment(\.localizationBundle) private var bundle
    @Environment(\.locale) private var locale
    var message: String {
        String(format: AppLocalizedString.string(failure.operationKey, locale: locale, bundle: bundle),
               AppLocalizedString.string(failure.reason, locale: locale, bundle: bundle))
    }
    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(DSColor.attentionMark(.error))
            Text(verbatim: message).font(DSFont.auxiliary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").resizable().scaledToFit()
                    .frame(width: DSIconSize.fileTreeDismiss, height: DSIconSize.fileTreeDismiss)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: DSLayout.fileTreeDismissSize, height: DSLayout.fileTreeDismissSize)
            }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("閉じる", bundle: bundle))
                .accessibilityIdentifier("file-tree-dismiss-failure")
        }
        .foregroundStyle(DSColor.textPrimary).padding(DSSpacing.s)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.m))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.m).stroke(DSColor.border))
        .padding(.horizontal, DSSpacing.s).padding(.top, DSSpacing.s)
        .accessibilityIdentifier("file-tree-operation-failure")
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

struct FileTreeTrashItem: Equatable {
    let path: String
    let dirty: Bool
}

struct FileTreeTrashConfirmation {
    let entry: FileTreeEntry
    let root: String
    let count: FileTreeItemCount?
    let openItems: [FileTreeTrashItem]
    var destructive: Bool { openItems.contains(where: \.dirty) }
    func title(locale: Locale, bundle: Bundle) -> String {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        if let count {
            let number = count.limited ? localized("1,000 項目以上") : String(format: localized("%lld 項目"), count.total)
            return String(format: localized("%@ と中の %@ をゴミ箱に入れますか？"), entry.name, number)
        }
        return String(format: localized("%@ をゴミ箱に入れますか？"), entry.name)
    }
    func message(locale: Locale, bundle: Bundle) -> String {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        var parts: [String] = []
        if let count {
            parts.append(count.limited ? localized("数えるのは 1,000 項目までです。")
                         : String(format: localized("フォルダ %lld・ファイル %lld を含みます。"), count.folders, count.files))
        }
        if !openItems.isEmpty { parts.append(localized(openItems.count == 1 ? "開いているタブを閉じます。" : "開いている複数のタブを閉じます。")) }
        if destructive { parts.append(localized("未保存の変更は失われます。")) }
        else { parts.append(localized("ゴミ箱から元に戻せます。")) }
        return parts.joined(separator: locale.language.languageCode?.identifier == "ja" ? "" : " ")
    }
}

struct FileTreeTrashContent: View {
    let confirmation: FileTreeTrashConfirmation
    @Environment(\.localizationBundle) private var bundle
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            VStack(spacing: 0) {
                item(confirmation.entry.relativePath, folder: confirmation.entry.isFolder,
                     tag: confirmation.openItems.first { $0.path == confirmation.entry.relativePath })
                ForEach(confirmation.openItems.filter { $0.path != confirmation.entry.relativePath }.prefix(5), id: \.path) { file in
                    Divider()
                    item(file.path, folder: false, tag: file)
                }
                if confirmation.openItems.count > 5 {
                    Text("ほか \(confirmation.openItems.count - 5) 件", bundle: bundle)
                        .font(DSFont.meta).padding(DSSpacing.s)
                }
            }
            .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.row))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.row).stroke(DSColor.border, lineWidth: DSLayout.controlBorderWidth))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("ゴミ箱に入れるファイル", bundle: bundle))
            if confirmation.destructive {
                Text("ファイルはゴミ箱から戻せますが、保存していない変更は戻りません。保存するには、キャンセルしてタブで ⌘S を押します。", bundle: bundle)
                    .font(DSFont.meta).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(DSColor.textPrimary)
        .frame(width: DSLayout.fileTreeTrashContentWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
    private func item(_ path: String, folder: Bool, tag: FileTreeTrashItem?) -> some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: folder ? "folder" : "doc").foregroundStyle(DSColor.textSecondary)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: (path as NSString).lastPathComponent).font(DSFont.auxiliary).lineLimit(1)
                Text(verbatim: URL(fileURLWithPath: confirmation.root).lastPathComponent + " · " + FileTreeRows.parent(of: path) + "/")
                    .font(DSFont.meta).foregroundStyle(DSColor.textTertiary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
            if let tag {
                Text(tag.dirty ? "未保存の変更" : "開いているタブ", bundle: bundle)
                    .font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
                    .fixedSize()
                    .padding(.horizontal, DSSpacing.xs).padding(.vertical, DSSpacing.xxs)
                    .overlay(RoundedRectangle(cornerRadius: DSRadius.s).stroke(DSColor.popoverEdge, lineWidth: DSLayout.controlBorderWidth))
            }
        }
        .padding(.horizontal, DSSpacing.s).padding(.vertical, DSSpacing.xs)
    }
}

enum FileTreeTrashAlert {
    @MainActor static func make(_ confirmation: FileTreeTrashConfirmation, locale: Locale, bundle: Bundle) -> NSAlert {
        func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
        let alert = NSAlert()
        alert.alertStyle = confirmation.destructive ? .warning : .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = confirmation.title(locale: locale, bundle: bundle)
        alert.informativeText = confirmation.message(locale: locale, bundle: bundle)
        let host = NSHostingView(rootView: FileTreeTrashContent(confirmation: confirmation)
            .environment(\.localizationBundle, bundle).environment(\.locale, locale))
        host.setFrameSize(host.fittingSize)
        alert.accessoryView = host
        let first = alert.addButton(withTitle: localized(confirmation.destructive ? "キャンセル" : "ゴミ箱に入れる"))
        let second = alert.addButton(withTitle: localized(confirmation.destructive ? "ゴミ箱に入れる" : "キャンセル"))
        first.keyEquivalent = "\r"
        first.keyEquivalentModifierMask = []
        second.keyEquivalent = ""
        let trash = confirmation.destructive ? second : first
        trash.hasDestructiveAction = confirmation.destructive
        trash.setAccessibilityIdentifier("file-tree-confirm-trash")
        let cancel = confirmation.destructive ? first : second
        cancel.setAccessibilityIdentifier("file-tree-cancel-trash")
        let escape = NSButton(frame: .zero)
        escape.keyEquivalent = "\u{1b}"
        escape.keyEquivalentModifierMask = []
        escape.target = cancel
        escape.action = #selector(NSButton.performClick(_:))
        escape.setAccessibilityElement(false)
        alert.window.contentView?.addSubview(escape)
        let blockDelete = NSButton(frame: .zero)
        blockDelete.keyEquivalent = "\u{7f}"
        blockDelete.keyEquivalentModifierMask = .command
        blockDelete.setAccessibilityElement(false)
        alert.window.contentView?.addSubview(blockDelete)
        return alert
    }
}

struct FileTreeWindowReader: NSViewRepresentable {
    final class Reference { weak var window: NSWindow? }
    let attach: (NSWindow) -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.attach = attach; return view }
    func updateNSView(_ view: Reader, context: Context) { view.attach = attach }
    final class Reader: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { self.attach?(window) } }
        }
    }
}
