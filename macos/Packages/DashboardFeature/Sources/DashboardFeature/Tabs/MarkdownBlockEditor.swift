import AppKit
import SwiftUI
import DesignSystem
import SessionFeature

/// 原文の区間だけを編集し、表示用 Markdown は文書の派生物として扱う。
struct MarkdownBlockEditor: View {
    let document: FileTabDocument
    let openURL: (URL) -> OpenURLAction.Result
    var linkDestination: (URL) async -> String? = { _ in nil }
    @State private var hoveredBlock: Int?
    @State private var hoveredLink: URL?
    @State private var hoveredDestination: String?
    @State private var selectedBlock: Int?
    @State private var selectionCrossesBlock = false
    @State private var editorRemoval = BlockEditorRemoval()
    @FocusState private var focusedBlock: Int?
    @AccessibilityFocusState private var accessibleBlock: Int?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                    blockRow(block)
                        .accessibilityIdentifier("markdown-block-\(index)")
                }
            }
            .padding(16)
        }
        .background(DSColor.background)
        .background(MarkdownBlockSelectionObserver(onBoundary: { _ in }, onOutsideClick: { textView in
            guard textView.blockEditID == document.activeBlockEdit?.id else { return }
            _ = textView.synchronizeAndCommitBlockEdit()
        }))
        .overlay(alignment: .bottomLeading) {
            if let message = statusMessage {
                HTMLLinkDestinationLabel(text: message, color: NSColor(DSColor.textSecondary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focusedBlock) { _, value in
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
            hoveredDestination = nil
            guard let url = hoveredLink else { return }
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

    private var statusMessage: String? {
        if selectionCrossesBlock {
            return "ブロックをまたいで選ぶには、ソース表示に切り替えます（⌃⌘M）"
        }
        return hoveredDestination
    }

    @ViewBuilder private func blockRow(_ block: MarkdownBlock) -> some View {
        if let edit = document.activeBlockEdit, edit.range.lowerBound == block.id {
            VStack(alignment: .leading, spacing: 6) {
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DSColor.accent, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSColor.focusRing, lineWidth: 3).padding(-2))
                .accessibilityLabel("マークダウンのブロック編集")
                if let reason = document.blockEditFailure {
                    Text(reason)
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textSecondary)
                    HStack {
                        Button("編集を破棄") { document.discardActiveBlockEdit(id: edit.id) }
                        Button("ソースで開く") { _ = document.openSourceDiscardingBlockEdit(id: edit.id) }
                            .help("編集中の内容をクリップボードへコピーしてからソース表示へ切り替えます")
                    }
                } else {
                    Text("⌘Return・Esc・ブロックの外をクリックで確定")
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
        } else {
            renderedBlock(block)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredLink == nil && (hoveredBlock == block.id || focusedBlock == block.id)
                            ? DSColor.fillSubtle : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(focusedBlock == block.id ? DSColor.accent : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveredBlock = inside ? block.id : (hoveredBlock == block.id ? nil : hoveredBlock)
                }
                .background(MarkdownBlockSelectionObserver { selectionCrossesBlock = $0 })
                .focusable(document.activeBlockEdit == nil)
                .focusEffectDisabled()
                .focused($focusedBlock, equals: block.id)
                .accessibilityFocused($accessibleBlock, equals: block.id)
                .accessibilityElement(children: .contain)
                .accessibilityHint("Return で編集。上下の矢印キーでブロックを移動")
                .accessibilityAddTraits(isHeading(block) ? .isHeader : [])
                .accessibilityAction(named: "編集") { beginEdit(block) }
                .onKeyPress(.return) { beginEdit(block); return .handled }
                .onKeyPress(.upArrow) { moveFocus(from: block.id, offset: -1); return .handled }
                .onKeyPress(.downArrow) { moveFocus(from: block.id, offset: 1); return .handled }
        }
    }

    @ViewBuilder private func renderedBlock(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .empty:
            Text("クリックして書き始める")
                .foregroundStyle(DSColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .onTapGesture { beginEdit(block) }
        case .raw, .frontMatter:
            VStack(alignment: .trailing, spacing: 4) {
                Text(block.kind == .frontMatter ? "front matter" : "原文")
                    .font(.system(size: 10))
                Text(block.original)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(DSColor.textTertiary)
            .padding(8)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 6))
            .onTapGesture { beginEdit(block) }
        case .markdown, .heading:
            RichMarkdownView(source: block.renderedMarkdown, openURL: openURL,
                             blockClick: { beginEdit(block) }, onLinkHover: { hoveredLink = $0 })
        }
    }

    private func isHeading(_ block: MarkdownBlock) -> Bool {
        if case .heading = block.kind { return true }
        return false
    }

    private func beginEdit(_ block: MarkdownBlock) {
        if document.beginBlockEdit(range: block.range) {
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
        let count = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        return min(200, max(54, CGFloat(count) * 18 + 12))
    }
}

/// 選択のドラッグが開始ブロックを越えたときだけ、制限を静かに案内する。
private struct MarkdownBlockSelectionObserver: NSViewRepresentable {
    var onBoundary: (Bool) -> Void
    var onOutsideClick: ((CurrentLineTextView) -> Void)? = nil
    func makeNSView(context: Context) -> SelectionView {
        SelectionView(onBoundary: onBoundary, onOutsideClick: onOutsideClick)
    }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.onBoundary = onBoundary
        view.onOutsideClick = onOutsideClick
    }
    static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stopObserving() }

    final class SelectionView: NSView {
        var onBoundary: (Bool) -> Void
        var onOutsideClick: ((CurrentLineTextView) -> Void)?
        private var monitor: Any?
        private var startedInside = false

        init(onBoundary: @escaping (Bool) -> Void, onOutsideClick: ((CurrentLineTextView) -> Void)?) {
            self.onBoundary = onBoundary
            self.onOutsideClick = onOutsideClick
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) は使用できません") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let inside = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                switch event.type {
                case .leftMouseDown:
                    self.startedInside = inside
                    if inside, let textView = self.window?.firstResponder as? CurrentLineTextView,
                       let scrollView = textView.enclosingScrollView,
                       !scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) {
                        // 別ブロックのクリック処理を先に行わせ、置換前の区間を正しく調整する。
                        DispatchQueue.main.async { [weak self, weak textView] in
                            guard let textView else { return }
                            self?.onOutsideClick?(textView)
                        }
                    }
                case .leftMouseDragged:
                    if self.startedInside { self.onBoundary(!inside) }
                case .leftMouseUp:
                    if self.startedInside { self.onBoundary(false) }
                    self.startedInside = false
                default: break
                }
                return event
            }
        }
        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            startedInside = false
        }
    }
}
