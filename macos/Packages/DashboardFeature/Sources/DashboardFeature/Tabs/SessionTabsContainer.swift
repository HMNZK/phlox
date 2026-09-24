import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

/// 単体表示の中央（02 C）。上段のタブ列、選択中セッションの子タブ列、子タブの中身（左右分割可）。
/// 会話の中身と、セッション未選択時の開始画面は `conversation` が描く。
struct SessionTabsContainer<Conversation: View>: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let terminals: SessionTerminalStore?
    let commonTerminal: TerminalPanelSession?
    let editorPanel: EditorPanelCoordinator
    let files: FileTabDocuments
    let agentConsoleWindowID: String?
    @ViewBuilder let conversation: () -> Conversation

    var body: some View {
        VStack(spacing: 0) {
            SessionTabBar(
                viewModel: viewModel,
                router: router,
                sessions: tabSessions,
                projectID: tabProjectID,
                hasCommonTerminal: commonTerminal != nil,
                agentConsoleWindowID: agentConsoleWindowID
            )
            separator
            if router.commonTerminalSelected, let commonTerminal {
                // AppKit の端末はオーバーレイではなくレイアウトの中に置く（ADR 0136）。
                TerminalPanelView(panel: commonTerminal, showsHeader: false)
            } else if let id = router.selectedSession, let node = viewModel.sessionNode(id: id) {
                let layout = router.tabs.layout(for: id)
                ChildTabBar(
                    router: router,
                    node: node,
                    layout: layout,
                    changeCount: editorPanel.viewModel.changes.count,
                    files: files,
                    agentConsoleWindowID: agentConsoleWindowID
                )
                separator
                ChildTabPanes(
                    router: router,
                    node: node,
                    layout: layout,
                    content: { tab in pane(tab, node: node) }
                )
            } else {
                conversation()
            }
        }
    }

    /// 上段に並べるプロジェクト：選択中セッションのプロジェクト、無ければ選択中のプロジェクト。
    private var tabProjectID: ProjectID? {
        router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID } ?? router.selectedProjectID
    }

    private var tabSessions: [SessionNode] {
        viewModel.numberedTabSessionIDs(router: router).compactMap(viewModel.sessionNode(id:))
    }

    @ViewBuilder
    private func pane(_ tab: ChildTab, node: SessionNode) -> some View {
        switch tab {
        case .conversation:
            conversation()
        case .terminal:
            if let terminals {
                TerminalPanelView(panel: terminals.terminal(for: node.id, workingDirectory: node.rawWorkspacePath), showsHeader: false)
                    .id(node.id)
            } else {
                ContentUnavailableView("ターミナルを準備しています", systemImage: "terminal")
            }
        case .changes:
            EditorPanelView(viewModel: editorPanel.viewModel) { path in
                router.tabs.updateLayout(for: node.id) { $0.open(.file(path)) }
            }
        case .file(let path):
            FileTabView(document: files.document(for: node.id, path: path, workingDirectory: node.rawWorkspacePath))
                .id("\(node.id)-\(path)")
        }
    }

    private var separator: some View {
        Rectangle().fill(DSColor.separator).frame(height: 1)
    }
}

// MARK: - Child tab bar

/// 下段の子タブ列（02 C1）。会話・ターミナル・変更 N・ファイル、＋、右端に worktree のパス。
struct ChildTabBar: View {
    @Bindable var router: AppRouter
    let node: SessionNode
    let layout: SessionTabLayout
    let changeCount: Int
    let files: FileTabDocuments
    let agentConsoleWindowID: String?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xxs) {
                    ForEach(layout.tabs, id: \.self) { tab in
                        ChildTabButton(
                            tab: tab,
                            glyph: glyph(for: tab),
                            title: title(for: tab),
                            isShown: layout.isShown(tab),
                            isSelected: layout.selected == tab,
                            isDirty: isDirty(tab),
                            onSelect: { router.tabs.updateLayout(for: node.id) { $0.select(tab) } },
                            onClose: { router.tabRequest = .closeChild(node.id, tab) }
                        )
                    }
                    // 02 C1: ＋は子タブの直後。
                    addButton
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DSSpacing.m)
            Text(verbatim: abbreviatedPath)
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(node.rawWorkspacePath)
                .accessibilityLabel(Text("worktree: \(node.rawWorkspacePath)"))
        }
        .padding(.horizontal, 10)
        .frame(height: DSLayout.childTabBarHeight)
        .background(DSColor.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("このセッションのタブ"))
    }

    private var addButton: some View {
        Button {
            router.newTabChooserPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text("このセッションにタブを追加"))
        .accessibilityLabel(Text("このセッションにタブを追加"))
        .popover(isPresented: $router.newTabChooserPresented, arrowEdge: .bottom) {
            NewTabChooser(router: router, node: node, agentConsoleWindowID: agentConsoleWindowID)
                // popover は画面のロケールを引き継がないので渡し直す（アプリ内の言語設定）。
                .environment(\.locale, locale)
        }
    }

    private var abbreviatedPath: String {
        node.workspacePath
    }

    private func glyph(for tab: ChildTab) -> String {
        switch tab {
        case .conversation: node.agentDescriptor.tabInitials
        case .terminal: ">_"
        case .changes: "±"
        case .file: "{}"
        }
    }

    /// 文言は画面のロケール（アプリ内の言語設定）で引くため Text で返す。
    private func title(for tab: ChildTab) -> Text {
        switch tab {
        case .conversation: Text("会話")
        case .terminal: Text("ターミナル")
        case .changes: changeCount > 0 ? Text("変更 \(changeCount)") : Text("tab.changes")
        case .file(let path): Text(verbatim: (path as NSString).lastPathComponent)
        }
    }

    private func isDirty(_ tab: ChildTab) -> Bool {
        guard case .file(let path) = tab else { return false }
        return files.existing(for: node.id, path: path)?.isDirty ?? false
    }
}

private struct ChildTabButton: View {
    let tab: ChildTab
    let glyph: String
    let title: Text
    let isShown: Bool
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        // PhloxTabs.dc.html:205: 高さ 24、padding 0 10、間 6、記号は 10/700 の等幅。
        HStack(spacing: 6) {
            Text(verbatim: glyph)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DSColor.textTertiary)
            title
                .font(DSFont.auxiliary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isShown ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(1)
            if tab != .conversation {
                closeAccessory
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(isShown ? DSColor.fillSelected : Color.clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .draggable(tab.dragPayload) {
            title.font(DSFont.auxiliary).padding(DSSpacing.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDirty ? Text("\(title)、未保存") : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: Text("タブを閉じる"), onClose)
    }

    /// 未保存のファイルは ✕ の代わりに点。ホバーで ✕ に戻る（02 のタブ規則）。
    @ViewBuilder
    private var closeAccessory: some View {
        if isDirty, !isHovering {
            Circle()
                .fill(DSColor.textPrimary)
                .frame(width: 6, height: 6)
                .frame(width: 14, height: 14)
        } else {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isHovering ? 1 : 0)
            .help(Text("タブを閉じる"))
        }
    }
}

extension ChildTab {
    /// ドラッグで運ぶ文字列。アプリ内でだけ使う。
    var dragPayload: String {
        switch self {
        case .conversation: "phlox-tab:conversation"
        case .terminal: "phlox-tab:terminal"
        case .changes: "phlox-tab:changes"
        case .file(let path): "phlox-tab:file:\(path)"
        }
    }

    init?(dragPayload: String) {
        switch dragPayload {
        case "phlox-tab:conversation": self = .conversation
        case "phlox-tab:terminal": self = .terminal
        case "phlox-tab:changes": self = .changes
        default:
            let prefix = "phlox-tab:file:"
            guard dragPayload.hasPrefix(prefix) else { return nil }
            self = .file(String(dragPayload.dropFirst(prefix.count)))
        }
    }
}

// MARK: - New tab chooser (C4)

/// 「＋」と ⌘T で開く選択肢。↑↓ で移動、↩ で開く。
private struct NewTabChooser: View {
    @Bindable var router: AppRouter
    let node: SessionNode
    let agentConsoleWindowID: String?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @FocusState private var focused: Item?

    enum Item: Hashable, CaseIterable {
        case conversation, terminal, changes, file, agentConsole
    }

    private var items: [Item] {
        Item.allCases.filter { $0 != .agentConsole || agentConsoleWindowID != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("このセッションに開く")
                .font(DSFont.meta.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, DSSpacing.xs)
            ForEach(items, id: \.self) { item in
                row(item)
                    .focusable()
                    .focused($focused, equals: item)
                    .focusEffectDisabled()
            }
        }
        .padding(DSSpacing.xs)
        .frame(width: 300)
        .background(DSColor.popoverBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("新しいタブ（⌘T）"))
        .onAppear { focused = items.first }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.return) {
            guard let focused else { return .ignored }
            open(focused)
            return .handled
        }
    }

    private func row(_ item: Item) -> some View {
        let isFocused = focused == item
        return HStack(spacing: DSSpacing.s) {
            Text(verbatim: glyph(item))
                .font(DSFont.monoCaption)
                .foregroundStyle(isFocused ? Color.white : DSColor.textTertiary)
                .frame(width: 22, alignment: .leading)
            title(item)
                .font(DSFont.row)
                .foregroundStyle(isFocused ? Color.white : DSColor.textPrimary)
            Spacer(minLength: DSSpacing.s)
            Text(verbatim: shortcut(item))
                .font(DSFont.meta)
                .foregroundStyle(isFocused ? Color.white.opacity(0.85) : DSColor.textTertiary)
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(height: 26)
        .background(isFocused ? DSColor.accentFill : Color.clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .onHover { if $0 { focused = item } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open(item) }
    }

    private func glyph(_ item: Item) -> String {
        switch item {
        case .conversation: node.agentDescriptor.tabInitials
        case .terminal: ">_"
        case .changes: "±"
        case .file: "{}"
        case .agentConsole: "⚙"
        }
    }

    private func title(_ item: Item) -> Text {
        switch item {
        case .conversation: Text("会話（このセッション）")
        case .terminal: Text("ターミナル（この worktree で）")
        case .changes: Text("変更一覧 · 差分")
        case .file: Text("ファイルを開く…")
        case .agentConsole: Text("エージェント管理")
        }
    }

    private func shortcut(_ item: Item) -> String {
        switch item {
        case .terminal: "⌃⌘T"
        case .changes: ""
        case .file: "⌘P"
        case .agentConsole: AppLocalizedString.string("共通 ⇧⌘,", locale: locale)
        case .conversation: ""
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let index = items.firstIndex { $0 == focused } ?? -offset
        focused = items[min(max(index + offset, 0), items.count - 1)]
        return .handled
    }

    private func open(_ item: Item) {
        router.newTabChooserPresented = false
        switch item {
        case .conversation: router.openChildTab(.conversation)
        case .terminal: router.openChildTab(.terminal)
        case .changes: router.openChildTab(.changes)
        case .file: router.tabRequest = .openFile(node.id)
        case .agentConsole:
            if let agentConsoleWindowID { openWindow(id: agentConsoleWindowID) }
        }
    }
}

// MARK: - Panes (split)

/// 子タブの中身。分割中は左右に並べ、区切りをドラッグで動かせる（既定 50:50・最小 320pt）。
/// 子タブを右半分へドラッグすると右に分割して開く（C6）。
private struct ChildTabPanes<Content: View>: View {
    @Bindable var router: AppRouter
    let node: SessionNode
    let layout: SessionTabLayout
    @ViewBuilder let content: (ChildTab) -> Content

    @State private var dragFraction: Double?
    @State private var fractionAtDragStart = 0.5
    @State private var isDropTargeted = false

    static var minimumPaneWidth: CGFloat { 320 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            if let right = layout.right, width >= Self.minimumPaneWidth * 2 + 1 {
                let leftWidth = Self.leftWidth(fraction: dragFraction ?? layout.splitFraction, totalWidth: width)
                HStack(spacing: 0) {
                    focusablePane(layout.left, isFocused: !layout.focusesRight)
                        .frame(width: leftWidth)
                    Rectangle().fill(DSColor.separator).frame(width: 1)
                    focusablePane(right, isFocused: layout.focusesRight)
                }
                .overlay(alignment: .topLeading) {
                    ResizeGripView(
                        hitWidth: DSLayout.dividerHitWidth,
                        onChanged: { value in
                            if dragFraction == nil { fractionAtDragStart = leftWidth / width }
                            dragFraction = fractionAtDragStart + value.translation.width / width
                        },
                        onEnded: {
                            let committed = Self.leftWidth(fraction: dragFraction ?? layout.splitFraction, totalWidth: width) / width
                            router.tabs.updateLayout(for: node.id) { $0.splitFraction = committed }
                            dragFraction = nil
                        },
                        onDoubleClick: { router.tabs.updateLayout(for: node.id) { $0.splitFraction = 0.5 } }
                    )
                    .offset(x: leftWidth + 0.5 - DSLayout.dividerHitWidth / 2)
                }
            } else {
                // 分割が入らない幅では操作中のタブだけを出す。
                content(layout.selected)
                    .frame(width: width, height: geometry.size.height)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let tab = items.first.flatMap(ChildTab.init(dragPayload:)), layout.tabs.contains(tab) else { return false }
            router.tabs.updateLayout(for: node.id) { $0.splitRight(tab) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay(alignment: .trailing) {
            if isDropTargeted {
                GeometryReader { geometry in
                    // PhloxTabs.dc.html:114: 面 --selText、内側 2pt の accent、12/600 accentInk、角丸 8。
                    RoundedRectangle(cornerRadius: DSRadius.m)
                        .fill(DSColor.focusRing)
                        .overlay {
                            RoundedRectangle(cornerRadius: DSRadius.m).strokeBorder(DSColor.accent, lineWidth: 2)
                        }
                        .overlay {
                            Text("右に分割して開く")
                                .font(DSFont.auxiliary.weight(.semibold))
                                .foregroundStyle(DSColor.accentInk)
                        }
                        .frame(width: geometry.size.width / 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(DSSpacing.xs)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 分割中は操作中の区画を accent の枠で示し、押された区画を操作中にする（C2）。
    private func focusablePane(_ tab: ChildTab, isFocused: Bool) -> some View {
        content(tab)
            .overlay {
                if isFocused {
                    Rectangle().strokeBorder(DSColor.accent.opacity(0.6), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                guard !isFocused else { return }
                router.tabs.updateLayout(for: node.id) { $0.select(tab) }
            })
    }

    static func leftWidth(fraction: Double, totalWidth: CGFloat) -> CGFloat {
        let maximum = totalWidth - minimumPaneWidth - 1
        return min(max(totalWidth * fraction, minimumPaneWidth), maximum)
    }
}

// MARK: - File tab

/// ファイルの子タブ。編集・保存・外部変更との競合（上書き／キャンセル）。
private struct FileTabView: View {
    @Bindable var document: FileTabDocument
    @State private var showsConflictAlert = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            if document.loadFailed {
                ContentUnavailableView(
                    "ファイルを開けません",
                    systemImage: "exclamationmark.triangle",
                    description: Text("このファイルは利用できないか、有効なUTF-8ではありません。")
                )
            } else if document.isLoaded {
                TextEditor(text: $document.draft)
                    .font(DSFont.mono)
                    .scrollContentBackground(.hidden)
                    .background(DSColor.codeBackground)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(DSColor.separator).frame(height: 1)
            HStack(spacing: DSSpacing.s) {
                Text(verbatim: document.path)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let saveError {
                    Text("保存できませんでした: \(saveError)")
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.attentionInk(.error))
                        .lineLimit(1)
                } else if document.isDirty {
                    Text("未保存の変更")
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer(minLength: 0)
                Button("保存") {
                    Task { await save() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!document.isDirty)
            }
            .padding(.horizontal, DSSpacing.m)
            .frame(height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await document.loadIfNeeded() }
        .alert(Text("\(document.fileName) は外部で変更されています"), isPresented: $showsConflictAlert) {
            Button("上書き", role: .destructive) {
                Task { await overwrite() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("キャンセル", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("開いてから別のプログラムが書き換えました。上書きすると、その変更は失われ、元に戻せません。")
        }
        .dialogSeverity(.critical)
    }

    private func save() async {
        do {
            saveError = nil
            if try await document.save() == .conflictDetected {
                showsConflictAlert = true
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func overwrite() async {
        do {
            saveError = nil
            try await document.overwrite()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
