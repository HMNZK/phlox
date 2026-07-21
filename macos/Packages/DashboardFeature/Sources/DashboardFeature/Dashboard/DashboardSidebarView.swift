import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

struct DashboardSidebarView<NewSessionMenuContent: View>: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Binding var expandedProjectIDs: Set<ProjectID>
    @Binding var draftName: String
    @Binding var renamingProject: Project?
    @Binding var pendingProjectDeletion: Project?
    @Binding var renamingSession: SelectedSessionNode?
    @Binding var pendingDeletion: SelectedSessionNode?
    @Binding var pendingWorkspaceChange: SessionViewModel?
    @Binding var sessionTreeViewModel: SessionTreeViewModel
    let onChooseProjectDirectory: () -> Void
    let onMoveSessionToProject: (SessionID, ProjectID) async -> Void
    let newSessionMenuItems: (ProjectID?) -> NewSessionMenuContent

    init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        expandedProjectIDs: Binding<Set<ProjectID>>,
        draftName: Binding<String>,
        renamingProject: Binding<Project?>,
        pendingProjectDeletion: Binding<Project?>,
        renamingSession: Binding<SelectedSessionNode?>,
        pendingDeletion: Binding<SelectedSessionNode?>,
        pendingWorkspaceChange: Binding<SessionViewModel?>,
        sessionTreeViewModel: Binding<SessionTreeViewModel>,
        onChooseProjectDirectory: @escaping () -> Void,
        onMoveSessionToProject: @escaping (SessionID, ProjectID) async -> Void,
        @ViewBuilder newSessionMenuItems: @escaping (ProjectID?) -> NewSessionMenuContent
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _expandedProjectIDs = expandedProjectIDs
        _draftName = draftName
        _renamingProject = renamingProject
        _pendingProjectDeletion = pendingProjectDeletion
        _renamingSession = renamingSession
        _pendingDeletion = pendingDeletion
        _pendingWorkspaceChange = pendingWorkspaceChange
        _sessionTreeViewModel = sessionTreeViewModel
        self.onChooseProjectDirectory = onChooseProjectDirectory
        self.onMoveSessionToProject = onMoveSessionToProject
        self.newSessionMenuItems = newSessionMenuItems
    }

    var body: some View {
        Group {
            if viewModel.projects.isEmpty {
                sidebarEmptyState
            } else {
                VStack(spacing: 0) {
                    sidebarProjectTitleBar
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.bottom, DSSpacing.xs)
                    List {
                        ForEach(viewModel.projects) { project in
                            projectHeader(project)
                                .listRowSeparator(.hidden)
                            if isProjectExpanded(project.id) {
                                projectSessionRows(project)
                            }
                        }
                        if !viewModel.unassignedSessionNodes.isEmpty {
                            Section("その他") {
                                ForEach(viewModel.unassignedSessionNodes, id: \.id) { session in
                                    sessionSidebarRow(session)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        // hiddenTitleBar ではトラフィックライト領域にサイドバーが食い込むため上余白を確保する。
        .padding(.top, 28)
    }

    private var sidebarProjectTitleBar: some View {
        HStack(spacing: DSSpacing.s) {
            Text("Projects")
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
            Spacer(minLength: 0)
            Button {
                onChooseProjectDirectory()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help("プロジェクトを追加")
        }
    }

    private func projectHeader(_ project: Project) -> some View {
        let isExpanded = isProjectExpanded(project.id)
        let isFilterSelected = router.gridFilterProjectID == project.id
        let isProjectSelected = router.selectedProjectID == project.id
        let requiresAttention = viewModel.hasAttention(in: project.id)
        return ProjectSidebarHeader(
            projectName: project.name,
            isExpanded: isExpanded,
            isFilterSelected: isFilterSelected,
            isProjectSelected: isProjectSelected,
            hasUnseenCompletion: requiresAttention,
            onToggleExpansion: {
                withAnimation(.easeInOut(duration: 0.12)) {
                    toggleProjectExpansion(project.id)
                }
            },
            onSelectProject: {
                router.selectProject(project.id)
            },
            onToggleFilter: {
                router.selectProjectFromSidebar(project.id)
            },
            onRename: {
                renamingProject = project
                draftName = project.name
            },
            onDelete: {
                pendingProjectDeletion = project
            },
            newSessionMenu: {
                newSessionMenuItems(project.id)
            }
        )
    }

    @ViewBuilder
    private func projectSessionRows(_ project: Project) -> some View {
        ForEach(sessionTreeViewModel.rows(from: viewModel.sessionForest(in: project.id))) { row in
            if let session = viewModel.sessionNode(id: row.id) {
                sessionSidebarRow(session, treeRow: row)
            }
        }
    }

    private func sessionSidebarRow(_ session: SessionNode) -> some View {
        SessionSidebarRowView(
            session: session,
            treeRow: nil,
            isSelected: router.selectedSession == session.id
        ) {
            router.selectedSession = session.id
        } onToggleExpansion: {}
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: DSSpacing.xxs,
                leading: DSSpacing.s,
                bottom: DSSpacing.xxs,
                trailing: DSSpacing.s
            ))
            .contextMenu {
                sessionContextMenu(for: session)
            }
    }

    private func sessionSidebarRow(_ session: SessionNode, treeRow: SessionTreeViewModel.Row) -> some View {
        SessionSidebarRowView(
            session: session,
            treeRow: treeRow,
            isSelected: router.selectedSession == session.id
        ) {
            router.selectedSession = session.id
        } onToggleExpansion: {
            withAnimation(.easeInOut(duration: 0.12)) {
                if let projectID = treeRow.projectID ?? session.projectID {
                    sessionTreeViewModel.toggleExpansion(for: treeRow.id, in: viewModel.sessionForest(in: projectID))
                }
            }
        }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: DSSpacing.xxs,
                leading: DSSpacing.s,
                bottom: DSSpacing.xxs,
                trailing: DSSpacing.s
            ))
            .contextMenu {
                sessionContextMenu(for: session)
            }
    }

    @ViewBuilder
    private func sessionContextMenu(for session: SessionNode) -> some View {
        Button("名前を変更") {
            renamingSession = SelectedSessionNode(session)
            draftName = session.name
        }
        if let pty = session.pty, session.projectID == nil {
            Button("プロジェクトを変更") {
                pendingWorkspaceChange = pty
            }
        } else if session.pty != nil, let currentProjectID = session.projectID {
            let destinationProjects = viewModel.projects.filter { $0.id != currentProjectID }
            if !destinationProjects.isEmpty {
                Menu("別のプロジェクトへ移動") {
                    ForEach(destinationProjects) { project in
                        Button(project.name) {
                            Task {
                                await onMoveSessionToProject(session.id, project.id)
                            }
                        }
                    }
                }
            }
        }
        Button("削除", role: .destructive) {
            pendingDeletion = SelectedSessionNode(session)
        }
    }

    private func isProjectExpanded(_ projectID: ProjectID) -> Bool {
        expandedProjectIDs.contains(projectID)
    }

    private func toggleProjectExpansion(_ projectID: ProjectID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DSColor.textTertiary)
            Text("プロジェクトがありません")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.textSecondary)
            Button {
                onChooseProjectDirectory()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: DSIconSize.l, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help("プロジェクトを追加")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.l)
    }
}

private struct ProjectSidebarHeader<NewSessionMenuContent: View>: View {
    let projectName: String
    let isExpanded: Bool
    let isFilterSelected: Bool
    let isProjectSelected: Bool
    let hasUnseenCompletion: Bool
    let onToggleExpansion: () -> Void
    let onSelectProject: () -> Void
    let onToggleFilter: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let newSessionMenu: () -> NewSessionMenuContent

    @State private var isHovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    init(
        projectName: String,
        isExpanded: Bool,
        isFilterSelected: Bool,
        isProjectSelected: Bool,
        hasUnseenCompletion: Bool,
        onToggleExpansion: @escaping () -> Void,
        onSelectProject: @escaping () -> Void,
        onToggleFilter: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder newSessionMenu: @escaping () -> NewSessionMenuContent
    ) {
        self.projectName = projectName
        self.isExpanded = isExpanded
        self.isFilterSelected = isFilterSelected
        self.isProjectSelected = isProjectSelected
        self.hasUnseenCompletion = hasUnseenCompletion
        self.onToggleExpansion = onToggleExpansion
        self.onSelectProject = onSelectProject
        self.onToggleFilter = onToggleFilter
        self.onRename = onRename
        self.onDelete = onDelete
        self.newSessionMenu = newSessionMenu
    }

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help(isExpanded ? "折りたたむ" : "展開")

            Button(action: onSelectProject) {
                projectIcon
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help("このプロジェクトを選択")

            Text(projectName)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleFilter)
                .help("このプロジェクトを選択")

            Menu {
                Button("名前を変更", action: onRename)
                Button("削除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(actionOpacity)
            .help("プロジェクト操作")

            Menu {
                newSessionMenu()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("このプロジェクトで新規セッションを開始")
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(
            backgroundFill,
            in: RoundedRectangle(cornerRadius: DSRadius.s)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("名前を変更", action: onRename)
            Button("削除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var projectIcon: some View {
        if let opacity = ProjectIconPolicy.opacity(hasUnseenCompletion: hasUnseenCompletion) {
            Image(systemName: "tray.full")
                .font(.system(size: DSIconSize.s, weight: .regular))
                .foregroundStyle(DSColor.textSecondary)
                .opacity(opacity)
                .frame(width: 16, height: 16)
        } else {
            Color.clear
                .frame(width: 16, height: 16)
        }
    }

    private var actionOpacity: Double {
        isHovering ? 1 : 0
    }

    private var backgroundFill: Color {
        if isFilterSelected || isProjectSelected { return DSColor.fillSelected }
        if isHovering { return DSColor.fillSubtle }
        return .clear
    }
}

private struct SessionSidebarRowView: View {
    let session: SessionNode
    let treeRow: SessionTreeViewModel.Row?
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleExpansion: () -> Void
    @State private var isHovering = false
    // テーマ変更で再描画して色を更新する。
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            expansionControl
            StatusDot(status: session.status)
            AgentSessionIcon(descriptor: session.agentDescriptor, status: session.status, size: 16)
            Text(session.displayName)
                .font(session.name.isEmpty ? DSFont.mono : DSFont.body)
                .foregroundStyle(session.name.isEmpty ? DSColor.textTertiary : DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DSSpacing.s)
            TimelineView(.periodic(from: session.startedAt, by: 60)) { timeline in
                Text(SidebarRelativeTime.label(from: session.startedAt, to: timeline.date))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .fixedSize()
            }
        }
        .padding(.leading, CGFloat(treeRow?.depth ?? 0) * 16)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.m)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .pointingHandCursor()
        .help(session.workspacePath)
    }

    @ViewBuilder
    private var expansionControl: some View {
        if let treeRow, treeRow.hasChildren {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(treeRow.isExpanded ? 90 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help(treeRow.isExpanded ? "折りたたむ" : "展開")
        } else if treeRow != nil {
            Color.clear
                .frame(width: 16, height: 16)
        }
    }

    private var requiresAttention: Bool {
        SessionAttentionPolicy.requiresAttention(
            status: session.status,
            hasUnseenCompletion: session.hasUnseenCompletion
        )
    }

    private var backgroundFill: Color {
        if isSelected { return DSColor.sessionRowSelected }
        if isHovering { return DSColor.sessionRowHover }
        if requiresAttention { return DSColor.idleHighlight }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return DSColor.sessionRowSelectedBorder }
        if isHovering { return DSColor.sessionRowHoverBorder }
        return .clear
    }
}
