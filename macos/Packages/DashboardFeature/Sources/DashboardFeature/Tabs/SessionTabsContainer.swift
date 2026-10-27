import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

/// 上段のプロジェクト列と、単体表示時のプロジェクトタブ列・中身（左右分割可）。
/// 会話の中身と、セッション未選択時の開始画面は `conversation` が描く。
struct SessionTabsContainer<Conversation: View>: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let terminals: ProjectTerminalStore?
    let simulatorHub: SimulatorHub?
    let editorPanel: EditorPanelCoordinator
    let files: FileTabDocuments
    var bottomPanel: BottomPanelState? = nil
    @ViewBuilder let conversation: (ProjectTab?) -> Conversation

    var body: some View {
        VStack(spacing: 0) {
            SessionTabBar(viewModel: viewModel, router: router)
            if router.viewMode == .grid {
                bottomContent { conversation(nil) }
            } else if let projectID = tabProjectID, let project = viewModel.projects.first(where: { $0.id == projectID }) {
                let layout = router.tabs.layout(for: projectID)
                let chats = viewModel.chatTabs(in: projectID)
                ChildTabBar(
                    router: router, viewModel: viewModel, project: project, layout: layout, chats: chats,
                    changeCount: editorPanel.viewModel.changes.count, files: files, simulatorHub: simulatorHub
                )
                bottomContent {
                    if router.showsNewChat {
                        pane(.newChat, project: project)
                    } else {
                        ChildTabPanes(
                            router: router, projectID: projectID, layout: layout, chats: chats,
                            content: { tab in pane(tab, project: project) }
                        )
                    }
                }
            } else {
                bottomContent { conversation(nil) }
            }
        }
    }

    @ViewBuilder
    private func bottomContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let bottomPanel {
            let target = BottomPanelState.targetProjectID(mode: router.viewMode, selectedProjectID: router.selectedProjectID,
                selectedTileProjectID: router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID })
            BottomPanelContainer(state: bottomPanel, project: viewModel.projects.first { $0.id == target }, terminals: terminals, content: content)
        } else { content() }
    }

    /// 上段に並べるプロジェクト：選択中セッションのプロジェクト、無ければ選択中のプロジェクト。
    private var tabProjectID: ProjectID? {
        router.selectedProjectID ?? router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID }
    }

    /// 文をそのセッションの入力欄に入れ、会話のタブを `kept` の無い方に出す（シミュレーターの FR-10・ブラウザの FR-11）。送信はしない。
    /// 入れられないとき（送信の受付待ち・許可や質問の回答待ち・未起動）は警告音だけ鳴らす。
    private func tellAgent(_ text: String, node: SessionNode, keeping kept: ProjectTab) {
        // 同じクリックで区画のタップ（押した区画を操作中にする）も走るので、その後に回す。
        // 文とタブの切り替えを同じ更新にまとめ、切り替えで入力先を外す処理（DashboardView）より後に入力欄へフォーカスを移す。
        DispatchQueue.main.async { [router] in
            switch node {
            case .appServer(let session):
                guard session.appendToDraft(text) else { return NSSound.beep() }
            case .pty(let session):
                // 回答待ちの CLI では、文の数字や英字が選択肢のキーとして効いてしまう。
                guard session.status == .idle || session.status == .running else { return NSSound.beep() }
                // 文は 1 行なので、Enter を送らない限り CLI は送信しない。
                Task { await session.sendInput(Data(text.utf8)) }
            }
            if let projectID = node.projectID {
                router.tabs.updateLayout(for: projectID) { $0.showChat(node.id, keeping: kept) }
                router.selectTab(.chat(node.id), in: projectID)
            }
        }
    }

    @ViewBuilder
    private func pane(_ tab: ProjectTab, project: Project) -> some View {
        let node = sessionID(for: tab).flatMap { viewModel.sessionNode(id: $0) }
        switch tab {
        case .chat(let id):
            chatPane(tab, sessionID: id, project: project)
        case .newChat:
            conversation(tab)
        case .terminal(let id):
            if let terminals {
                TerminalPanelView(panel: terminals.terminal(for: id, projectID: project.id, workingDirectory: project.directoryPath), showsHeader: false).id(id)
            } else {
                ContentUnavailableView("ターミナルを準備しています", systemImage: "terminal")
            }
        case .changes:
            EditorPanelView(
                viewModel: editorPanel.viewModel, projectName: project.name, workingDirectory: project.directoryPath,
                isDirty: { files.existing(for: project.id, path: $0)?.hasUnsavedChanges ?? false }
            ) { path in
                Task {
                    guard let path = await FileTabOpening.projectRelativeChangePath(path, workingDirectory: project.directoryPath) else { return }
                    let root = await FileTabOpening.root(for: project.directoryPath)
                    files.openFileTab(projectID: project.id, root: root, relativePath: path, router: router,
                        requestedWorkingDirectory: project.directoryPath,
                        currentWorkingDirectory: viewModel.projects.first { $0.id == project.id }?.directoryPath)
                }
            }
        case .simulator:
            if let simulatorHub {
                SimulatorTabView(hub: simulatorHub, projectID: project.id,
                    isFocused: router.tabs.layout(for: project.id).selected == .simulator,
                    tellAgent: node.map { node in { tellAgent($0, node: node, keeping: .simulator) } }).id(project.id)
            }
        case .browser:
            if let model = router.browsers[project.id] {
                BrowserTabView(model: model, tellAgent: node.map { node in { tellAgent($0, node: node, keeping: .browser) } }).id(project.id)
            }
        case .file(let path):
            RestoredFileTabView(
                files: files, projectID: project.id, path: path, workingDirectory: project.directoryPath,
                currentWorkingDirectory: { viewModel.projects.first { $0.id == project.id }?.directoryPath },
                lastWriter: { document in document.lastWriter(among: viewModel.sessionNodes, excluding: node?.id) },
                isFocused: router.tabs.layout(for: project.id).selected == .file(path),
                openBrowser: { router.openBrowser($0, for: project.id) },
                openFile: { root, path in
                    files.openFileTab(projectID: project.id, root: root, relativePath: path, router: router,
                        requestedWorkingDirectory: project.directoryPath,
                        currentWorkingDirectory: viewModel.projects.first { $0.id == project.id }?.directoryPath)
                }
            ).id("\(project.id)-\(path)")
        }
    }

    private func sessionID(for tab: ProjectTab) -> SessionID? {
        if case .chat(let id) = tab { return id }
        return router.selectedSession
    }

    @ViewBuilder
    private func chatPane(_ tab: ProjectTab, sessionID: SessionID, project: Project) -> some View {
        if let branch = viewModel.worktreeBranchName(for: sessionID),
           let node = viewModel.sessionNode(id: sessionID) {
            WorktreeChatPane(sessionID: sessionID, branch: branch, workingDirectory: node.workspacePath,
                projectName: project.name, workspaces: viewModel.workspaceSessionWorkspaces) {
                conversation(tab)
            }.id(sessionID)
        } else {
            conversation(tab)
        }
    }

}

private struct WorktreeChatPane<Conversation: View>: View {
    let sessionID: SessionID
    let branch: String
    let workingDirectory: String
    let projectName: String
    let workspaces: [SessionWorkspace]
    @ViewBuilder let conversation: () -> Conversation
    @State private var showsChanges = false
    @State private var editorPanel = EditorPanelCoordinator()

    var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: DSSpacing.xs) {
                    Text("worktree で実行中")
                    Text(verbatim: "·")
                    Text(verbatim: branch)
                        .font(DSFont.monoCaption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        showsChanges.toggle()
                    } label: {
                        Text("変更 \(editorPanel.viewModel.changes.count) ファイル")
                            .font(DSFont.auxiliary)
                            .foregroundStyle(showsChanges ? DSColor.textPrimary : DSColor.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("worktreeChanges.toggle")
                    .help(Text("変更 \(editorPanel.viewModel.changes.count) ファイル"))
                }
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }

                HStack(spacing: 0) {
                    conversation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsChanges {
                        Rectangle().fill(DSColor.separator).frame(width: 1)
                        EditorPanelView(
                            viewModel: editorPanel.viewModel,
                            projectName: projectName,
                            workingDirectory: workingDirectory
                        )
                        .frame(width: 440)
                    }
                }
            }
            .task(id: EditorPanelTargetPolicy.target(selectedSessionID: sessionID, workspaces: workspaces)) {
                editorPanel.update(selectedSessionID: sessionID, workspaces: workspaces)
                await editorPanel.resolve(workspaces: workspaces)
            }
            .task(id: showsChanges) {
                if showsChanges { await editorPanel.resolve(workspaces: workspaces) }
            }
    }
}

// MARK: - Child tab bar

/// 下段のプロジェクト内タブ列。チャットをセッション順に並べ、その後ろに項目を置く。
struct ChildTabBar: View {
    @Bindable var router: AppRouter
    let viewModel: DashboardViewModel
    let project: Project
    let layout: ProjectTabLayout
    let chats: [ProjectTab]
    let changeCount: Int
    let files: FileTabDocuments
    var simulatorHub: SimulatorHub? = nil
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            let tabs = layout.tabs(chats: chats)
            // 新規チャット画面を重ねている間は、どの子タブも選択表示にしない（要件 FR-1a）。
            let selected = router.showsNewChat ? nil : layout.selected ?? chats.first
            let maximumWidth: CGFloat = geometry.size.width < 700 ? 150 : 200
            let overflowLayout = TabBarOverflowLayout.make(
                contentWidths: tabs.map { tabWidth($0, selected: selected == $0, shown: layout.isShown($0), maximum: maximumWidth) },
                selectedIndex: selected.flatMap { tabs.firstIndex(of: $0) },
                availableWidth: max(0, geometry.size.width - 16),
                maxItemWidth: maximumWidth,
                addButtonWidth: 26,
                overflowButtonWidth: 70
            )
            HStack(spacing: 0) {
                ForEach(overflowLayout.visibleIndices, id: \.self) { index in
                    let tab = tabs[index]
                    ChildTabButton(
                        tab: tab,
                        title: title(for: tab),
                        isShown: layout.isShown(tab),
                        isSelected: selected == tab,
                        isDirty: isDirty(tab),
                        activityState: activityState(for: tab),
                        displayState: displayState(for: tab),
                        onSelect: { router.selectTab(tab, in: project.id) },
                        onClose: { tab.requestClose(in: router) }
                    )
                    .frame(width: overflowLayout.width(for: index), height: 26)
                    .accessibilityIdentifier(TabAccessibilityIdentifier.item(index + 1))
                }
                if overflowLayout.overflowCount > 0 {
                    let hiddenTabs = tabs.indices.filter { !overflowLayout.visibleIndices.contains($0) }.map { tabs[$0] }
                    SelectablePopoverButton(
                        options: hiddenTabs.map { tab in
                            SelectablePopoverOption(
                                id: tab.dragPayload,
                                value: tab.dragPayload,
                                title: titleText(for: tab),
                                closeAccessibilityLabel: tab.closeAccessibilityLabel,
                                isSelected: selected == tab
                            )
                        },
                        selectedID: selected?.dragPayload,
                        accessibilityLabel: "ほか \(overflowLayout.overflowCount)",
                        accessibilityValue: "",
                        accessibilityIdentifier: TabAccessibilityIdentifier.overflow,
                        help: "ほかのタブ",
                        width: 248,
                        onSelect: { option in
                            if let tab = hiddenTabs.first(where: { $0.dragPayload == option.id }) {
                                router.selectTab(tab, in: project.id)
                            }
                        },
                        onClose: { option in
                            if let tab = hiddenTabs.first(where: { $0.dragPayload == option.id }) {
                                tab.requestClose(in: router)
                            }
                        }
                    ) { _ in
                        (Text("ほか \(overflowLayout.overflowCount)") + Text(verbatim: " ⌄"))
                            .font(DSFont.auxiliary)
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: 70, height: 26)
                            .contentShape(Rectangle())
                    }
                }
                addButton
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: DSLayout.childTabBarHeight)
        .background(DSColor.windowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("このプロジェクトのタブ"))
    }

    private var addButton: some View {
        Button {
            router.newTabChooserPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: DSIconSize.m, weight: .regular))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text("タブを追加"))
        .accessibilityLabel(Text("タブを追加"))
        .accessibilityIdentifier(TabAccessibilityIdentifier.itemAdd)
        .popover(isPresented: $router.newTabChooserPresented, arrowEdge: .bottom) {
            NewTabChooser(router: router, project: project, simulatorHub: simulatorHub)
                // popover は画面のロケールを引き継がないので渡し直す（アプリ内の言語設定）。
                .environment(\.locale, locale)
        }
    }

    /// 表示と幅計算で同じ翻訳済み文字列を使う。
    private func title(for tab: ProjectTab) -> Text {
        Text(verbatim: titleText(for: tab))
    }

    func titleText(for tab: ProjectTab, locale overrideLocale: Locale? = nil, bundle: Bundle? = nil) -> String {
        Self.titleText(for: tab, viewModel: viewModel, changeCount: changeCount,
                       locale: overrideLocale ?? locale, bundle: bundle ?? localizationBundle)
    }

    /// 子タブの列とヘッダーの名前（新規チャットの要件 FR-41）で同じ文字列を使う。
    static func titleText(for tab: ProjectTab, viewModel: DashboardViewModel, changeCount: Int,
                          locale: Locale, bundle localizationBundle: Bundle) -> String {
        switch tab {
        case .chat(let id): viewModel.sessionNode(id: id)?.displayName ?? "会話"
        case .newChat: AppLocalizedString.string("新規チャット", locale: locale, bundle: localizationBundle)
        case .terminal: AppLocalizedString.string("ターミナル", locale: locale, bundle: localizationBundle)
        case .simulator: AppLocalizedString.string("シミュレーター", locale: locale, bundle: localizationBundle)
        case .browser: AppLocalizedString.string("ブラウザ", locale: locale, bundle: localizationBundle)
        case .changes: locale.language.languageCode?.identifier == "ja"
            ? "変更" : AppLocalizedString.string("tab.changes", locale: locale, bundle: localizationBundle)
        case .file(let path): (path as NSString).lastPathComponent
        }
    }

    private func tabWidth(_ tab: ProjectTab, selected: Bool, shown: Bool, maximum: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular) // DSFont.auxiliary
        let textWidth = ceil((titleText(for: tab) as NSString).size(withAttributes: [.font: font]).width)
        return min(maximum, textWidth + 16 + (shown || selected ? 20 : 0)
            + (activityState(for: tab).showsActivityIndicator ? SessionRunningSpinner.diameter + 6 : 0))
    }

    private func activityState(for tab: ProjectTab) -> SessionDisplayState {
        guard case .chat(let id) = tab else { return .idle }
        return viewModel.sessionNode(id: id)?.activityDisplayState ?? .idle
    }

    private func displayState(for tab: ProjectTab) -> SessionDisplayState {
        guard case .chat(let id) = tab else { return .idle }
        return viewModel.sessionNode(id: id)?.tabDisplayState ?? .idle
    }

    private func isDirty(_ tab: ProjectTab) -> Bool {
        guard case .file(let path) = tab else { return false }
        return files.existing(for: project.id, path: path)?.hasUnsavedChanges ?? false
    }
}

private struct ChildTabButton: View {
    let tab: ProjectTab
    let title: Text
    let isShown: Bool
    let isSelected: Bool
    let isDirty: Bool
    let activityState: SessionDisplayState
    let displayState: SessionDisplayState
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @Environment(\.locale) private var locale

    var body: some View {
        // PhloxTabsWindow.dc.html: 下段は高さ 26、padding 0 6 0 10。
        HStack(spacing: 6) {
            if activityState.showsActivityIndicator {
                SessionActivityIndicator(state: activityState)
            }
            title
                .font(DSFont.auxiliary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isShown ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(1)
            closeAccessory
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            isSelected ? DSColor.fillSelected : (isShown || isHovering ? DSColor.fillSubtle : Color.clear),
            in: RoundedRectangle(cornerRadius: DSRadius.row)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .draggable(tab.dragPayload) {
            title.font(DSFont.auxiliary).padding(DSSpacing.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDirty ? Text("\(title)、未保存") : title)
        .accessibilityValue(displayState.attentionKind != nil || activityState.showsActivityIndicator ? Text(verbatim: displayState.localizedLabel(locale: locale)) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: Text(closeHelp), onClose)
    }

    /// 未保存のファイルは ✕ の代わりに点。ホバーで ✕ に戻る（02 のタブ規則）。
    @ViewBuilder
    private var closeAccessory: some View {
        if isDirty, !isHovering, !isShown {
            Circle()
                .fill(DSColor.textPrimary)
                .frame(width: 6, height: 6)
                .frame(width: 14, height: 14)
        } else if isShown || isHovering {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(closeHelp))
            .accessibilityLabel(Text(closeHelp))
        }
    }

    private var closeHelp: String {
        tab.closeAccessibilityLabel
    }
}

extension ProjectTab {
    var dragPayload: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return "phlox-tab:" + data.base64EncodedString()
    }
    init?(dragPayload: String) {
        let prefix = "phlox-tab:"
        guard dragPayload.hasPrefix(prefix), let data = Data(base64Encoded: String(dragPayload.dropFirst(prefix.count))),
              let tab = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = tab
    }
}

// MARK: - New tab chooser (C4)

/// 「＋」と ⌘T で開くプロジェクト内タブの選択肢。
struct NewTabChooser: View {
    @Bindable var router: AppRouter
    let project: Project
    let simulatorHub: SimulatorHub?

    @Environment(\.localizationBundle) private var localizationBundle
    @FocusState private var focused: Item?

    enum Item: Hashable { case newChat, terminal, changes, file, browser, simulator }
    private let items: [Item] = [.newChat, .terminal, .changes, .file, .browser, .simulator]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { item in
                if item == .terminal || item == .browser {
                    Rectangle().fill(DSColor.separator).frame(height: 1).padding(.vertical, DSSpacing.xs)
                }
                row(item)
                    .focusable()
                    .focused($focused, equals: item)
                    .focusEffectDisabled()
            }
            Rectangle().fill(DSColor.separator).frame(height: 1).padding(.top, DSSpacing.xs)
            Text("ターミナル・変更・ファイルは \(project.name) のフォルダで開きます")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textSecondary)
                .lineSpacing(2)
                .padding(.horizontal, 8)
                .padding(.top, DSSpacing.xs)
        }
        .padding(5)
        .frame(width: 220)
        .background(DSColor.popoverBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("タブを追加"))
        .onAppear { focused = .newChat }
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
        return HStack {
            title(item)
                .font(DSFont.row)
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: DSSpacing.s)
            if item == .newChat {
                Text("⌘N")
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .dsPopupRowHighlight(isFocused)
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .onHover { if $0 { focused = item } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open(item) }
    }

    private func title(_ item: Item) -> Text {
        switch item {
        case .newChat: Text("新規チャット", bundle: localizationBundle)
        case .terminal: Text("ターミナル", bundle: localizationBundle)
        case .changes: Text("変更")
        case .file: Text("ファイルを開く…")
        case .browser: Text("ブラウザ")
        case .simulator: Text("シミュレーター")
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
        case .newChat: router.showNewChat(projectID: project.id)
        case .terminal: router.openTerminalTab()
        case .changes: router.openChildTab(.changes)
        case .browser: router.openChildTab(.browser)
        case .simulator:
            router.openChildTab(.simulator)
            simulatorHub?.requestMenuFocus(for: project.id)
        case .file: router.tabRequest = .openFile(project.id)
        }
    }
}

// MARK: - Panes (split)

/// 子タブの中身。分割中は左右に並べ、区切りをドラッグで動かせる（既定 50:50・最小 320pt）。
/// 子タブを右半分へドラッグすると右に分割して開く（C6）。
private struct ChildTabPanes<Content: View>: View {
    @Bindable var router: AppRouter
    let projectID: ProjectID
    let layout: ProjectTabLayout
    let chats: [ProjectTab]
    @ViewBuilder let content: (ProjectTab) -> Content

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
                    focusablePane(layout.left ?? chats.first ?? .newChat, isFocused: !layout.focusesRight)
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
                            router.tabs.updateLayout(for: projectID) { $0.splitFraction = committed }
                            dragFraction = nil
                        },
                        onDoubleClick: { router.tabs.updateLayout(for: projectID) { $0.splitFraction = 0.5 } }
                    )
                    .offset(x: leftWidth + 0.5 - DSLayout.dividerHitWidth / 2)
                }
            } else {
                // 分割が入らない幅では操作中のタブだけを出す。
                content(layout.selected ?? chats.first ?? .newChat)
                    .frame(width: width, height: geometry.size.height)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let tab = items.first.flatMap(ProjectTab.init(dragPayload:)), layout.tabs(chats: chats).contains(tab) else { return false }
            router.splitRight(tab, in: projectID, chats: chats)
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
    private func focusablePane(_ tab: ProjectTab, isFocused: Bool) -> some View {
        content(tab)
            .overlay {
                if isFocused {
                    Rectangle().strokeBorder(DSColor.accent.opacity(0.6), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                guard !isFocused else { return }
                router.selectTab(tab, in: projectID)
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
    let projectID: ProjectID
    let path: String
    let workingDirectory: String
    let currentWorkingDirectory: () -> String?
    let lastWriter: (FileTabDocument) -> String?
    let isFocused: Bool
    let openBrowser: (URL) -> Void
    let openFile: (String, String) -> Void
    @State private var restoredDocument: FileTabDocument?

    private var changingWorkspace: Bool { FileTabDocumentRegistry.shared.isChangingProject(projectID) }

    var body: some View {
        Group {
            if !changingWorkspace,
               let document = files.existing(for: projectID, path: path) ?? restoredDocument, !document.invalidated {
                FileTabUndoScope(document: document, isFocused: isFocused) {
                    FileTabView(document: document, lastWriter: lastWriter, isFocused: isFocused, openFile: openFile, openBrowser: openBrowser)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(workingDirectory)-\(changingWorkspace)") {
            guard !changingWorkspace else { return }
            guard files.existing(for: projectID, path: path) == nil else { return }
            restoredDocument = nil
            let root = await FileTabOpening.root(for: workingDirectory)
            guard !Task.isCancelled, !changingWorkspace,
                  currentWorkingDirectory() == workingDirectory else { return }
            restoredDocument = files.document(for: projectID, path: path, root: root)
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
                                   isEditable: !document.isReadOnly, isTemporarilyLocked: document.fileOperationInProgress,
                                   readOnlyText: document.readOnlyText)
                        .disabled(document.invalidated)
                }
            case .unloaded, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(document.fileOperationInProgress)
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
            .disabled(!isFocused || document.isReadOnly || document.fileOperationInProgress)
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

    /// 先にパスを縮め、次に「ブラウザで開く」の文字、補助の文言、最後に表示切替のアイコンを縮める。
    private var toolbar: some View {
        let pathWidth = FilePathDisplay.minimumReadableWidth(document.path)
        return ViewThatFits(in: .horizontal) {
            toolbarContents(reason: true, unsaved: true, keyHint: true, icons: false, minimumPathWidth: pathWidth)
            toolbarContents(reason: true, unsaved: true, keyHint: true, icons: false, browserIcon: true, minimumPathWidth: pathWidth)
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

    private func toolbarContents(reason showsReason: Bool, unsaved showsUnsaved: Bool, keyHint: Bool, icons: Bool,
                                 browserIcon: Bool = false, minimumPathWidth: CGFloat) -> some View {
        let browserIcon = browserIcon || !showsReason
        return HStack(spacing: DSSpacing.s) {
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
                            Label { if !browserIcon { Text("ブラウザで開く") } } icon: { Image(systemName: "globe") }
                        }
                        .buttonStyle(.ds(.secondary, height: 20, fontSize: 11, padding: browserIcon ? 4 : 8))
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
        document.isLoaded && !document.isReadOnly && !document.fileOperationInProgress && !document.invalidated && document.hasUnsavedChanges && document.blockEditFailure == nil
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
