import AppKit
import SwiftUI
import DesignSystem
import SessionFeature

private struct FileTabRecoveryPasteboardKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var fileTabRecoveryPasteboardName: String? {
        get { self[FileTabRecoveryPasteboardKey.self] }
        set { self[FileTabRecoveryPasteboardKey.self] = newValue }
    }
}

/// 原文の区間だけを編集し、表示用 Markdown は文書の派生物として扱う。
struct MarkdownBlockEditor: View {
    let document: FileTabDocument
    let openURL: (URL) -> OpenURLAction.Result
    @Environment(\.localizationBundle) private var localizationBundle
    var linkDestination: (URL) async -> FileLinkDestination? = { _ in nil }
    @State private var hoveredBlock: Int?
    @State private var hoveredLink: URL?
    @State private var hoveredDestination: FileLinkDestination?
    @State private var activatedLink: URL?
    @State private var selectedBlock: Int?
    @State private var selectionCrossesBlock = false
    @State private var editorRemoval = BlockEditorRemoval()
    @State private var focusedBlock: Int?
    @AccessibilityFocusState private var accessibleBlock: Int?
    @Environment(\.locale) private var locale

    init(document: FileTabDocument, openURL: @escaping (URL) -> OpenURLAction.Result,
         linkDestination: @escaping (URL) async -> FileLinkDestination? = { _ in nil },
         hoveredBlock: Int? = nil, focusedBlock: Int? = nil, hoveredLink: URL? = nil,
         hoveredDestination: FileLinkDestination? = nil, selectionCrossesBlock: Bool = false) {
        self.document = document
        self.openURL = openURL
        self.linkDestination = linkDestination
        _hoveredBlock = State(initialValue: hoveredBlock)
        _hoveredLink = State(initialValue: hoveredLink)
        _hoveredDestination = State(initialValue: hoveredDestination)
        _selectionCrossesBlock = State(initialValue: selectionCrossesBlock)
        _selectedBlock = State(initialValue: focusedBlock)
        // フォーカスの画面外描画にも実際の選択表示と同じ状態を使う。
        _snapshotFocusedBlock = State(initialValue: focusedBlock)
    }

    @State private var snapshotFocusedBlock: Int?
    private var visibleFocusedBlock: Int? { focusedBlock ?? snapshotFocusedBlock }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                    blockRow(block)
                        .accessibilityIdentifier("markdown-block-\(index)")
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColor.background)
        .background(MarkdownBlockSelectionObserver(onBoundary: { _ in }, onOutsideClick: { textView in
            guard textView.blockEditID == document.activeBlockEdit?.id else { return }
            _ = textView.synchronizeAndCommitBlockEdit()
        }))
        .overlay(alignment: .bottomLeading) {
            if selectionCrossesBlock || hoveredDestination != nil {
                Group {
                    if selectionCrossesBlock {
                        HTMLLinkDestinationLabel(text: AppLocalizedString.string(
                            "ブロックをまたいで選ぶには、ソース表示に切り替えます（⌃⌘M）", locale: locale, bundle: localizationBundle),
                            color: NSColor(DSColor.textPrimary))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                    } else if let hoveredDestination {
                        FileLinkDestinationView(destination: hoveredDestination)
                    }
                }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focusedBlock) { _, value in
            snapshotFocusedBlock = nil
            if let value { selectedBlock = value }
        }
        .onChange(of: document.activeBlockEdit?.id) { old, new in
            // 遅延行の再評価・dismantle を待たず、終了した編集欄を撤去する。
            editorRemoval.removeUnlessActive(new)
            if old != nil, new == nil, let selectedBlock {
                focusedBlock = selectedBlock
                accessibleBlock = selectedBlock
            }
        }
        .task(id: hoveredLink) {
            guard let url = hoveredLink else { hoveredDestination = nil; return }
            let destination = await linkDestination(url)
            if !Task.isCancelled, hoveredLink == url { hoveredDestination = destination }
        }
    }

    private final class BlockEditorRemoval {
        var id: UUID?
        var remove: (() -> Void)?

        func removeUnlessActive(_ activeID: UUID?) {
            guard id != activeID else { return }
            let removal = remove
            id = nil
            remove = nil
            removal?()
        }
    }

    private var displayBlocks: [MarkdownBlock] {
        var blocks = document.markdownBlocks
        if let edit = document.activeBlockEdit, !blocks.contains(where: { $0.id == edit.range.lowerBound }) {
            // 別の版でブロックが消えても、未確定の原文を入力欄に残す。
            blocks.append(MarkdownBlock(range: edit.range, original: edit.original,
                                        renderedMarkdown: "", kind: .raw))
            blocks.sort { $0.id < $1.id }
        }
        return blocks
    }

    @ViewBuilder private func blockRow(_ block: MarkdownBlock) -> some View {
        if let edit = document.activeBlockEdit, edit.range.lowerBound == block.id {
            VStack(alignment: .trailing, spacing: 4) {
                CodeTextEditor(
                    text: Binding(
                        get: {
                            guard let current = document.activeBlockEdit, current.id == edit.id else { return edit.current }
                            return current.current
                        },
                        set: { document.updateActiveBlockEdit(id: edit.id, current: $0) }
                    ),
                    blockEditID: edit.id,
                    synchronizeBlockEdit: { document.updateActiveBlockEdit(id: $0, current: $1) },
                    commitBlockEdit: { id in
                        // 保存や別ブロックへの移動で確定済みなら、古い入力欄のフォーカスを解放する。
                        guard document.activeBlockEdit?.id == id else { return true }
                        return document.commitActiveBlockEdit(id: id)
                    },
                    onBlockCommit: {
                        if document.activeBlockEdit == nil { focusBlock(selectedBlock ?? block.id) }
                    },
                    registerBlockEditor: { id, synchronize, remove in
                        guard document.activeBlockEdit?.id == id else { remove(); return }
                        editorRemoval.removeUnlessActive(id)
                        editorRemoval.id = id
                        editorRemoval.remove = remove
                        document.synchronizeActiveBlockEditor = synchronize
                    },
                    requestBlockFocus: true
                )
                .id(edit.id)
                .frame(height: Self.editorHeight(edit.current))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.m).stroke(DSColor.accent, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSColor.focusRing, lineWidth: 3).padding(-2))
                .accessibilityLabel("マークダウンのブロック編集")
                Text(LocalizedStringKey(Self.commitHint(text: edit.current, hasFailure: document.blockEditFailure != nil)),
                     bundle: localizationBundle)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(.horizontal, -10)
            .padding(.vertical, 2)
        } else {
            renderedBlock(block)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredLink == nil && (hoveredBlock == block.id || visibleFocusedBlock == block.id)
                            ? DSColor.fillSubtle : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(visibleFocusedBlock == block.id ? DSColor.accent : .clear, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(visibleFocusedBlock == block.id ? DSColor.focusRing : .clear, lineWidth: 3).padding(-2))
                .overlay(alignment: .topTrailing) {
                    if visibleFocusedBlock == block.id {
                        Text("Return で編集")
                            .font(.system(size: 10.5)).foregroundStyle(DSColor.textPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 4))
                            .offset(x: -3, y: -20)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, visibleFocusedBlock == block.id ? 20 : 0)
                .padding(.horizontal, -10)
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveredBlock = inside ? block.id : (hoveredBlock == block.id ? nil : hoveredBlock)
                }
                .overlay(MarkdownBlockSelectionObserver(onBoundary: { selectionCrossesBlock = $0 },
                    prepareClick: { prepareBlockClick(block) }, isFocused: focusedBlock == block.id,
                    onFocus: { hasFocus in
                        if hasFocus { focusedBlock = block.id }
                        else if focusedBlock == block.id { focusedBlock = nil }
                    }, onKey: { key in
                        switch key {
                        case 36, 76: beginEdit(block)
                        case 126: moveFocus(from: block.id, offset: -1)
                        case 125: moveFocus(from: block.id, offset: 1)
                        default: return false
                        }
                        return true
                    }))
                .accessibilityFocused($accessibleBlock, equals: block.id)
                .accessibilityElement(children: .contain)
                .accessibilityHint("Return で編集。上下の矢印キーでブロックを移動")
                .accessibilityAddTraits(isHeading(block) ? .isHeader : [])
                .accessibilityAction(named: "編集") { beginEdit(block) }
        }
    }

    @ViewBuilder private func renderedBlock(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .empty:
            Text("クリックして書き始める")
                .foregroundStyle(DSColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        case .raw, .frontMatter:
            Text(block.original.trimmingCharacters(in: .newlines))
                .font(DSFont.monoCaption)
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(block.kind == .frontMatter ? DSColor.textSecondary : DSColor.textTertiary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(block.kind == .frontMatter ? DSColor.codeBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(block.kind == .raw ? DSColor.border : .clear, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Text(block.kind == .frontMatter ? "front matter" : "原文")
                    .font(.system(size: 10)).foregroundStyle(DSColor.textTertiary)
                    .padding(.top, 6).padding(.trailing, 9)
            }
        case .markdown, .heading:
            RichMarkdownView(source: block.renderedMarkdown, openURL: { url in
                activatedLink = url
                return openURL(url)
            }, onLinkHover: { hoveredLink = $0 },
                             hoveredLink: hoveredLink)
        }
    }

    private func isHeading(_ block: MarkdownBlock) -> Bool {
        if case .heading = block.kind { return true }
        return false
    }

    private func beginEdit(_ block: MarkdownBlock) {
        beginEdit(range: block.range)
    }

    private func prepareBlockClick(_ block: MarkdownBlock) -> (URL?) -> Void {
        activatedLink = nil
        document.synchronizeActiveBlockEditor?()
        let version = document.version
        let previousEdit = document.activeBlockEdit
        return { link in
            if let link {
                if activatedLink != link { _ = openURL(link) }
                return
            }
            guard hoveredLink == nil else { return }
            var range = block.range
            if document.version != version {
                // 選択用の field editor へフォーカスが移ると、前の入力欄は先に確定する。
                guard document.version == version + 1, document.activeBlockEdit == nil,
                      let previousEdit, previousEdit.baseVersion == version else { return }
                range = document.rangeAfterCommitting(previousEdit, for: range)
            }
            beginEdit(range: range)
        }
    }

    private func beginEdit(range: Range<Int>) {
        if document.beginBlockEdit(range: range) {
            selectedBlock = document.activeBlockEdit?.range.lowerBound
            hoveredLink = nil
            selectionCrossesBlock = false
        }
    }

    private func focusBlock(_ id: Int) {
        let restoredID = document.markdownBlocks.first(where: { $0.id >= id })?.id
            ?? document.markdownBlocks.last?.id ?? id
        selectedBlock = restoredID
        // 確定直後の入力欄の撤去を待ち、描画ブロックへ戻す。
        DispatchQueue.main.async { focusedBlock = restoredID; accessibleBlock = restoredID }
    }

    private func moveFocus(from id: Int, offset: Int) {
        let blocks = document.markdownBlocks
        guard let index = blocks.firstIndex(where: { $0.id == id }), !blocks.isEmpty else { return }
        focusBlock(blocks[min(max(index + offset, 0), blocks.count - 1)].id)
    }

    static func editorHeight(_ text: String) -> CGFloat {
        // 区間末尾の空行は次のブロックとの区切り。入力欄の下に余白として数えない。
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let count = lines.lastIndex(where: { !$0.isEmpty }).map { $0 + 1 } ?? 1
        return min(200, max(54, CGFloat(count) * 18 + 16))
    }

    static func commitHint(text: String, hasFailure: Bool) -> String {
        if hasFailure { return "編集内容は残っています" }
        let hint = "⌘Return・Esc・ブロックの外をクリックで確定"
        return editorHeight(text) == 200 ? "中をスクロール · " + hint : hint
    }
}

/// 選択のドラッグが開始ブロックを越えたときだけ、制限を静かに案内する。
struct MarkdownBlockSelectionObserver: NSViewRepresentable {
    var onBoundary: (Bool) -> Void
    var onOutsideClick: ((CurrentLineTextView) -> Void)? = nil
    var prepareClick: (() -> ((URL?) -> Void))? = nil
    var isFocused = false
    var onFocus: ((Bool) -> Void)? = nil
    var onKey: ((UInt16) -> Bool)? = nil
    func makeNSView(context: Context) -> SelectionView {
        SelectionView(onBoundary: onBoundary, onOutsideClick: onOutsideClick, prepareClick: prepareClick)
    }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.onBoundary = onBoundary
        view.onOutsideClick = onOutsideClick
        view.prepareClick = prepareClick
        view.onFocus = onFocus
        view.onKey = onKey
        view.setFocused(isFocused)
    }
    static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stopObserving() }

    final class SelectionView: NSView {
        var onBoundary: (Bool) -> Void
        var onOutsideClick: ((CurrentLineTextView) -> Void)?
        var prepareClick: (() -> ((URL?) -> Void))?
        var onFocus: ((Bool) -> Void)?
        var onKey: ((UInt16) -> Bool)?
        private var requestsFocus = false
        private var clickAction: ((URL?) -> Void)?
        private var monitor: Any?
        private var startedInside = false
        private var dragged = false
        private var forwardingHitTest = false
        private var trackingOrigin: NSPoint?

        init(onBoundary: @escaping (Bool) -> Void, onOutsideClick: ((CurrentLineTextView) -> Void)?, prepareClick: (() -> ((URL?) -> Void))?) {
            self.onBoundary = onBoundary
            self.onOutsideClick = onOutsideClick
            self.prepareClick = prepareClick
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) は使用できません") }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .leftMouseDown,
                  !forwardingHitTest, prepareClick != nil,
                  bounds.contains(convert(point, from: superview)),
                  let target = underlyingView(at: convert(point, from: superview)) else { return nil }
            if let field = target as? NSTextField, field.isSelectable { return self }
            if let editor = target as? NSTextView, editor.isFieldEditor { return self }
            return nil
        }

        private func underlyingView(at point: NSPoint) -> NSView? {
            guard let content = window?.contentView else { return nil }
            forwardingHitTest = true
            defer { forwardingHitTest = false }
            return content.hitTest(convert(point, to: content.superview))
        }

        override func mouseDown(with event: NSEvent) {
            guard let target = underlyingView(at: convert(event.locationInWindow, from: nil)) else { return }
            trackingOrigin = event.locationInWindow
            // NSTextView の追跡ループ中も、ブロックを越えた位置だけを案内する。
            let timer = Timer(timeInterval: 0.03, target: self, selector: #selector(updateTrackingBoundary),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .eventTracking)
            target.mouseDown(with: event)
            timer.invalidate()
            updateTrackingBoundary()
            trackingOrigin = nil
            finishClick(at: event)
        }

        @objc private func updateTrackingBoundary() {
            guard startedInside, let origin = trackingOrigin, let window else { return }
            let point = window.mouseLocationOutsideOfEventStream
            guard hypot(point.x - origin.x, point.y - origin.y) > 3 else { return }
            dragged = true
            onBoundary(!bounds.contains(convert(point, from: nil)))
        }
        override var acceptsFirstResponder: Bool { onKey != nil }
        override func becomeFirstResponder() -> Bool {
            guard acceptsFirstResponder else { return false }
            DispatchQueue.main.async { [weak self] in self?.onFocus?(true) }
            return true
        }
        override func resignFirstResponder() -> Bool {
            DispatchQueue.main.async { [weak self] in self?.onFocus?(false) }
            return true
        }
        override func keyDown(with event: NSEvent) {
            if onKey?(event.keyCode) != true { super.keyDown(with: event) }
        }
        func setFocused(_ focused: Bool) {
            guard requestsFocus != focused else { return }
            requestsFocus = focused
            requestFocus()
        }
        private func requestFocus() {
            guard requestsFocus else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestsFocus, let window = self.window else { return }
                if window.firstResponder !== self { window.makeFirstResponder(self) }
            }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            requestFocus()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handleEvent(event)
                return event
            }
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged),
                name: NSTextView.didChangeSelectionNotification, object: nil)
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, editor.window === window else { return }
            editor.selectedTextAttributes[.backgroundColor] = NSColor(DSColor.textSelection)
            updateTrackingBoundary()
        }

        /// 選択可能な NSTextField が処理したクリックも、ドラッグと区別して編集へ渡す。
        func handleEvent(_ event: NSEvent) {
            guard event.window === window else { return }
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            switch event.type {
            case .leftMouseDown:
                startedInside = inside
                dragged = false
                clickAction = inside ? prepareClick?() : nil
                if inside, let textView = window?.firstResponder as? CurrentLineTextView,
                   let scrollView = textView.enclosingScrollView,
                   !scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) {
                    // 選択用の field editor へ移る前に、入力欄の変更を確定する。
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let textView else { return }
                        self?.onOutsideClick?(textView)
                    }
                }
            case .leftMouseDragged:
                if startedInside {
                    dragged = true
                    onBoundary(!inside)
                }
            case .leftMouseUp:
                finishClick(at: event)
            default: break
            }
        }

        private func finishClick(at event: NSEvent) {
            if startedInside {
                onBoundary(false)
                let selected = (window?.firstResponder as? NSTextView)?.selectedRange().length ?? 0
                if bounds.contains(convert(event.locationInWindow, from: nil)), !dragged, selected == 0 {
                    let click = clickAction
                    let link = link(at: event)
                    DispatchQueue.main.async { click?(link) }
                }
            }
            startedInside = false
            clickAction = nil
        }

        private func link(at event: NSEvent) -> URL? {
            guard let editor = window?.firstResponder as? NSTextView, let text = editor.textStorage else { return nil }
            let point = editor.convert(event.locationInWindow, from: nil)
            guard editor.bounds.contains(point) else { return nil }
            let index = editor.characterIndexForInsertion(at: point)
            guard index < text.length else { return nil }
            let value = text.attribute(.link, at: index, effectiveRange: nil)
            return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        }
        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            NotificationCenter.default.removeObserver(self, name: NSTextView.didChangeSelectionNotification, object: nil)
            monitor = nil
            startedInside = false
            dragged = false
            clickAction = nil
        }
    }
}
