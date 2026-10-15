import AppKit
import DesignSystem
import SwiftUI

enum GitHistoryInput: Equatable {
    case branch(start: String)
    case rename(String)
    case stash
    var section: GitHistorySection { if case .stash = self { .stashes } else { .branches } }
    var title: String {
        switch self { case .branch: "新しいブランチ"; case .rename: "名前の変更"; case .stash: "スタッシュのメッセージ（任意）" }
    }
}

extension GitInspectorView {
    func expanded(_ section: GitHistorySection) -> Bool {
        switch section {
        case .commits: commitsExpanded
        case .branches: branchesExpanded
        case .remotes: remotesExpanded
        case .stashes: stashesExpanded
        case .graph: graphExpanded
        }
    }

    func setExpanded(_ section: GitHistorySection, _ value: Bool) {
        switch section {
        case .commits: commitsExpanded = value
        case .branches: branchesExpanded = value
        case .remotes: remotesExpanded = value
        case .stashes: stashesExpanded = value
        case .graph: graphExpanded = value
        }
        historyMenu = nil
        if !value {
            focusedArea = .historyHeader(section)
            if input?.section == section { input = nil }
        }
        Task { await model.setHistorySection(section, expanded: value) }
    }

    func sectionCount(_ section: GitHistorySection) -> Int {
        switch section {
        case .commits: model.historyCommits.count
        case .branches: model.localBranches.count
        case .remotes: model.remoteBranches.count
        case .stashes: model.gitStashes.count
        case .graph: model.graphRows.count
        }
    }

    func historyHeader(_ section: GitHistorySection) -> some View {
        HStack(spacing: DSSpacing.chip) {
            Button { setExpanded(section, !expanded(section)) } label: {
                HStack(spacing: DSSpacing.chip) {
                    Image(systemName: expanded(section) ? "chevron.down" : "chevron.right")
                    Text(LocalizedStringKey(section.title), bundle: bundle).font(DSFont.auxiliary.weight(.semibold))
                    if model.loadedHistorySections.contains(section) {
                        Text(verbatim: "\(sectionCount(section))").foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focusedArea, equals: .historyHeader(section)).focusEffectDisabled()
                .accessibilityLabel(Text(LocalizedStringKey(section.title), bundle: bundle))
                .accessibilityValue(Text(expanded(section) ? "展開中" : "折りたたみ中", bundle: bundle))
                .accessibilityIdentifier("git-section-\(section.rawValue)-toggle")
            if section == .branches || section == .stashes || section == .remotes {
                let key = section == .branches ? "新しいブランチ" : section == .stashes ? "スタッシュ" : "取得"
                Button {
                    if section == .branches { beginInput(.branch(start: "HEAD")) }
                    else if section == .stashes { beginInput(.stash) }
                    else { requestAction(.fetch) }
                } label: {
                    if section == .remotes && model.runningOperation == .fetch { ProgressView().controlSize(.mini) }
                    else if section == .remotes { Text("取得", bundle: bundle) }
                    else { Image(systemName: "plus") }
                }.buttonStyle(HoverableIconButtonStyle())
                    .frame(minWidth: DSSpacing.xl, minHeight: DSSpacing.xl)
                    .disabled(model.isWorkflowBusy || model.listState != .ready)
                    .help(Text(LocalizedStringKey(key), bundle: bundle))
                    .accessibilityLabel(Text(LocalizedStringKey(key), bundle: bundle))
                    .accessibilityIdentifier("git-section-\(section.rawValue)-action")
            }
        }.font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.m).frame(height: DSLayout.gitRowHeight)
            .background(DSColor.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
    }

    @ViewBuilder func historyContent(_ section: GitHistorySection) -> some View {
        if let input, input.section == section {
            if case .rename = input { EmptyView() } else { historyInput(input) }
        }
        if model.loadingHistorySections.contains(section) {
            ProgressView().controlSize(.small).padding(DSSpacing.s)
                .accessibilityLabel(Text("読み込んでいます…", bundle: bundle))
        }
        switch section {
        case .commits:
            ForEach(model.historyCommits) { commit in commitRow(commit, graph: nil) }
            if model.hasMoreCommits {
                Button { Task { await model.loadMoreCommits() } } label: { Text("続きを読む", bundle: bundle) }
                    .buttonStyle(.plain).font(DSFont.meta).padding(DSSpacing.m)
                    .disabled(model.loadingHistorySections.contains(.commits))
                    .accessibilityLabel(Text("続きを読む", bundle: bundle)).accessibilityIdentifier("git-commits-more")
            }
        case .branches:
            ForEach(model.localBranches) { branch in branchRow(branch, remote: false) }
        case .remotes:
            ForEach(Array(Set(model.remoteBranches.map(\.remote))).sorted(), id: \.self) { remote in
                Button { remoteExpansion[remote] = !remoteIsExpanded(remote); historyMenu = nil } label: {
                    HStack(spacing: DSSpacing.chip) {
                        Image(systemName: remoteIsExpanded(remote) ? "chevron.down" : "chevron.right")
                        Text(verbatim: remote).font(DSFont.meta.weight(.semibold))
                        Spacer(minLength: 0)
                        Text(verbatim: "\(model.remoteBranches.filter { $0.remote == remote }.count)")
                        if let date = model.lastFetchDate {
                            Text(verbatim: fetchLabel(date)).lineLimit(1)
                        }
                    }.font(DSFont.meta).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.m).frame(height: DSLayout.gitRowHeight)
                    .accessibilityLabel(Text(verbatim: remote))
                    .accessibilityValue(Text(remoteIsExpanded(remote) ? "展開中" : "折りたたみ中", bundle: bundle))
                    .accessibilityIdentifier("git-remote-\(remote)-toggle")
                if remoteIsExpanded(remote) {
                    ForEach(model.remoteBranches.filter { $0.remote == remote }) { branch in branchRow(branch, remote: true) }
                }
            }
        case .stashes:
            ForEach(model.gitStashes) { stash in stashRow(stash) }
        case .graph:
            ForEach(model.graphRows, id: \.commit.id) { row in commitRow(row.commit, graph: row) }
            if model.hasMoreGraph {
                Button { Task { await model.loadMoreGraph() } } label: { Text("続きを読む", bundle: bundle) }
                    .buttonStyle(.plain).font(DSFont.meta).padding(DSSpacing.m)
                    .disabled(model.loadingHistorySections.contains(.graph))
                    .accessibilityLabel(Text("続きを読む", bundle: bundle)).accessibilityIdentifier("git-graph-more")
            }
        }
        if sectionCount(section) == 0 && model.loadedHistorySections.contains(section) {
            let key = switch section {
            case .commits: "コミットはまだありません"
            case .branches: "ブランチはありません"
            case .remotes: "リモートはありません"
            case .stashes: "スタッシュはありません"
            case .graph: "最初のコミットの後に線が出ます"
            }
            Text(LocalizedStringKey(key), bundle: bundle).font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                .padding(DSSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func remoteIsExpanded(_ remote: String) -> Bool { remoteExpansion[remote] ?? (remote == "origin") }

    private func fetchLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        return String(format: AppLocalizedString.string("%@に取得", locale: locale, bundle: bundle),
                      formatter.localizedString(for: date, relativeTo: Date()))
    }

    func beginInput(_ value: GitHistoryInput) {
        setExpanded(value.section, true)
        input = value
        if case .rename(let name) = value { inputText = name } else { inputText = "" }
        historyInputFocused = true
    }

    func historyInput(_ value: GitHistoryInput) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if case .branch(let start) = value {
                Text("起点: \(start)", bundle: bundle).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
            }
            if case .stash = value {
                Text("未追跡を含む今の変更をしまいます", bundle: bundle).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
            }
            TextField(text: $inputText) { Text(LocalizedStringKey(value.title), bundle: bundle) }
                .textFieldStyle(.plain).font(DSFont.monoCaption).focused($historyInputFocused)
                .padding(DSSpacing.xs).background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: DSRadius.s))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.controlBorder, lineWidth: DSLayout.controlBorderWidth))
                .accessibilityLabel(Text(LocalizedStringKey(value.title), bundle: bundle))
                .accessibilityIdentifier("git-history-input")
                .onSubmit { submitInput(value) }
                .onExitCommand { input = nil; focusedArea = .list }
            HStack {
                Button { submitInput(value) } label: {
                    Text(value == .stash ? "スタッシュ" : "確定", bundle: bundle)
                }.disabled(model.isWorkflowBusy || value != .stash && inputText.isEmpty)
                    .accessibilityLabel(Text("確定", bundle: bundle)).accessibilityIdentifier("git-history-input-submit")
                Button { input = nil; focusedArea = .list } label: { Text("キャンセル", bundle: bundle) }
                    .accessibilityLabel(Text("キャンセル", bundle: bundle)).accessibilityIdentifier("git-history-input-cancel")
            }.buttonStyle(.plain).font(DSFont.meta)
        }.padding(DSSpacing.m)
    }

    func submitInput(_ value: GitHistoryInput) {
        guard !model.isWorkflowBusy, value == .stash || !inputText.isEmpty else { return }
        let action: GitRepositoryAction = switch value {
        case .branch(let start): .createBranch(name: inputText, start: start, switchTo: true)
        case .rename(let old): .renameBranch(old: old, new: inputText)
        case .stash: .stash(inputText)
        }
        requestAction(action)
    }

    func requestAction(_ action: GitRepositoryAction) {
        guard !model.isWorkflowBusy else { return }
        historyMenu = nil
        if action.needsConfirmation(runningSession: !runningSessionNames.isEmpty) { pendingAction = action }
        else { Task { await model.performRepositoryAction(action) } }
    }

    func commitRow(_ commit: GitHistoryCommit, graph: GitGraphRow?) -> some View {
        let row: GitHistoryRowID = .commit(commit.id, graph: graph != nil)
        let source = WorkingTreeSource.commit(commit.id)
        return VStack(spacing: 0) {
            HStack(spacing: DSSpacing.chip) {
                if let graph { GitGraphLines(row: graph).frame(width: GitGraphLines.width(graph.width), height: DSLayout.gitRowHeight * 2) }
                Image(systemName: model.expandedHistoryRows.contains(source) ? "chevron.down" : "chevron.right")
                    .font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    if graph != nil && !commit.refs.isEmpty {
                        graphBadges(commit.refs)
                    }
                    Text(verbatim: commit.summary).font(DSFont.row).lineLimit(1).truncationMode(.tail)
                    HStack(spacing: DSSpacing.chip) {
                        Text(verbatim: commit.author).lineLimit(1)
                        Text(commit.date, style: .relative).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: commit.shortID).font(DSFont.monoCaption)
                    }.font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                }
            }.padding(.horizontal, DSSpacing.s).padding(.vertical, graph == nil ? DSSpacing.xs : 0)
                .modifier(GitHistoryRowStyle(selected: model.activeGitRow == row))
                .onTapGesture { focusedArea = .list; model.activeGitRow = row; Task { await model.toggleHistoryRow(source) } }
                .contextMenu { historyActions(row) }
                .popover(isPresented: menuBinding(row)) {
                    VStack(alignment: .leading, spacing: DSSpacing.s) { historyActions(row) }.buttonStyle(.plain).padding(DSSpacing.m)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: commit.summary + ", " + commit.author + ", " + commit.refs.joined(separator: ", ") + ", " + commit.shortID))
                .accessibilityAction(named: Text("ID をコピー", bundle: bundle)) { copyCommitID(commit.id) }
                .accessibilityAction(named: Text("ここからブランチを作成", bundle: bundle)) { beginInput(.branch(start: commit.id)) }
                .accessibilityAction(named: Text("ファイルを展開", bundle: bundle)) { Task { await model.toggleHistoryRow(source) } }
                .accessibilityIdentifier("git-\(graph == nil ? "commit" : "graph")-\(commit.id)")
            if model.expandedHistoryRows.contains(source) {
                historyFileRows(source, graph: graph != nil)
                    .padding(.leading, graph.map { GitGraphLines.width($0.width) + DSSpacing.chip } ?? 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if let graph {
                            GitGraphLines(row: graph, continuation: true)
                                .frame(width: GitGraphLines.width(graph.width))
                                .padding(.leading, DSSpacing.s).allowsHitTesting(false)
                        }
                    }
            }
        }.id(row)
    }

    func branchRow(_ branch: GitBranch, remote: Bool) -> some View {
        let row: GitHistoryRowID = remote ? .remote(branch.name) : .branch(branch.name)
        return VStack(spacing: 0) {
        if input == .rename(branch.name) { historyInput(.rename(branch.name)) }
        else { HStack(spacing: DSSpacing.chip) {
            if model.runningRepositoryAction == (remote ? .checkoutRemote(branch.name) : .switchBranch(branch.name)) {
                ProgressView().controlSize(.mini).accessibilityLabel(Text("ブランチを操作しています…", bundle: bundle))
            } else { Image(systemName: branch.current ? "checkmark" : "arrow.branch").accessibilityHidden(true) }
            Text(verbatim: remote ? branch.localName : branch.name).font(branch.current ? DSFont.monoCaption.weight(.bold) : DSFont.monoCaption)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if remote && branch.tracked {
                Image(systemName: "link").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .help(Text("追跡中", bundle: bundle)).accessibilityLabel(Text("追跡中", bundle: bundle))
            }
            if branch.current && model.aheadCount > 0 { Text(verbatim: "↑\(model.aheadCount)").font(DSFont.meta).foregroundStyle(DSColor.textSecondary) }
        }.padding(.horizontal, DSSpacing.m).frame(height: DSLayout.gitRowHeight)
            .modifier(GitHistoryRowStyle(selected: model.activeGitRow == row))
            .onTapGesture(count: 2) { if !branch.current { requestAction(remote ? .checkoutRemote(branch.name) : .switchBranch(branch.name)) } }
            .onTapGesture { focusedArea = .list; model.activeGitRow = row }
            .contextMenu { historyActions(row) }
            .popover(isPresented: menuBinding(row)) {
                    VStack(alignment: .leading, spacing: DSSpacing.s) { historyActions(row) }.buttonStyle(.plain).padding(DSSpacing.m)
                }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: branch.name) + (branch.current ? Text("、今のブランチ", bundle: bundle) : Text("")))
            .accessibilityValue(Text(remote && branch.tracked ? "追跡中" : "", bundle: bundle))
            .accessibilityAction(named: Text(remote ? "チェックアウト" : "切り替え", bundle: bundle)) {
                requestAction(remote ? .checkoutRemote(branch.name) : .switchBranch(branch.name))
            }
            .accessibilityAction(named: Text("ここからブランチを作成", bundle: bundle)) { beginInput(.branch(start: (remote ? "refs/remotes/" : "refs/heads/") + branch.name)) }
            .accessibilityActions {
                if !remote {
                    actionButton("名前の変更", id: "vo-rename") { beginInput(.rename(branch.name)) }
                    if !branch.current {
                        actionButton("削除", id: "vo-delete-branch") {
                            Task { if let merged = await model.branchIsMerged(branch.name) { requestAction(.deleteBranch(branch.name, force: !merged)) } }
                        }
                    }
                }
            }
            .accessibilityIdentifier("git-\(remote ? "remote" : "branch")-\(branch.name)").id(row)
        }
        }
    }

    func stashRow(_ stash: GitStash) -> some View {
        let row = GitHistoryRowID.stash(stash.id)
        return VStack(spacing: 0) {
            HStack(spacing: DSSpacing.chip) {
                Image(systemName: model.expandedHistoryRows.contains(stash.source) ? "chevron.down" : "chevron.right").font(DSFont.meta)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(verbatim: stash.message).font(DSFont.row).lineLimit(1)
                    HStack {
                        Text(verbatim: stash.name)
                        Text(stash.date, style: .relative)
                    }.font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.xs)
                .modifier(GitHistoryRowStyle(selected: model.activeGitRow == row))
                .onTapGesture { focusedArea = .list; model.activeGitRow = row; Task { await model.toggleHistoryRow(stash.source) } }
                .contextMenu { historyActions(row) }
                .popover(isPresented: menuBinding(row)) {
                    VStack(alignment: .leading, spacing: DSSpacing.s) { historyActions(row) }.buttonStyle(.plain).padding(DSSpacing.m)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: stash.name + ", " + stash.message))
                .accessibilityAction(named: Text("適用", bundle: bundle)) { requestAction(.applyStash(stash.id)) }
                .accessibilityAction(named: Text("取り出す", bundle: bundle)) { requestAction(.popStash(stash.id)) }
                .accessibilityAction(named: Text("削除", bundle: bundle)) { requestAction(.dropStash(stash.id)) }
                .accessibilityIdentifier("git-stash-\(stash.id)").id(row)
            if model.expandedHistoryRows.contains(stash.source) { historyFileRows(stash.source, graph: false) }
        }
    }

    @ViewBuilder func historyFileRows(_ source: WorkingTreeSource, graph: Bool) -> some View {
        if let files = model.historyFiles[source] {
            if files.isEmpty {
                Text("変更はありません", bundle: bundle).font(DSFont.meta).foregroundStyle(DSColor.textTertiary).padding(DSSpacing.s)
            }
            ForEach(files, id: \.path) { file in
                let selection = GitChangeSelection(path: file.path, source: source)
                let row = GitHistoryRowID.file(selection, graph: graph)
                Button {
                    model.activeGitRow = row
                    openChanges(file.path, source, false)
                } label: {
                    HStack(spacing: DSSpacing.chip) {
                        Text(verbatim: GitTabPolicy.letter(file.kind)).font(DSFont.monoCaption).foregroundStyle(editorChangeColor(for: file))
                        Text(verbatim: (file.path as NSString).lastPathComponent).font(DSFont.row).lineLimit(1)
                        Text(verbatim: (file.path as NSString).deletingLastPathComponent).font(DSFont.meta)
                            .foregroundStyle(DSColor.textSecondary).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 0)
                    }.padding(.leading, DSSpacing.xl).padding(.trailing, DSSpacing.s).frame(height: DSLayout.gitRowHeight)
                        .modifier(GitHistoryRowStyle(selected: model.activeGitRow == row))
                }.buttonStyle(.plain)
                    .help(Text(verbatim: file.path))
                    .accessibilityLabel(Text(verbatim: file.path))
                    .accessibilityIdentifier("git-\(graph ? "graph" : "history")-file-\(source.rawValue)-\(file.path)").id(row)
            }
        } else { ProgressView().controlSize(.small).padding(DSSpacing.s) }
    }

    func menuBinding(_ row: GitHistoryRowID) -> Binding<Bool> {
        Binding(get: { historyMenu == row && visibleRows.contains(row) }, set: { if !$0 { historyMenu = nil } })
    }

    @ViewBuilder func historyActions(_ row: GitHistoryRowID) -> some View {
        switch row {
        case .commit(let id, _):
            actionButton("ID をコピー", id: "copy-id") { copyCommitID(id) }
            actionButton("ここからブランチを作成", id: "branch-from-commit") { beginInput(.branch(start: id)) }
        case .branch(let name):
            actionButton("切り替え", id: "switch") { requestAction(.switchBranch(name)) }.disabled(name == model.branchLabel || model.isWorkflowBusy)
            actionButton("ここからブランチを作成", id: "branch-from-branch") { beginInput(.branch(start: "refs/heads/" + name)) }
            actionButton("名前の変更", id: "rename") { beginInput(.rename(name)) }.disabled(model.isWorkflowBusy)
            actionButton("削除", id: "delete-branch") {
                Task { if let merged = await model.branchIsMerged(name) { requestAction(.deleteBranch(name, force: !merged)) } }
            }.disabled(name == model.branchLabel || model.isWorkflowBusy)
        case .remote(let name):
            actionButton("チェックアウト", id: "checkout") { requestAction(.checkoutRemote(name)) }.disabled(model.isWorkflowBusy)
            actionButton("ここからブランチを作成", id: "branch-from-remote") { beginInput(.branch(start: "refs/remotes/" + name)) }
        case .stash(let id):
            actionButton("適用", id: "apply-stash") { requestAction(.applyStash(id)) }.disabled(model.isWorkflowBusy)
            actionButton("取り出す", id: "pop-stash") { requestAction(.popStash(id)) }.disabled(model.isWorkflowBusy)
            actionButton("削除", id: "drop-stash") { requestAction(.dropStash(id)) }.disabled(model.isWorkflowBusy)
        default: EmptyView()
        }
    }

    func actionButton(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(LocalizedStringKey(key), bundle: bundle) }
            .accessibilityLabel(Text(LocalizedStringKey(key), bundle: bundle)).accessibilityIdentifier("git-history-\(id)")
    }

    func copyCommitID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    func confirmationTarget(_ action: GitRepositoryAction) -> String? {
        switch action {
        case .applyStash(let id), .popStash(let id), .dropStash(let id): model.gitStashes.first { $0.id == id }.map { $0.name + " · " + $0.message }
        case .stash: nil
        default: nil
        }
    }

    func graphBadges(_ refs: [String]) -> some View {
        let badges = GitGraphBadge.make(refs: refs)
        return HStack(spacing: DSSpacing.xxs) {
            ForEach(Array(badges.prefix(2))) { badge in
                HStack(spacing: DSSpacing.xxs) {
                    if badge.cloud || badge.tag { Image(systemName: badge.tag ? "tag" : "cloud") }
                    Text(verbatim: badge.title).lineLimit(1).truncationMode(.tail)
                }.font(badge.current ? DSFont.meta.weight(.semibold) : DSFont.meta)
                    .padding(.horizontal, DSSpacing.xxs)
                    .frame(maxWidth: DSLayout.gitGraphBadgeMaximumWidth)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s))
                    .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(
                        badge.current ? DSColor.textPrimary : DSColor.separator,
                        style: StrokeStyle(lineWidth: DSLayout.paneSeparatorWidth, dash: badge.remoteOnly ? [DSSpacing.xxs] : [])))
                    .help(Text(verbatim: badge.fullName)).accessibilityLabel(Text(verbatim: badge.fullName))
            }
            if badges.count > 2 {
                Text(verbatim: "+\(badges.count - 2)").font(DSFont.meta)
                    .help(Text(verbatim: badges.dropFirst(2).map(\.fullName).joined(separator: ", ")))
            }
        }
    }

    var visibleRows: [GitHistoryRowID] {
        var rows = model.visibleGitRows(changesExpanded: changesExpanded).map(GitHistoryRowID.change)
        for section in GitHistorySection.allCases where expanded(section) {
            switch section {
            case .commits, .graph:
                let graph = section == .graph
                for commit in graph ? model.graphRows.map(\.commit) : model.historyCommits {
                    rows.append(.commit(commit.id, graph: graph))
                    appendFiles(.commit(commit.id), graph: graph, to: &rows)
                }
            case .branches: rows += model.localBranches.map { .branch($0.name) }
            case .remotes:
                for remote in Array(Set(model.remoteBranches.map(\.remote))).sorted() where remoteIsExpanded(remote) {
                    rows += model.remoteBranches.filter { $0.remote == remote }.map { .remote($0.name) }
                }
            case .stashes:
                for stash in model.gitStashes { rows.append(.stash(stash.id)); appendFiles(stash.source, graph: false, to: &rows) }
            }
        }
        return rows
    }

    func appendFiles(_ source: WorkingTreeSource, graph: Bool, to rows: inout [GitHistoryRowID]) {
        guard model.expandedHistoryRows.contains(source) else { return }
        rows += (model.historyFiles[source] ?? []).map { .file(.init(path: $0.path, source: source), graph: graph) }
    }

    func activateHistoryRow(_ row: GitHistoryRowID) {
        guard visibleRows.contains(row) else { return }
        switch row {
        case .change(let item), .file(let item, _): openChanges(item.path, item.source, false)
        case .commit(let id, _): Task { await model.toggleHistoryRow(.commit(id)) }
        case .branch(let name): if name != model.branchLabel { requestAction(.switchBranch(name)) }
        case .remote(let name): requestAction(.checkoutRemote(name))
        case .stash(let id): if let stash = model.gitStashes.first(where: { $0.id == id }) { Task { await model.toggleHistoryRow(stash.source) } }
        }
    }
}

private struct GitHistoryRowStyle: ViewModifier {
    let selected: Bool
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.foregroundStyle(DSColor.textPrimary)
            .background(selected ? DSColor.fillSelected : hovered ? DSColor.fillSubtle : DSColor.clear,
                        in: RoundedRectangle(cornerRadius: DSRadius.row))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct GitGraphLines: View {
    let row: GitGraphRow
    var continuation = false
    static func width(_ lanes: Int) -> CGFloat {
        CGFloat(min(lanes, DSLayout.gitGraphMaximumLanes)) * (lanes > 4 ? DSLayout.gitGraphCompactLaneSpacing : DSLayout.gitGraphLaneSpacing) + DSSpacing.chip
    }
    private var isCurrent: Bool { row.commit.refs.contains { $0.hasPrefix("HEAD -> ") || $0 == "HEAD" } }
    private func color(_ lane: Int) -> Color { lane == row.currentLane ? DSColor.textPrimary : DSColor.textSecondary }
    var body: some View {
        Canvas { context, size in
            let step = row.width > 4 ? DSLayout.gitGraphCompactLaneSpacing : DSLayout.gitGraphLaneSpacing
            let middle = size.height / 2
            func point(_ lane: Int, _ y: CGFloat) -> CGPoint { .init(x: CGFloat(min(lane, DSLayout.gitGraphMaximumLanes - 1)) * step + step / 2, y: y) }
            if continuation {
                for edge in row.outgoing {
                    var path = Path()
                    path.move(to: point(edge.to, 0)); path.addLine(to: point(edge.to, size.height))
                    context.stroke(path, with: .color(color(edge.color)), style: StrokeStyle(lineWidth: DSLayout.gitGraphLineWidth,
                        dash: edge.to >= DSLayout.gitGraphMaximumLanes - 1 && row.width > DSLayout.gitGraphMaximumLanes ? [DSSpacing.xxs] : []))
                }
                return
            }
            for edge in row.incoming {
                var path = Path(); path.move(to: point(edge.from, 0)); path.addLine(to: point(edge.to, middle))
                context.stroke(path, with: .color(color(edge.color)), style: StrokeStyle(lineWidth: DSLayout.gitGraphLineWidth,
                    dash: max(edge.from, edge.to) >= DSLayout.gitGraphMaximumLanes - 1 && row.width > DSLayout.gitGraphMaximumLanes ? [DSSpacing.xxs] : []))
            }
            for edge in row.outgoing {
                var path = Path(); path.move(to: point(edge.from, middle)); path.addLine(to: point(edge.to, size.height))
                context.stroke(path, with: .color(color(edge.color)), style: StrokeStyle(lineWidth: DSLayout.gitGraphLineWidth,
                    dash: max(edge.from, edge.to) >= DSLayout.gitGraphMaximumLanes - 1 && row.width > DSLayout.gitGraphMaximumLanes ? [DSSpacing.xxs] : []))
            }
            let center = point(row.lane, middle)
            let diameter = row.commit.parents.count > 1 ? DSLayout.gitGraphMergeDotDiameter : DSLayout.gitGraphDotDiameter
            let dot = Path(ellipseIn: .init(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            context.fill(dot, with: .color(isCurrent ? DSColor.textPrimary : DSColor.background))
            context.stroke(dot, with: .color(color(row.lane)), lineWidth: DSLayout.gitGraphLineWidth)
        }.help(Text(verbatim: row.commit.id + " → " + row.commit.parents.joined(separator: ", "))).accessibilityHidden(true)
    }
}

struct GitActionConfirmation: View {
    let action: GitRepositoryAction
    let runningSessions: [String]
    var targetLabel: String? = nil
    var changeCount = 0
    var untrackedCount = 0
    var cancel: () -> Void
    var perform: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle
    private func string(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
    private var target: String {
        switch action {
        case .switchBranch(let name), .checkoutRemote(let name), .deleteBranch(let name, _): name
        case .createBranch(let name, _, _): name
        case .applyStash(let id), .popStash(let id), .dropStash(let id): String(id.prefix(7))
        default: ""
        }
    }
    var title: String {
        switch action {
        case .deleteBranch(_, true): string("マージされていないブランチを削除しますか？")
        case .deleteBranch: string("ブランチを削除しますか？")
        case .dropStash: string("スタッシュを削除しますか？")
        case .popStash: string("スタッシュを取り出しますか？")
        case .stash: string("今の変更をスタッシュしますか？")
        default: string("作業ツリーを変更しますか？")
        }
    }
    var button: String {
        switch action {
        case .deleteBranch(_, true): "強制削除"
        case .deleteBranch, .dropStash: "削除"
        case .popStash: "取り出す"
        case .stash: "スタッシュ"
        default: "実行"
        }
    }
    var message: String? {
        switch action {
        case .deleteBranch(_, false): string("現在の HEAD にマージ済みです。コミットは残ります。")
        case .deleteBranch(_, true): string("マージされていないコミットがブランチからたどれなくなります。強制削除します。")
        case .dropStash: string("スタッシュの中の変更は戻せません。")
        case .popStash: string("変更を作業ツリーに戻してスタッシュを削除します。衝突した場合はスタッシュを残します。")
        case .stash:
            String(format: string("変更 %lld 件（未追跡 %lld 件を含む）をしまい、作業ツリーを HEAD に戻します。"), changeCount, untrackedCount)
        default: nil
        }
    }
    var body: some View {
        DSDialog(.irreversible, title: title,
                 message: message,
                 note: runningSessions.isEmpty ? nil : string("このプロジェクトのフォルダでエージェントが実行中です。作業中のファイルが変わります。"),
                 buttons: [.init("キャンセル", role: .primary, action: cancel),
                           .init(button, role: action.needsDestructiveConfirmation ? .destructive : .normal, action: perform)], onCancel: cancel) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let label = targetLabel ?? (target.isEmpty ? nil : target) { Text(verbatim: label).font(DSFont.monoCaption).textSelection(.enabled) }
                ForEach(runningSessions, id: \.self) { name in Text(verbatim: name).font(DSFont.meta).lineLimit(1) }
            }.foregroundStyle(DSColor.textPrimary)
        }.accessibilityLabel(Text("Git の操作の確認", bundle: bundle)).accessibilityIdentifier("git-action-confirmation")
    }
}
