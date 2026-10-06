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
    let simulatorHub: SimulatorHub?
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
                    agentConsoleWindowID: agentConsoleWindowID,
                    simulatorHub: simulatorHub
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
            EditorPanelView(
                viewModel: editorPanel.viewModel,
                projectName: node.workspaceName,
                workingDirectory: node.rawWorkspacePath,
                isDirty: { files.existing(for: node.id, path: $0)?.hasUnsavedChanges ?? false }
            ) { path in
                let requestedDirectory = node.rawWorkspacePath
                Task {
                    let root = await FileTabOpening.root(for: requestedDirectory)
                    files.openFileTab(
                        sessionID: node.id, root: root, relativePath: path, router: router,
                        requestedWorkingDirectory: requestedDirectory,
                        currentWorkingDirectory: viewModel.sessionNode(id: node.id)?.rawWorkspacePath
                    )
                }
            }
        case .simulator:
            if let simulatorHub {
                SimulatorTabView(hub: simulatorHub, sessionID: node.id,
                                 isFocused: router.tabs.layout(for: node.id).selected == .simulator)
                    .id(node.id)
            }
        case .browser:
            if let model = router.browsers[node.id] {
                BrowserTabView(model: model).id(node.id)
            }
        case .file(let path):
            RestoredFileTabView(
                files: files, sessionID: node.id, path: path, workingDirectory: node.rawWorkspacePath,
                currentWorkingDirectory: { viewModel.sessionNode(id: node.id)?.rawWorkspacePath },
                lastWriter: { [viewModel] document in document.lastWriter(among: viewModel.sessionNodes, excluding: node.id) },
                isFocused: router.tabs.layout(for: node.id).selected == .file(path),
                openBrowser: { url in router.openBrowser(url, for: node.id) },
                openFile: { root, linkedPath in
                    files.openFileTab(
                        sessionID: node.id, root: root, relativePath: linkedPath, router: router,
                        requestedWorkingDirectory: node.rawWorkspacePath,
                        currentWorkingDirectory: viewModel.sessionNode(id: node.id)?.rawWorkspacePath
                    )
                }
            )
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
    var simulatorHub: SimulatorHub? = nil
    @Environment(\.localizationBundle) private var localizationBundle

    @Environment(\.locale) private var locale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabBar(showsPath: true)
            tabContents(compact: true).fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            tabBar(showsPath: false)
        }
        .padding(.horizontal, 10)
        .frame(height: DSLayout.childTabBarHeight)
        .background(DSColor.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("このセッションのタブ"))
    }

    private func tabBar(showsPath: Bool) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            if showsPath {
                tabContents()
                    .fixedSize(horizontal: true, vertical: true)
                FilePathLabel(path: abbreviatedPath, alignment: .trailing)
                    .frame(minWidth: 0, maxWidth: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal, showsIndicators: false) {
                        tabButtons()
                    }
                    .onAppear { scroll.scrollTo(layout.selected, anchor: .trailing) }
                    .onChange(of: layout.selected) { _, selected in scroll.scrollTo(selected, anchor: .trailing) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                addButton.fixedSize()
            }
        }
    }

    private func tabContents(compact: Bool = false) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            tabButtons(compact: compact)
            addButton.fixedSize()
        }
    }

    private func tabButtons(compact: Bool = false) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(layout.tabs, id: \.self) { tab in
                ChildTabButton(
                    tab: tab,
                    glyph: glyph(for: tab),
                    showsGlyph: !compact,
                    title: title(for: tab),
                    isShown: layout.isShown(tab),
                    isSelected: layout.selected == tab,
                    isDirty: isDirty(tab),
                    onSelect: { router.tabs.updateLayout(for: node.id) { $0.select(tab) } },
                    onClose: { router.tabRequest = .closeChild(node.id, tab) }
                )
                .fixedSize(horizontal: true, vertical: true)
                .id(tab)
            }
        }
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
            NewTabChooser(router: router, node: node, agentConsoleWindowID: agentConsoleWindowID,
                          simulatorHub: simulatorHub)
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
        case .simulator: "▯"
        case .browser: "◎"
        case .file: "{}"
        }
    }

    /// 文言は画面のロケール（アプリ内の言語設定）で引くため Text で返す。
    private func title(for tab: ChildTab) -> Text {
        switch tab {
        case .conversation: Text("会話", bundle: localizationBundle)
        case .terminal: Text("ターミナル", bundle: localizationBundle)
        case .simulator: Text("シミュレーター")
        case .browser: Text("ブラウザ")
        case .changes: changeCount > 0 ? Text("変更 \(changeCount)") : Text("tab.changes")
        case .file(let path): Text(verbatim: (path as NSString).lastPathComponent)
        }
    }

    private func isDirty(_ tab: ChildTab) -> Bool {
        guard case .file(let path) = tab else { return false }
        return files.existing(for: node.id, path: path)?.hasUnsavedChanges ?? false
    }
}

private struct ChildTabButton: View {
    let tab: ChildTab
    let glyph: String
    let showsGlyph: Bool
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
            if showsGlyph { Text(verbatim: glyph)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DSColor.textTertiary)
            }
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
        case .simulator: "phlox-tab:simulator"
        case .browser: "phlox-tab:browser"
        case .file(let path): "phlox-tab:file:\(path)"
        }
    }

    init?(dragPayload: String) {
        switch dragPayload {
        case "phlox-tab:conversation": self = .conversation
        case "phlox-tab:terminal": self = .terminal
        case "phlox-tab:changes": self = .changes
        case "phlox-tab:simulator": self = .simulator
        case "phlox-tab:browser": self = .browser
        default:
            let prefix = "phlox-tab:file:"
            guard dragPayload.hasPrefix(prefix) else { return nil }
            self = .file(String(dragPayload.dropFirst(prefix.count)))
        }
    }
}

// MARK: - New tab chooser (C4)

/// 「＋」と ⌘T で開く選択肢。↑↓ で移動、↩ で開く。
struct NewTabChooser: View {
    @Bindable var router: AppRouter
    let node: SessionNode
    let agentConsoleWindowID: String?
    let simulatorHub: SimulatorHub?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @FocusState private var focused: Item?

    enum Item: Hashable, CaseIterable {
        case conversation, terminal, changes, file, agentConsole, simulator, browser
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
                if item == .simulator {
                    Rectangle().fill(DSColor.separator).frame(height: 1).padding(.vertical, DSSpacing.xs)
                }
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
        case .simulator: "▯"
        case .browser: "◎"
        case .file: "{}"
        case .agentConsole: "⚙"
        }
    }

    private func title(_ item: Item) -> Text {
        switch item {
        case .conversation: Text("会話（このセッション）")
        case .terminal: Text("ターミナル（この worktree で）")
        case .changes: Text("変更一覧 · 差分")
        case .simulator: Text("シミュレーター")
        case .browser: Text("ブラウザ")
        case .file: Text("ファイルを開く…")
        case .agentConsole: Text("エージェント管理")
        }
    }

    private func shortcut(_ item: Item) -> String {
        switch item {
        case .terminal: "⌃⌘T"
        case .changes: "⌃⌘E"
        case .simulator: "⌃⌘Y"
        case .browser: "⌃⌘R"
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
        case .browser: router.openChildTab(.browser)
        case .simulator:
            router.openChildTab(.simulator)
            simulatorHub?.requestMenuFocus(for: node.id)
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
                        onChanged: { translation in
                            if dragFraction == nil { fractionAtDragStart = leftWidth / width }
                            dragFraction = fractionAtDragStart + translation / width
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

/// 復元タブもルートの解決を待ち、既に開いた文書の固定ルートを優先する。
private struct RestoredFileTabView: View {
    let files: FileTabDocuments
    let sessionID: SessionID
    let path: String
    let workingDirectory: String
    let currentWorkingDirectory: () -> String?
    let lastWriter: (FileTabDocument) -> String?
    let isFocused: Bool
    let openBrowser: (URL) -> Void
    let openFile: (String, String) -> Void
    @State private var restoredDocument: FileTabDocument?

    private var changingWorkspace: Bool { FileTabDocumentRegistry.shared.isChangingSession(sessionID) }

    var body: some View {
        Group {
            if !changingWorkspace,
               let document = files.existing(for: sessionID, path: path) ?? restoredDocument, !document.invalidated {
                FileTabUndoScope(document: document, isFocused: isFocused) {
                    FileTabView(document: document, lastWriter: lastWriter, isFocused: isFocused, openFile: openFile, openBrowser: openBrowser)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(workingDirectory)-\(changingWorkspace)") {
            guard !changingWorkspace else { return }
            guard files.existing(for: sessionID, path: path) == nil else { return }
            restoredDocument = nil
            let root = await FileTabOpening.root(for: workingDirectory)
            guard !Task.isCancelled, !changingWorkspace,
                  currentWorkingDirectory() == workingDirectory else { return }
            restoredDocument = files.document(for: sessionID, path: path, root: root)
        }
    }
}

/// ファイルの子タブ。編集・保存・外部変更との競合（上書き／キャンセル）。
struct FileTabView: View {
    @Bindable var document: FileTabDocument
    let lastWriter: (FileTabDocument) -> String?
    let isFocused: Bool
    let openFile: (String, String) -> Void
    let openBrowser: ((URL) -> Void)?
    @State private var htmlPreview: HTMLPreviewModel
    @State private var showsIsolationExplanation = false
    @State private var showsConflictAlert = false
    @State private var conflictWriter: String?
    @State private var saveError: String?
    @State private var emphasizesMarkdownReason = false
    @Environment(\.fileTabRecoveryPasteboardName) private var fileTabRecoveryPasteboardName
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    init(document: FileTabDocument, lastWriter: @escaping (FileTabDocument) -> String?,
         isFocused: Bool, openFile: @escaping (String, String) -> Void,
         openBrowser: ((URL) -> Void)? = nil, htmlPreview: HTMLPreviewModel? = nil,
         markdownEditor: MarkdownBlockEditor? = nil,
         showsIsolationExplanation: Bool = false, emphasizesMarkdownReason: Bool = false) {
        self.document = document
        self.lastWriter = lastWriter
        self.isFocused = isFocused
        self.openFile = openFile
        self.openBrowser = openBrowser
        self.markdownEditor = markdownEditor
        _htmlPreview = State(initialValue: htmlPreview ?? HTMLPreviewModel(document: document))
        _showsIsolationExplanation = State(initialValue: showsIsolationExplanation)
        _emphasizesMarkdownReason = State(initialValue: emphasizesMarkdownReason)
    }

    private let markdownEditor: MarkdownBlockEditor?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            .frame(height: 30)
            .background(DSColor.panelBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DSColor.separator).frame(height: 1)
            }
            if document.blockEditFailure != nil, let edit = document.activeBlockEdit {
                HStack(spacing: DSSpacing.s) {
                    Button { document.discardActiveBlockEdit(id: edit.id) } label: { localized("編集を破棄") }
                    Button {
                        let pasteboard = fileTabRecoveryPasteboardName.map { NSPasteboard(name: .init($0)) } ?? .general
                        document.openSourceDiscardingBlockEdit(id: edit.id, pasteboard: pasteboard)
                    } label: { localized("ソースで開く") }
                        .help(localized("編集中の内容をコピーしてソース表示で開きます"))
                }
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 11))
                .padding(DSSpacing.s)
            }
            switch document.loadState {
            case .loadFailed, .outsideRoot, .tooLarge, .binary:
                unavailableContent
            case .loaded:
                if document.isHTML, document.presentation == .rendered {
                    htmlContent
                } else if document.isMarkdown, document.presentation == .rendered {
                    markdownEditor ?? MarkdownBlockEditor(document: document, openURL: openMarkdownURL, linkDestination: markdownLinkDestination)
                } else {
                    CodeTextEditor(getText: { document.draft }, setText: { document.draft = $0 },
                                   path: document.path, bomByteCount: document.bom.count,
                                   isEditable: !document.isReadOnly, readOnlyText: document.readOnlyText)
                        .disabled(document.invalidated)
                }
            case .unloaded, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await document.loadIfNeeded() }
        .task {
            if document.isHTML { await htmlPreview.prepare() }
        }
        .background {
            Button("表示を切り替え") { togglePresentation() }
                .keyboardShortcut("m", modifiers: [.control, .command])
                .disabled(!canTogglePresentation || !isFocused)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            Button("保存") { requestSave() }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isFocused || document.isReadOnly)
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onChange(of: document.blockEditFailure) { _, failure in
            if failure == nil { emphasizesMarkdownReason = false }
        }
        // 09 E1: 取り返しがつかない型。キャンセルが既定。
        .dsDialog(isPresented: $showsConflictAlert) {
            DSDialog(
                .irreversible,
                title: String(format: AppLocalizedString.string("%@ は外部で変更されています", locale: locale), document.fileName),
                message: conflictWriter.map {
                    String(format: AppLocalizedString.string("開いてから別のセッション（%@）が書き換えました。上書きすると、その変更は失われ、元に戻せません。", locale: locale), $0)
                } ?? AppLocalizedString.string("開いてから別のセッションが書き換えました。上書きすると、その変更は失われ、元に戻せません。", locale: locale),
                buttons: [
                    DSDialogButton("上書き", role: .destructive) {
                        showsConflictAlert = false
                        Task { await overwrite() }
                    },
                    DSDialogButton("キャンセル", role: .primary) { showsConflictAlert = false },
                ],
                onCancel: { showsConflictAlert = false }
            )
        }
    }

    private var canTogglePresentation: Bool {
        document.isLoaded && !document.invalidated && document.blockEditFailure == nil
            && ((document.isMarkdown && !document.markdownPresentationLocked)
                || (document.isHTML && htmlPreview.ruleList != nil && htmlPreview.preparationError == nil))
    }

    /// 先にパスを縮め、次に補助の文言、最後に表示切替のアイコンを縮める。
    private var toolbar: some View {
        let pathWidth = FilePathDisplay.minimumReadableWidth(document.path)
        return ViewThatFits(in: .horizontal) {
            toolbarContents(reason: true, unsaved: true, keyHint: true, icons: false, minimumPathWidth: pathWidth)
            toolbarContents(reason: false, unsaved: true, keyHint: true, icons: false, minimumPathWidth: pathWidth)
            toolbarContents(reason: false, unsaved: false, keyHint: true, icons: false, minimumPathWidth: pathWidth)
            toolbarContents(reason: false, unsaved: false, keyHint: false, icons: false, minimumPathWidth: pathWidth)
            toolbarContents(reason: false, unsaved: false, keyHint: false, icons: true, minimumPathWidth: pathWidth)
            // 長いファイル名でも最小区画からはみ出さないよう、最後にパスの最小幅を外す。
            toolbarContents(reason: false, unsaved: false, keyHint: false, icons: true, minimumPathWidth: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func toolbarContents(reason showsReason: Bool, unsaved showsUnsaved: Bool, keyHint: Bool, icons: Bool, minimumPathWidth: CGFloat) -> some View {
        HStack(spacing: DSSpacing.s) {
            FilePathLabel(path: document.path)
                .frame(minWidth: minimumPathWidth, idealWidth: minimumPathWidth, maxWidth: .infinity)
            HStack(spacing: DSSpacing.s) {
            if !document.loadFailed {
                if document.isReadOnly || isLargeSource {
                    Label { if showsReason { Text(verbatim: largeFileNotice) } } icon: { Image(systemName: "info.circle") }
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .help(document.isReadOnly ? Text(verbatim: largeFileNotice) : document.isMarkdown ? Text(verbatim: markdownReasonDetail(locale: locale)) : Text(verbatim: largeFileNotice))
                        .accessibilityLabel(Text(verbatim: largeFileNotice))
                        .accessibilityIdentifier(document.isReadOnly ? "large-file-read-only-notice" : "large-file-plain-notice")
                }
                if document.isHTML {
                    if htmlPreview.preparationError != nil {
                        Label {
                            if showsReason { localized(htmlPreview.preparationFailureReason) }
                        } icon: { Image(systemName: "info.circle") }
                            .font(DSFont.meta)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .help(htmlPreparationHelp())
                    } else if document.presentation == .rendered {
                        if !htmlPreview.processTerminated { isolationButton }
                        if showsReason && !document.isReadOnly { localized("閲覧のみ").font(DSFont.meta).foregroundStyle(DSColor.textSecondary) }
                        Button { htmlPreview.reload() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain)
                            .disabled(htmlPreview.ruleList == nil || !document.isLoaded || document.invalidated)
                            .help(localized("再読込"))
                            .accessibilityLabel(localized("再読込"))
                    }
                    if let openBrowser {
                        Button {
                            openInBrowser(openBrowser)
                        } label: {
                            Label { if !icons { Text("ブラウザで開く") } } icon: { Image(systemName: "globe") }
                        }
                        .buttonStyle(.ds(.secondary, height: 20, fontSize: 11, padding: icons ? 4 : 8))
                        .disabled(!document.isLoaded || document.invalidated)
                        .help("保存済みの HTML をブラウザで開きます")
                        .accessibilityLabel("ブラウザで開く")
                        .accessibilityIdentifier("html-open-in-browser")
                    }
                    presentationButtons(compact: icons)
                }
                if document.isMarkdown {
                    if let reason = markdownReason, !isLargeSource {
                        Label { if showsReason { localized(reason) } } icon: { Image(systemName: "info.circle") }
                            .font(DSFont.meta)
                            .foregroundStyle(emphasizesMarkdownReason && document.blockEditFailure != nil ? DSColor.attentionInk(.error) : DSColor.textPrimary)
                            .lineLimit(1)
                            .help(markdownReasonDetail(locale: locale))
                    }
                    presentationButtons(compact: icons)
                }
                if let saveError {
                    Text("保存できませんでした: \(saveError)")
                        .font(DSFont.meta).foregroundStyle(DSColor.attentionInk(.error)).lineLimit(1)
                } else if document.hasUnsavedChanges {
                    HStack(spacing: 5) {
                        Circle().fill(DSColor.textPrimary).frame(width: 6, height: 6)
                        if showsUnsaved { localized("未保存").font(DSFont.meta) }
                    }
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityLabel(localized("未保存"))
                }
                Button { Task { await save() } } label: { localized("保存") }
                    .buttonStyle(.ds(.secondary, keyHint: keyHint ? "⌘S" : nil, height: 20, fontSize: 11, padding: 8,
                                     fill: canSave ? nil : .clear))
                    .accessibilityLabel(localized("保存"))
                    .accessibilityHint("⌘S")
                    .disabled(!canSave)
            }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var canSave: Bool {
        document.isLoaded && !document.isReadOnly && !document.invalidated && document.hasUnsavedChanges && document.blockEditFailure == nil
    }

    func openInBrowser(_ open: (URL) -> Void) {
        guard document.isHTML, document.isLoaded, !document.invalidated else { return }
        open(URL(fileURLWithPath: document.root).appendingPathComponent(document.path))
    }

    private var markdownReason: String? {
        document.blockEditFailure ?? document.markdownAnalysisFailure
            ?? (document.markdownPresentationLocked ? "大きすぎるためソース表示に固定" : nil)
    }

    func markdownReasonDetail(locale: Locale, bundle: Bundle? = nil) -> String {
        func localizedString(_ key: String) -> String {
            AppLocalizedString.string(key, locale: locale, bundle: bundle ?? localizationBundle)
        }
        if let failure = document.blockEditFailure {
            return String(format: localizedString("%@。編集内容は残っています。"), localizedString(failure))
        }
        if let failure = document.markdownAnalysisFailure { return localizedString(failure) }
        if document.draft.utf8.count > 500_000 {
            return String(format: localizedString("このファイルは大きすぎるためソース表示に固定しています（%@ KB。上限 500 KB）"), (document.draft.utf8.count / 1_000).formatted(.number.locale(locale)))
        }
        return String(format: localizedString("このファイルは大きすぎるためソース表示に固定しています（%@ ブロック。上限 2,000）"), document.markdownBlocks.count.formatted(.number.locale(locale)))
    }

    private func localized(_ key: String) -> Text {
        Text(LocalizedStringKey(key), bundle: localizationBundle)
    }

    private func localizedString(_ key: String) -> String {
        AppLocalizedString.string(key, locale: locale, bundle: localizationBundle)
    }

    private var unavailableContent: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: DSRadius.s)
                .strokeBorder(DSColor.textTertiary, lineWidth: 1.5)
                .frame(width: document.loadState == .tooLarge ? 36 : 30, height: 36)
                .overlay(alignment: .bottom) {
                    Text(verbatim: unavailableBadge)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.bottom, 5)
                }
                .frame(width: 40, height: 44)
            localized(unavailableTitle).font(DSFont.row.weight(.semibold))
            Text(verbatim: unavailableMessage).font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            if case .outsideRoot(let target) = document.loadState {
                VStack(alignment: .leading, spacing: 3) {
                    localized("解決先").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                    Text(verbatim: FilePathDisplay.homeRelative(target))
                        .font(DSFont.monoCaption).textSelection(.enabled)
                        .padding(DSSpacing.s).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.row))
                }
                .frame(maxWidth: 460)
            }
            Button {
                if case .outsideRoot(let target) = document.loadState {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: document.root).appendingPathComponent(document.path))
                }
            } label: { localized(unavailableBadge == "↗" ? "Finder で表示" : "既定のアプリで開く") }
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.windowBackground)
    }

    private var unavailableBadge: String {
        switch document.loadState {
        case .tooLarge: "\(WorkingTreeText.maximumReadableFileSize / 1_000_000)MB+"
        case .binary: "BIN"
        case .outsideRoot: "↗"
        default: "?"
        }
    }

    private var isLargeSource: Bool {
        document.presentation == .source && !document.syntaxHighlightingEnabled
    }

    private var largeFileNotice: String {
        if document.isReadOnly {
            let key = document.presentation == .source && document.readOnlyText?.hasOmittedLines == true
                ? "閲覧のみ（%@ MB を超えるため）・長い行は省略して表示"
                : "閲覧のみ（%@ MB を超えるため）"
            return String(format: localizedString(key), String(WorkingTreeText.maximumEditableFileSize / 1_000_000))
        }
        return localizedString("大きいファイルのため色付けなし")
    }

    private var unavailableTitle: String {
        switch document.loadState {
        case .tooLarge: "ファイルが大きすぎるため開けません"
        case .binary: "テキストではないため開けません"
        case .outsideRoot: "このファイルは作業ツリーの外を指しています"
        default: "ファイルを開けません"
        }
    }

    private var unavailableMessage: String {
        switch document.loadState {
        case .tooLarge:
            let limit = String(WorkingTreeText.maximumReadableFileSize / 1_000_000)
            if let size = document.fileSize {
                let value = (Double(size) / 1_000_000).formatted(.number.locale(locale).precision(.fractionLength(1...6)))
                return String(format: localizedString("%@ MB あります。Phlox で開けるのは %@ MB までです。"), value, limit)
            }
            return String(format: localizedString("Phlox で開けるのは %@ MB までです。"), limit)
        case .binary: return localizedString("ファイルの先頭にテキストには含まれない文字（NUL）があります。")
        case .outsideRoot:
            return String(format: localizedString("リンクの先が %@ の外にあるため、Phlox では読み書きしません。"), FilePathDisplay.homeRelative(document.root))
        default: return localizedString(document.readFailureReason ?? "ファイルを読み込めませんでした。")
        }
    }

    private func togglePresentation() {
        guard canTogglePresentation else { return }
        _ = document.setPresentation(document.presentation == .rendered ? .source : .rendered)
    }

    private func presentationButtons(compact: Bool) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            presentationButton(.rendered, title: compact ? "Aa" : "レンダリング", label: "レンダリング")
            presentationButton(.source, title: compact ? "</>" : "ソース", label: "ソース")
        }
        .padding(DSSpacing.xxs)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("ファイルの表示"))
        .accessibilityHint(localized("⌃⌘M で切り替え"))
        .accessibilityIdentifier("file-tab-presentation")
    }

    private func presentationButton(_ presentation: FileTabDocument.Presentation, title: String, label: String) -> some View {
        Button { _ = document.setPresentation(presentation) } label: {
            localized(title)
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.chip)
                .padding(.vertical, DSSpacing.xxs)
                .background(document.presentation == presentation
                            ? (DSColor.isDark ? DSColor.fillSelected : DSColor.background) : .clear,
                            in: RoundedRectangle(cornerRadius: DSRadius.s))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.s)
                    .strokeBorder(document.presentation == presentation && !DSColor.isDark ? DSColor.border : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!document.isLoaded || document.invalidated
                  || (presentation == .source && document.blockEditFailure != nil)
                  || (presentation == .rendered && document.blockEditFailure == nil && !canTogglePresentation))
        .accessibilityLabel(localized(label))
        .help(presentationHelp(presentation))
        .accessibilityAddTraits(document.presentation == presentation ? .isSelected : [])
    }

    func presentationHelp(_ presentation: FileTabDocument.Presentation, bundle: Bundle? = nil) -> Text {
        Text(LocalizedStringKey(document.isHTML && presentation == .rendered
                  ? "⌃⌘M で切り替え。レンダリング表示は閲覧のみ" : "⌃⌘M で切り替え"),
             bundle: bundle ?? localizationBundle)
    }

    func htmlPreparationHelp(bundle: Bundle? = nil) -> Text {
        Text(LocalizedStringKey(document.isReadOnly
             ? "安全に表示する準備ができないため、ソースを表示しています。ファイルの内容は閲覧のみです。"
             : "安全に表示する準備ができないため、ソースを表示しています。ファイルの内容は編集できます。"),
             bundle: bundle ?? localizationBundle)
    }

    private var isolationButton: some View {
        Button { showsIsolationExplanation.toggle() } label: {
            HStack(spacing: 5) {
                Circle().strokeBorder(DSColor.textTertiary, lineWidth: 1.2).frame(width: 7, height: 7)
                localized("外部の読み込みを止めています")
            }
            .padding(.horizontal, DSSpacing.xxs)
            .padding(.vertical, 2)
            .background(showsIsolationExplanation ? DSColor.fillSubtle : .clear,
                        in: RoundedRectangle(cornerRadius: DSRadius.s))
        }
            .buttonStyle(.plain)
            .font(DSFont.meta)
            .foregroundStyle(DSColor.textSecondary)
            .fixedSize()
            .accessibilityLabel(localized("外部の読み込みを止めています"))
            .help(localized("外部の読み込みを止めています"))
            .accessibilityHint(localized("説明を表示"))
            .popover(isPresented: $showsIsolationExplanation) {
                isolationExplanation()
                    .environment(\.locale, locale)
            }
    }

    func isolationExplanation(bundle: Bundle? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("外部の読み込みを止めています", bundle: bundle ?? localizationBundle).font(DSFont.row.weight(.semibold))
            Text("このページが外部に出す要求（画像・CSS・フォントなど）と、ページのスクリプトは常に止めています。作業ツリー内のファイルは読み込みます。安全のための仕様で、切り替えはできません。", bundle: bundle ?? localizationBundle)
                .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary).lineSpacing(4)
        }
        .padding(DSSpacing.m)
        .frame(width: 340, alignment: .leading)
        .background(DSColor.popoverBackground)
    }

    @ViewBuilder
    private var htmlContent: some View {
        if htmlPreview.processTerminated {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 28)).foregroundStyle(DSColor.textTertiary)
                localized("表示が停止しました").font(DSFont.row.weight(.semibold))
                localized("ページを描く処理が終了しました。未保存の下書きは残っています。")
                    .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
                Button("再読込") { htmlPreview.reload() }.buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if htmlPreview.ruleList == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HTMLPreviewView(model: htmlPreview) { path in openFile(document.root, path) }
                .overlay(alignment: .bottomLeading) {
                    if let url = htmlPreview.hoveredURL {
                        FileLinkDestinationView(destination: FileLinkDestination(url: url, decision: htmlPreview.hoveredDestination))
                            .padding(DSSpacing.s)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func openMarkdownURL(_ url: URL) -> OpenURLAction.Result {
        Task {
            let destination = await MarkdownLinkRouting.checkedDestination(url, documentPath: document.path, root: document.root)
            guard !document.invalidated else { return }
            switch destination {
            case .openFile(let path): openFile(document.root, path)
            case .openBrowser(let url): NSWorkspace.shared.open(url)
            default: break
            }
        }
        return .handled
    }

    private func markdownLinkDestination(_ url: URL) async -> FileLinkDestination? {
        let resolved = MarkdownLinkRouting.resolvedURL(url, documentPath: document.path, root: document.root)
        let destination = await MarkdownLinkRouting.checkedDestination(url, documentPath: document.path, root: document.root)
        return FileLinkDestination(url: resolved ?? url, decision: destination)
    }

    private func save() async {
        do {
            saveError = nil
            if try await document.save() == .conflictDetected {
                conflictWriter = lastWriter(document)
                showsConflictAlert = true
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    @discardableResult
    func requestSave() -> Task<Void, Never>? {
        if canSave {
            return Task { await save() }
        } else if document.blockEditFailure != nil {
            emphasizesMarkdownReason = true
        }
        return nil
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
