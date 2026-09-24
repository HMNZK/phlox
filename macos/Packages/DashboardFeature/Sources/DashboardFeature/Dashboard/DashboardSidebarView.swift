import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 移動・割り当ての再起動確認（03 F9）に渡す内容。
struct PendingSessionMove: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let sessionTitle: String
    let project: Project
}

/// サイドバー（03）。上から「対応待ち」→「プロジェクト」→「その他（未割当）」。
/// 対応待ちの節は固定し、スクロールするのはプロジェクト以下だけ。スクロール中はプロジェクト行を上端に貼り付ける。
struct DashboardSidebarView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Binding var expandedProjectIDs: Set<ProjectID>
    @Binding var pendingProjectDeletion: Project?
    @Binding var pendingDeletion: SelectedSessionNode?
    @Binding var pendingWorkspaceChange: SessionViewModel?
    @Binding var pendingMove: PendingSessionMove?
    /// メニューバーの「名前を変更…」から来た要求。受けたら nil に戻す。
    @Binding var renameRequest: SessionID?
    @Binding var sessionTreeViewModel: SessionTreeViewModel
    let onChooseProjectDirectory: () -> Void
    /// プロジェクト行の ＋ と右クリックの「新規セッション…」で開く表（Sidebar F4・F5）。
    let newSessionTable: (ProjectID?) -> NewSessionTable

    @Environment(\.locale) private var locale
    @FocusState private var listFocused: Bool
    @State private var renaming: SidebarItem?
    @State private var renameDraft = ""
    @State private var unreadExpanded = false
    @State private var typeSelectBuffer = ""
    @State private var typeSelectAt = Date.distantPast
    /// キーで選んだ直後は、開いたターミナル・入力欄が入力先を取っても一覧に戻す（↑↓ で続けて動けるように）。
    /// クリックで選んだときは戻さない（ユーザーがすぐ入力欄を押した場合に奪わない）。
    @State private var holdFocusUntil = Date.distantPast

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        expandedProjectIDs: Binding<Set<ProjectID>>,
        pendingProjectDeletion: Binding<Project?>,
        pendingDeletion: Binding<SelectedSessionNode?>,
        pendingWorkspaceChange: Binding<SessionViewModel?>,
        pendingMove: Binding<PendingSessionMove?>,
        renameRequest: Binding<SessionID?>,
        sessionTreeViewModel: Binding<SessionTreeViewModel>,
        onChooseProjectDirectory: @escaping () -> Void,
        newSessionTable: @escaping (ProjectID?) -> NewSessionTable
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _expandedProjectIDs = expandedProjectIDs
        _pendingProjectDeletion = pendingProjectDeletion
        _pendingDeletion = pendingDeletion
        _pendingWorkspaceChange = pendingWorkspaceChange
        _pendingMove = pendingMove
        _renameRequest = renameRequest
        _sessionTreeViewModel = sessionTreeViewModel
        self.onChooseProjectDirectory = onChooseProjectDirectory
        self.newSessionTable = newSessionTable
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsAttentionSection {
                attentionSection
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                        tree
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                // 名前変更の案内は行の外で描く（LazyVStack では zIndex が効かず、下の行に隠れるため）。
                // 見えている範囲で測り、下に収まらなければ欄の上に出す。
                .overlayPreferenceValue(SidebarRenameHintKey.self) { hint in
                    if let hint { SidebarRenameHintBubble(hint: hint) }
                }
                .onChange(of: currentItem) { _, item in
                    guard let item, listFocused else { return }
                    withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(item) }
                }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onChange(of: listFocused) { _, isFocused in
            if !isFocused, renaming == nil, Date() < holdFocusUntil {
                listFocused = true
            }
        }
        .onKeyPress(phases: .down, action: handleKey)
        // サイドバーを出した直後に届いた依頼も拾う（隠れていた間は onChange が動かないため）。
        .onChange(of: renameRequest, initial: true) { _, id in
            guard let id else { return }
            renameRequest = nil
            revealAndRename(id)
        }
        .onChange(of: router.projectRenameRequest, initial: true) { _, id in
            guard let id else { return }
            router.projectRenameRequest = nil
            beginRename(.project(id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("プロジェクトとセッション"))
    }

    // MARK: - 対応待ち

    private var attentionNodes: [(entry: AttentionEntry, node: SessionNode)] {
        viewModel.attentionEntries.compactMap { entry in
            viewModel.sessionNode(id: entry.id).map { (entry, $0) }
        }
    }

    private var showsAttentionSection: Bool {
        !viewModel.projects.isEmpty && (!viewModel.attentionEntries.isEmpty || !viewModel.unseenCompletionNodes.isEmpty)
    }

    private var attentionSection: some View {
        let attention = attentionNodes
        let unread = viewModel.unseenCompletionNodes
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("対応待ち")
                if !attention.isEmpty {
                    Text(verbatim: "\(attention.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 15)
                        .background(DSColor.accentFill, in: Capsule())
                }
                Spacer(minLength: 0)
                Text("待ち時間順")
                    .fontWeight(.regular)
            }
            .font(DSFont.meta.weight(.semibold))
            .foregroundStyle(DSColor.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            ForEach(attention, id: \.node.id) { item in
                SidebarAttentionRow(
                    node: item.node,
                    since: item.entry.since,
                    projectName: projectName(for: item.node),
                    isSelected: router.selectedSession == item.node.id
                ) {
                    selectSession(item.node.id, holdFocus: false)
                }
            }
            if !unread.isEmpty {
                unreadSummaryRow(unread)
                if unreadExpanded, unread.count > 1 {
                    ForEach(unread, id: \.id) { node in
                        SidebarAttentionRow(
                            node: node,
                            since: node.statusEnteredAt,
                            projectName: projectName(for: node),
                            isSelected: router.selectedSession == node.id
                        ) {
                            selectSession(node.id, holdFocus: false)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("対応待ち"))
    }

    /// 未読の完了は 1 行にまとめ、押すと展開する（1 件ならそのセッションを開く）。
    private func unreadSummaryRow(_ unread: [SessionNode]) -> some View {
        let text = unread.count == 1
            ? Text("未読の完了 1 件 — \(unread[0].displayName)")
            : Text("未読の完了 \(unread.count) 件")
        return Button {
            if unread.count == 1 {
                selectSession(unread[0].id, holdFocus: false)
            } else {
                unreadExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(DSColor.accent)
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 3)
                text
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "›")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textTertiary)
                    .rotationEffect(.degrees(unreadExpanded && unread.count > 1 ? 90 : 0))
            }
            .font(DSFont.auxiliary)
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    // MARK: - プロジェクトとその他

    @ViewBuilder
    private var tree: some View {
        let unassigned = viewModel.unassignedSessionNodes
        // プロジェクトが無く未割当だけが残る場合は「その他」だけを出す（03 S3）。
        if !viewModel.projects.isEmpty || unassigned.isEmpty {
            projectsHeading
        }
        if viewModel.projects.isEmpty, unassigned.isEmpty {
            emptyState
        }
        ForEach(viewModel.projects) { project in
            Section {
                if isProjectExpanded(project.id) {
                    projectSessionRows(project)
                }
            } header: {
                projectRow(project)
                    .padding(.top, 4)
                    .background(DSColor.sidebarBackground)
            }
        }
        if !unassigned.isEmpty {
            Text("その他（プロジェクト未割当）")
                .font(DSFont.meta.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 3)
            ForEach(unassigned, id: \.id) { node in
                sessionRow(node, depth: 1, treeRow: nil, forest: [])
            }
        }
    }

    private var projectsHeading: some View {
        HStack(spacing: 6) {
            Text(UIWording.text(.projectsHeading, languageCode: languageCode))
                .font(DSFont.meta.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onChooseProjectDirectory) {
                Text(verbatim: "＋")
                    .font(.system(size: 14))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help(Text("プロジェクトを追加（⌘O）"))
            .accessibilityLabel(Text("プロジェクトを追加（⌘O）"))
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            FolderShape()
                .stroke(DSColor.textTertiary, lineWidth: 1.7)
                .frame(width: 34, height: 28)
                .accessibilityHidden(true)
            Text("プロジェクトがありません")
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text("作業フォルダを追加すると、そのフォルダでエージェントを起動できます。")
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4.5)
            Button(action: onChooseProjectDirectory) {
                HStack(spacing: 6) {
                    Text("フォルダを追加…")
                        .font(DSFont.auxiliary.weight(.semibold))
                    Text(verbatim: "⌘O")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 48)
    }

    private func projectRow(_ project: Project) -> some View {
        let isExpanded = isProjectExpanded(project.id)
        let states = projectSessionIDs(project.id).compactMap { viewModel.sessionNode(id: $0)?.tabDisplayState }
        return SidebarProjectRow(
            project: project,
            isExpanded: isExpanded,
            isSelected: router.selectedProjectID == project.id,
            isScoped: router.gridFilterProjectID == project.id,
            showsScopeMark: router.viewMode == .grid && router.gridFilterProjectID == project.id,
            collapsedSummary: .make(states),
            running: viewModel.runningBreakdown(in: project.id),
            sessionCount: states.count,
            isRenaming: renaming == .project(project.id),
            renameDraft: $renameDraft,
            onSelect: { commandPressed in
                listFocused = true
                if commandPressed {
                    router.clearProjectScope()
                } else {
                    router.selectProjectFromSidebar(project.id)
                }
            },
            onToggleExpansion: { toggleProjectExpansion(project.id) },
            onCommitRename: { commitRename(byReturn: $0) },
            onCancelRename: cancelRename,
            menu: { projectMenu(project) },
            newSessionMenu: { newSessionTable(project.id) }
        )
        .id(SidebarItem.project(project.id))
    }

    @ViewBuilder
    private func projectSessionRows(_ project: Project) -> some View {
        let forest = viewModel.sessionForest(in: project.id)
        ForEach(sessionTreeViewModel.rows(from: forest)) { row in
            if let node = viewModel.sessionNode(id: row.id) {
                sessionRow(node, depth: row.depth + 1, treeRow: row, forest: forest)
            }
        }
    }

    private func sessionRow(
        _ node: SessionNode,
        depth: Int,
        treeRow: SessionTreeViewModel.Row?,
        forest: [SessionTreeNode]
    ) -> some View {
        let children = treeRow?.hasChildren == true ? Self.findNode(node.id, in: forest)?.children ?? [] : []
        let descendantStates = children.flatMap(Self.flatten).compactMap { viewModel.sessionNode(id: $0.id)?.tabDisplayState }
        return SidebarSessionRow(
            node: node,
            depth: depth,
            hasChildren: treeRow?.hasChildren ?? false,
            isExpanded: treeRow?.isExpanded ?? false,
            childCount: children.count,
            descendantSummary: .make(descendantStates),
            isSelected: router.selectedSession == node.id,
            isRenaming: renaming == .session(node.id),
            renameDraft: $renameDraft,
            onSelect: { selectSession(node.id, holdFocus: false) },
            onToggleExpansion: { toggleSessionExpansion(node.id, projectID: treeRow?.projectID ?? node.projectID) },
            onCommitRename: { commitRename(byReturn: $0) },
            onCancelRename: cancelRename,
            menu: { sessionMenu(node) }
        )
        .id(SidebarItem.session(node.id))
    }

    // MARK: - メニュー（⋯ と右クリックで同じもの）

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        // 03 F4: 押すと F5 の表（下端の「新規セッション」と同じ）をこのプロジェクトで開く。
        Button("新規セッション…") {
            router.selectProject(project.id)
            router.newSessionTablePresented = true
        }
        Divider()
        Button("名前を変更…") { beginRename(.project(project.id)) }
        Toggle("git worktree で隔離する", isOn: Binding(
            get: { viewModel.projects.first { $0.id == project.id }?.usesWorktreeIsolation ?? false },
            set: { viewModel.setWorktreeIsolationEnabled($0, for: project.id) }
        ))
        Divider()
        Button("プロジェクトを削除…", role: .destructive) {
            pendingProjectDeletion = project
        }
    }

    @ViewBuilder
    private func sessionMenu(_ node: SessionNode) -> some View {
        Button("名前を変更…") { beginRename(.session(node.id)) }
        // 「別のプロジェクトへ移動」と「プロジェクトを変更（フォルダを選ぶ）」を 1 つにまとめる（03 F2・F3）。
        // チャット型は所属だけを移すので、フォルダ選択と再起動の注記は出さない。
        Menu(node.projectID == nil ? "プロジェクトに割り当てる" : "プロジェクトを移動") {
            let canMove = viewModel.canMoveSession(node.id)
            ForEach(viewModel.projects.filter { $0.id != node.projectID }) { project in
                Button {
                    if node.pty == nil {
                        router.sidebarRequest = .moveSession(node.id, project.id)
                    } else {
                        pendingMove = PendingSessionMove(sessionID: node.id, sessionTitle: node.displayName, project: project)
                    }
                } label: {
                    Label(project.name, systemImage: "folder")
                }
                .disabled(!canMove)
            }
            if !canMove {
                Text("worktree で動いているチャットは移動できません")
            }
            if let pty = node.pty {
                Divider()
                Button("フォルダを選択…") { pendingWorkspaceChange = pty }
                Text("移動するとセッションは再起動します")
            }
        }
        Divider()
        Button("セッションを削除…", role: .destructive) {
            pendingDeletion = SelectedSessionNode(node)
        }
    }

    // MARK: - 名前の変更（03 F6）

    private func beginRename(_ item: SidebarItem) {
        switch item {
        case .project(let id):
            renameDraft = viewModel.projects.first { $0.id == id }?.name ?? ""
        case .session(let id):
            renameDraft = viewModel.sessionNode(id: id)?.name ?? ""
        }
        renaming = item
    }

    private func cancelRename() {
        renaming = nil
        listFocused = true
    }

    /// セッションは空欄で短縮 ID 表示に戻す（空名の手動名。AcceptanceSessionTitleStateTests が凍結）。プロジェクトは空欄なら変えない（現行どおり）。
    /// ↩ で確定したときだけ一覧に入力先を戻す（ほかをクリックして確定したときはそのまま）。
    private func commitRename(byReturn: Bool) {
        guard let item = renaming else { return }
        renaming = nil
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        switch item {
        case .session(let id):
            viewModel.renameSession(id, to: name)
        case .project(let id):
            guard !name.isEmpty else { return }
            viewModel.renameProject(id, to: name)
        }
        if byReturn { listFocused = true }
    }

    /// メニューバーから名前を変える: 畳まれていれば行が見えるまで開いてから編集に入る。
    private func revealAndRename(_ id: SessionID) {
        guard let node = viewModel.sessionNode(id: id) else { return }
        if let projectID = node.projectID {
            expandedProjectIDs.insert(projectID)
            var parent = node.controllable.parentSessionID
            while let ancestor = parent {
                if !sessionTreeViewModel.isExpanded(ancestor) {
                    sessionTreeViewModel.toggleExpansion(for: ancestor, in: viewModel.sessionForest(in: projectID))
                }
                parent = viewModel.sessionNode(id: ancestor)?.controllable.parentSessionID
            }
        }
        beginRename(.session(id))
    }

    // MARK: - キーボード（03 キーボード）

    /// 画面に見えている行の順（プロジェクト → 展開した中のセッション → その他）。
    private var visibleItems: [(item: SidebarItem, name: String)] {
        var items: [(item: SidebarItem, name: String)] = []
        for project in viewModel.projects {
            items.append((.project(project.id), project.name))
            guard isProjectExpanded(project.id) else { continue }
            for row in sessionTreeViewModel.rows(from: viewModel.sessionForest(in: project.id)) {
                if let node = viewModel.sessionNode(id: row.id) {
                    items.append((.session(row.id), node.displayName))
                }
            }
        }
        for node in viewModel.unassignedSessionNodes {
            items.append((.session(node.id), node.displayName))
        }
        return items
    }

    private var currentItem: SidebarItem? {
        if let session = router.selectedSession { return .session(session) }
        return router.selectedProjectID.map(SidebarItem.project)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard renaming == nil else { return .ignored }
        let modifiers = press.modifiers.intersection([.command, .option, .control, .shift])
        switch (press.key, modifiers) {
        case (.upArrow, []):
            select(SidebarNavigation.step(from: currentItem, by: -1, in: visibleItems.map(\.item)))
        case (.downArrow, []):
            select(SidebarNavigation.step(from: currentItem, by: 1, in: visibleItems.map(\.item)))
        case (.leftArrow, []):
            collapseOrSelectParent()
        case (.rightArrow, []):
            expandCurrent()
        case (.return, []):
            guard let currentItem else { return .ignored }
            beginRename(currentItem)
        case (.delete, [.command]):
            // ⌘⌫ はサイドバーにフォーカスがあるときだけ（入力欄の「行頭まで消去」と取り合わない）。
            // プロジェクト行ではプロジェクトの削除の確認（キーボードだけでも届くように）。
            switch currentItem {
            case .session(let id):
                guard let node = viewModel.sessionNode(id: id) else { return .ignored }
                pendingDeletion = SelectedSessionNode(node)
            case .project(let id):
                guard let project = viewModel.projects.first(where: { $0.id == id }) else { return .ignored }
                pendingProjectDeletion = project
            case nil:
                return .ignored
            }
        default:
            return typeSelect(press, modifiers: modifiers)
        }
        return .handled
    }

    /// 文字入力で頭出し。1 秒以内に続けて打った文字はつなげて探す。
    private func typeSelect(_ press: KeyPress, modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isSubset(of: [.shift]),
              let scalar = press.characters.unicodeScalars.first,
              press.characters.unicodeScalars.count == 1,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) || !typeSelectBuffer.isEmpty else {
            return .ignored
        }
        let now = Date()
        typeSelectBuffer = now.timeIntervalSince(typeSelectAt) < 1 ? typeSelectBuffer + press.characters : press.characters
        typeSelectAt = now
        guard let match = SidebarNavigation.typeSelect(typeSelectBuffer, from: currentItem, in: visibleItems) else {
            return .handled
        }
        select(match)
        return .handled
    }

    /// キー操作（↑↓・←・頭出し）で選ぶ。
    private func select(_ item: SidebarItem?) {
        switch item {
        case .project(let id):
            holdFocus()
            router.showProject(id)
        case .session(let id):
            selectSession(id, holdFocus: true)
        case nil:
            break
        }
    }

    private func selectSession(_ id: SessionID, holdFocus shouldHold: Bool) {
        if shouldHold { holdFocus() } else { listFocused = true }
        router.commonTerminalSelected = false
        router.selectedSession = id
    }

    private func holdFocus() {
        holdFocusUntil = Date().addingTimeInterval(0.5)
        listFocused = true
    }

    private func collapseOrSelectParent() {
        switch currentItem {
        case .project(let id):
            if isProjectExpanded(id) { toggleProjectExpansion(id) }
        case .session(let id):
            guard let node = viewModel.sessionNode(id: id) else { return }
            if let projectID = node.projectID, sessionTreeViewModel.isExpanded(id),
               Self.findNode(id, in: viewModel.sessionForest(in: projectID))?.children.isEmpty == false {
                toggleSessionExpansion(id, projectID: projectID)
            } else if let parent = node.controllable.parentSessionID, viewModel.sessionNode(id: parent) != nil {
                selectSession(parent, holdFocus: true)
            } else if let projectID = node.projectID {
                router.showProject(projectID)
            }
        case nil:
            break
        }
    }

    private func expandCurrent() {
        switch currentItem {
        case .project(let id):
            if !isProjectExpanded(id) { toggleProjectExpansion(id) }
        case .session(let id):
            guard let projectID = viewModel.sessionNode(id: id)?.projectID, !sessionTreeViewModel.isExpanded(id) else { return }
            toggleSessionExpansion(id, projectID: projectID)
        case nil:
            break
        }
    }

    // MARK: - 展開

    private func isProjectExpanded(_ projectID: ProjectID) -> Bool {
        expandedProjectIDs.contains(projectID)
    }

    private func toggleProjectExpansion(_ projectID: ProjectID) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedProjectIDs.contains(projectID) {
                expandedProjectIDs.remove(projectID)
            } else {
                expandedProjectIDs.insert(projectID)
            }
        }
    }

    private func toggleSessionExpansion(_ id: SessionID, projectID: ProjectID?) {
        guard let projectID else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            sessionTreeViewModel.toggleExpansion(for: id, in: viewModel.sessionForest(in: projectID))
        }
    }

    // MARK: - Helpers

    private func projectSessionIDs(_ projectID: ProjectID) -> [SessionID] {
        viewModel.sessionForest(in: projectID).flatMap(Self.flatten).map(\.id)
    }

    private func projectName(for node: SessionNode) -> String? {
        guard let projectID = node.projectID else { return nil }
        return viewModel.projects.first { $0.id == projectID }?.name
    }

    private static func flatten(_ node: SessionTreeNode) -> [SessionTreeNode] {
        [node] + node.children.flatMap(flatten)
    }

    private static func findNode(_ id: SessionID, in nodes: [SessionTreeNode]) -> SessionTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id, in: node.children) { return found }
        }
        return nil
    }
}

/// 対応待ちの節の 1 行: タイトルと状態の文言、下に「プロジェクト · エージェント」と待ち時間。
private struct SidebarAttentionRow: View {
    let node: SessionNode
    let since: Date?
    let projectName: String?
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.locale) private var locale
    @State private var isHovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var state: SessionDisplayState { node.tabDisplayState }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let waited = since.map { SidebarRelativeTime.label(from: $0, to: context.date, locale: locale) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: node.displayName)
                        .font(DSFont.row)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: state.localizedLabel(locale: locale))
                        .font(DSFont.meta.weight(.semibold))
                        .foregroundStyle(state.color)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    subtitle
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let waited {
                        Text(verbatim: waited)
                            .foregroundStyle(DSColor.textTertiary)
                            .monospacedDigit()
                    }
                }
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? DSColor.selectionFill : isHovering ? DSColor.fillSubtle : Color.clear,
                in: RoundedRectangle(cornerRadius: DSRadius.row)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
        }
    }

    /// 「プロジェクト · エージェント」。未割当は「その他」。
    private var subtitle: Text {
        let project = projectName.map { Text(verbatim: $0) } ?? Text("その他")
        return project + Text(verbatim: " · \(node.agentDescriptor.displayName)")
    }

    /// 「承認待ち、タイトル、プロジェクト、3分前から」（モックの aria-label と同じ並び）。語は画面の言語設定で引く。
    private var accessibilityText: Text {
        var parts = [Text(verbatim: state.localizedLabel(locale: locale)), Text(verbatim: node.displayName)]
        if let projectName { parts.append(Text(verbatim: projectName)) }
        if let since {
            let relative = since.formatted(Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .wide, locale: locale))
            parts.append(Text("\(relative)から"))
        }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text("、") + $1 }
    }
}
