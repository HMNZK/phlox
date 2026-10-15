import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

extension Notification.Name {
    static let fileTreeFileSaved = Notification.Name("phlox.fileTreeFileSaved")
}

struct FileTreeInspectorView: View {
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale
    @Bindable var router: AppRouter
    let project: Project?
    @Binding var models: [String: FileTreeModel]
    let files: FileTabDocuments
    var isOverlay = false
    @State private var root: String?
    @State private var requestedWorkingDirectory: String?

    var body: some View {
        Group {
            if let project, let root, let requestedWorkingDirectory, let model = models[root] {
                FileTreeView(model: model, openPath: openPath(project.id), open: { path, split in
                    files.openFileTab(
                        projectID: project.id, root: root, relativePath: path, split: split, router: router,
                        requestedWorkingDirectory: requestedWorkingDirectory,
                        currentWorkingDirectory: self.project?.directoryPath
                    )
                }, isOverlay: isOverlay, focusRequest: router.inspectorFocusToken, operate: { operation in
                    _ = await perform(operation, model: model, project: project)
                }, requestTrash: { entry, window in
                    await confirmTrash(entry, window: window, model: model, project: project)
                })
                .id(project.id)
            } else if project != nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileTreeEmptyView(isOverlay: isOverlay)
            }
        }
        .accessibilityIdentifier("inspector-files")
        .task(id: project.map { "\($0.id):\($0.directoryPath)" }) {
            root = nil
            requestedWorkingDirectory = nil
            guard let project else { return }
            let resolved = await FileTabOpening.root(for: project.directoryPath)
            guard !Task.isCancelled else { return }
            let model = FileTreeModel.model(for: resolved, in: models)
            models[resolved] = model
            files.router = router
            requestedWorkingDirectory = project.directoryPath
            root = resolved
            await model.refresh()
        }
    }

    private func openPath(_ id: ProjectID) -> String? {
        FileTreeRows.openPath(selected: router.tabs.layout(for: id).selected, viewMode: router.viewMode)
    }

    /// true は保存待ちの間に削除対象が変わり、再確認が必要な場合。
    private func perform(_ operation: FileTreeOperation, model: FileTreeModel, project: Project,
                         trashState: FileTreeTrashState? = nil) async -> Bool {
        guard requestedWorkingDirectory == project.directoryPath, root == model.root,
              !FileTabDocumentRegistry.shared.isChangingProject(project.id) else { return false }
        let registry = FileTabDocumentRegistry.shared
        let path: String?
        switch operation {
        case .rename(let source, _), .trash(let source): path = source
        case .create: path = nil
        }
        let documents = path.map { registry.operationDocuments(root: model.root, path: $0, including: files) } ?? []
        for document in documents {
            document.synchronizeActiveBlockEditor?()
            document.fileOperationInProgress = true
        }
        defer { for document in documents { document.fileOperationInProgress = false } }
        if let trashState, let path {
            guard await registry.trashStateMatchesAfterSaves(trashState, root: model.root, path: path,
                projectID: project.id, including: files) else { return true }
        } else {
            for document in documents { await document.waitForPendingSaves() }
        }
        guard requestedWorkingDirectory == project.directoryPath, root == model.root,
              !registry.isChangingProject(project.id) else { return false }
        if case .rename(let old, let name) = operation {
            let parent = FileTreeRows.parent(of: old)
            let destination = parent.isEmpty ? name : parent + "/" + name
            let conflicts = registry.operationDocuments(root: model.root, path: destination, including: files)
                .filter { target in !documents.contains(where: { $0 === target }) }
            let tabConflicts = registry.operationTabPaths(root: model.root, path: destination, projectID: project.id, including: files)
                .filter { FileTreeOperations.renamedPath($0, from: old, to: old) == nil }
            if !conflicts.isEmpty || !tabConflicts.isEmpty {
                model.operationFailure = FileTreeFailure(operationKey: operation.failureKey,
                    error: FileTreeNameError(key: "同じ名前のファイルのタブが開いています"))
                await model.load(parent, refresh: true)
                return false
            }
        }
        let result = await model.perform(operation)
        guard case .success(let newPath) = result else { return false }
        switch operation {
        case .rename(let old, _):
            if let newPath { registry.retargetOperationTabs(root: model.root, from: old, to: newPath, projectID: project.id, including: files) }
        case .trash(let old): await registry.closeOperationTabs(root: model.root, path: old, projectID: project.id, including: files)
        case .create(_, _, let folder):
            if !folder, let newPath {
                files.openFileTab(projectID: project.id, root: model.root, relativePath: newPath, router: router,
                                  requestedWorkingDirectory: project.directoryPath, currentWorkingDirectory: requestedWorkingDirectory)
            }
        }
        NotificationCenter.default.post(name: .fileTreeFileSaved, object: nil,
            userInfo: ["root": model.root, "path": newPath ?? path ?? ""])
        return false
    }

    private func confirmTrash(_ entry: FileTreeEntry, window: NSWindow, model: FileTreeModel, project: Project) async {
        guard requestedWorkingDirectory == project.directoryPath, root == model.root else { return }
        do {
            let count = entry.canExpand ? try await model.countItems(in: entry.relativePath) : nil
            guard requestedWorkingDirectory == project.directoryPath, root == model.root else { return }
            let registry = FileTabDocumentRegistry.shared
            let state = registry.trashState(root: model.root, path: entry.relativePath, projectID: project.id, including: files)
            let items = state.paths.map { path in FileTreeTrashItem(path: path, dirty: state.documents.contains { $0.path == path && $0.hasUnsavedChanges }) }
            let confirmation = FileTreeTrashConfirmation(entry: entry, root: model.root, count: count, openItems: items)
            let alert = FileTreeTrashAlert.make(confirmation, locale: locale, bundle: localizationBundle)
            let response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
            let approved = confirmation.destructive ? response == .alertSecondButtonReturn : response == .alertFirstButtonReturn
            guard approved else { return }
            if !registry.trashStateMatches(state, root: model.root, path: entry.relativePath, projectID: project.id, including: files) {
                await confirmTrash(entry, window: window, model: model, project: project)
                return
            }
            if await perform(.trash(path: entry.relativePath), model: model, project: project, trashState: state) {
                await confirmTrash(entry, window: window, model: model, project: project)
            }
        } catch {
            model.operationFailure = FileTreeFailure(operationKey: "ゴミ箱に入れられませんでした: %@", error: error)
            await model.load(FileTreeRows.parent(of: entry.relativePath), refresh: true)
        }
    }
}

struct FileTreeEmptyView: View {
    @Environment(\.localizationBundle) private var localizationBundle
    var isOverlay = false
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "folder").font(.system(size: 24, weight: .light)).foregroundStyle(DSColor.textTertiary)
            Text("セッションが選ばれていません", bundle: localizationBundle).font(DSFont.auxiliary.weight(.semibold))
            Text("セッションを選ぶと、その作業ディレクトリのファイルが表示されます", bundle: localizationBundle)
                .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DSSpacing.xl)
        .padding(.bottom, DSSpacing.xxl * 2 + DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isOverlay ? DSColor.popoverBackground : DSColor.panelBackground)
    }
}

struct FileTreeView: View {
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale
    @Bindable var model: FileTreeModel
    let openPath: String?
    let open: (String, Bool) -> Void
    var keyboardPath: String? = nil
    var hoverPath: String? = nil
    var contextPath: String? = nil
    var isOverlay = false
    var focusRequest = 0
    var blockedPath: String? = nil
    var operate: ((FileTreeOperation) async -> Void)? = nil
    var requestTrash: ((FileTreeEntry, NSWindow) async -> Void)? = nil
    var inputRequestsFocus = true
    @State private var windowReference = FileTreeWindowReader.Reference()
    @State private var trashPending = false
    @State private var selectedPath: String?
    @State private var keyboardMoving = false
    @State private var blockedSelection: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider().overlay(DSColor.separator)
            if let failure = model.operationFailure {
                FileTreeFailureBanner(failure: failure) { model.operationFailure = nil }
                    .id(failure.operationKey + failure.reason)
            }
            if let error = model.errorsByDir[""] {
                rootError(error)
            } else {
                list
            }
        }
        .background(isOverlay ? DSColor.popoverBackground : DSColor.panelBackground)
        .background(FileTreeWindowReader { windowReference.window = $0 })
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                FilePathLabel(path: model.root)
                    .help(model.root)
                HStack(spacing: DSSpacing.xs) {
                    if model.errorsByDir[""] == nil, !model.branch.isEmpty, model.branch != "Git 管理外" {
                        if model.branch.hasSuffix(" detached HEAD") {
                            HStack(spacing: 0) {
                                Rectangle().frame(width: 4, height: 1)
                                Circle().stroke(lineWidth: 1.2).frame(width: 7, height: 7)
                                Rectangle().frame(width: 4, height: 1)
                            }
                            .foregroundStyle(DSColor.textSecondary)
                        } else {
                            Image(systemName: "arrow.triangle.branch")
                                .font(DSFont.iconTiny).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    if model.errorsByDir[""] != nil {
                        Text("")
                    } else if model.branch.hasSuffix(" detached HEAD") {
                        Text(verbatim: String(model.branch.dropLast(" detached HEAD".count))).font(DSFont.monoCaption)
                        Text("detached HEAD").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                    } else {
                        Text(verbatim: model.branch).font(model.branch == "Git 管理外" ? DSFont.meta : DSFont.monoCaption)
                            .foregroundStyle(model.branch == "Git 管理外" ? DSColor.textSecondary : DSColor.textPrimary)
                    }
                }
                .lineLimit(1).frame(height: DSSpacing.l)
            }
            Spacer(minLength: 0)
            Menu {
                Section(String(format: localized("%@ の直下に作成"), URL(fileURLWithPath: model.root).lastPathComponent)) {
                    createButtons(nil, shortcuts: true)
                }
            } label: { Image(systemName: "plus").frame(width: DSHitTarget.icon, height: DSHitTarget.icon) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(model.operating || trashPending)
                .accessibilityLabel(Text("新規ファイル・フォルダ", bundle: localizationBundle))
                .accessibilityIdentifier("file-tree-create-menu")
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: DSHitTarget.icon, height: DSHitTarget.icon)
            }
            .buttonStyle(.plain)
            .help("更新").accessibilityLabel("更新")
            .accessibilityIdentifier("file-tree-refresh")
        }
        .padding(DSSpacing.m)
    }

    private var list: some View {
        let rows = model.rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    directoryStatus("", depth: 0)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        FileTreeEditableRow(model: model, rowID: row.id,
                            content: { rowView(row) }, editing: { editingRow($0, depth: row.depth) })
                            .id(row.id)
                        if row.entry.canExpand, model.expanded.contains(row.id),
                           model.childrenByDir[row.id]?.isEmpty != false {
                            omitted(row.id, depth: row.depth + 1)
                        }
                        ForEach(FileTreeRows.finishedDirectories(after: index, rows: rows), id: \.self) { path in
                            omitted(path, depth: path.split(separator: "/").count)
                        }
                    }
                    omitted("", depth: 0)
                    Color.clear.frame(maxWidth: .infinity, minHeight: DSSpacing.xxl * 4)
                        .contentShape(Rectangle())
                        .contextMenu { operationMenu(nil) }
                }.padding(.horizontal, DSSpacing.s).padding(.vertical, DSSpacing.xs)
            }
                .contextMenu { operationMenu(nil) }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onChange(of: focusRequest, initial: true) { _, request in if request > 0 { focused = true } }
                .onKeyPress(.rightArrow) { key(.right) }
                .onKeyPress(.leftArrow) { key(.left) }
                .onKeyPress(.upArrow) { key(.up) }
                .onKeyPress(keys: [.downArrow]) { press in
                    if press.modifiers.contains(.command) {
                        guard model.edit == nil, !trashPending else { return .ignored }
                        return key(.open)
                    }
                    return key(.down)
                }
                .onKeyPress(.return) {
                    guard model.edit == nil, !trashPending else { return .ignored }
                    return key(.rename)
                }
                .onKeyPress(characters: .init(charactersIn: "nN")) { press in
                    guard press.modifiers.contains([.command, .option]), model.edit == nil, !trashPending else { return .ignored }
                    beginCreate(selectedEntry, folder: press.modifiers.contains(.shift))
                    return .handled
                }
                .onKeyPress(keys: [.delete]) { press in
                    guard press.modifiers.contains(.command), model.edit == nil, !trashPending else { return .ignored }
                    if let entry = selectedEntry { trash(entry) }
                    return .handled
                }
                .onChange(of: model.edit?.id) { _, _ in
                    if let edit = model.edit { proxy.scrollTo(edit.rowID) }
                    else { focused = true }
                }
                .onChange(of: model.operationSelection) { _, path in
                    selectedPath = path
                    keyboardMoving = true
                    if let path { proxy.scrollTo(path) }
                    focused = true
                }
                .onChange(of: model.operating) { old, current in
                    if old, !current, model.operationFailure == nil {
                        selectedPath = model.operationSelection
                        keyboardMoving = true
                        if let path = selectedPath { proxy.scrollTo(path) }
                        focused = true
                    }
                }
                .onChange(of: selectedPath) { _, path in
                    if let path, keyboardMoving { proxy.scrollTo(path) }
                }
                .onChange(of: model.rows) { _, rows in
                    selectedPath = selectedPath == nil
                        ? FileTreeRows.selection(openPath: openPath, selectedPath: nil, rows: rows)
                        : FileTreeRows.visibleSelection(selectedPath, rows: rows)
                }
                .onChange(of: openPath, initial: true) { previous, path in
                    selectedPath = FileTreeRows.selection(openPath: path, selectedPath: selectedPath, rows: model.rows,
                                                         previousOpenPath: previous, renamed: model.lastRename)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("ファイル")
                .accessibilityIdentifier("file-tree")
        }
    }

    private func rowView(_ row: FileTreeRows.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: row.entry.canExpand
                      ? (model.expanded.contains(row.id) ? "chevron.down" : "chevron.right") : "")
                    .font(DSFont.iconTiny).frame(width: DSIconSize.m)
                    .foregroundStyle(DSColor.textTertiary)
                Image(systemName: row.entry.isFolder ? "folder" : "doc")
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: DSIconSize.l, height: DSIconSize.l)
                    .overlay(alignment: .bottomTrailing) {
                        if row.entry.resolvedPath != nil {
                            Image(systemName: "arrow.up.right").font(DSFont.iconTiny)
                                .background(DSColor.fillSelected, in: RoundedRectangle(cornerRadius: DSRadius.s))
                                .offset(x: DSSpacing.xxs, y: DSSpacing.xxs)
                        }
                    }
                    .opacity(row.entry.kind == .symlinkOutsideRoot ? 0.5 : 1)
                Text(verbatim: row.entry.name)
                    .font(DSFont.row.weight(row.isOpen(openPath) && (keyboardMoving || keyboardPath != nil) ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if row.entry.kind == .symlinkOutsideRoot {
                    Text("ルート外", bundle: localizationBundle).font(DSFont.meta)
                        .foregroundStyle(DSColor.isDark ? DSColor.textTertiary : DSColor.neutralGlyph)
                } else if row.entry.kind == .unavailable {
                    Text("開けません").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                } else if let destination = row.entry.linkDestination {
                    Text(verbatim: destination).font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                }
            }
            .foregroundStyle(row.entry.kind == .symlinkOutsideRoot
                             ? (DSColor.isDark ? DSColor.textTertiary : DSColor.neutralGlyph)
                             : row.entry.kind == .unavailable ? DSColor.textTertiary : DSColor.textPrimary)
            .padding(.leading, CGFloat(row.depth) * (DSSpacing.m + DSSpacing.xxs))
            .frame(minHeight: DSLayout.listRowHeight)
            .hoverableControlSurface(cornerRadius: DSRadius.row,
                                     baseFill: rowFill(row),
                                     hoverFill: DSColor.fillSubtle,
                                     borderColor: .clear, hoverBorderColor: .clear)
            .contentShape(Rectangle())
            .onTapGesture { activate(row) }
            .help(row.entry.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(row.entry.name)、\(row.entry.kindLabel)"))
            .accessibilityValue(Text("レベル \(row.depth + 1)" + (row.entry.canExpand ? "、" + (model.expanded.contains(row.id) ? "展開" : "折りたたみ") : "") + (row.isOpen(openPath) ? "、開いています" : "")))
            .accessibilityAddTraits(isSelectedRow(row) ? .isSelected : [])
            .accessibilityAction { activate(row) }
            .accessibilityActions {
                if row.entry.canExpand {
                    Button(model.expanded.contains(row.id) ? "折りたたみ" : "展開") {
                        activate(row)
                    }
                }
            }
            .accessibilityIdentifier("file-tree-row-\(row.id)")
            .modifier(SidebarMenuOpenRing(isPresented: row.id == contextPath) {
                Section(row.entry.kind == .symlinkOutsideRoot ? localized("ルートの外を指すリンク") : row.entry.name) {
                if row.entry.canOpen {
                    Button("右に分割して開く") {
                        selectedPath = row.id
                        open(row.id, true)
                    }
                    Divider()
                }
                createButtons(row.entry, shortcuts: true)
                Divider()
                Button(localized("名前を変更")) {
                    // メニュー処理が戻るまで、そのメニューを所有する行を置き換えない。
                    DispatchQueue.main.async { model.beginRename(row.entry) }
                }
                    .disabled(!row.entry.canModify || model.operating || trashPending)
                    .accessibilityIdentifier("file-tree-rename")
                Button(localized("ゴミ箱に入れる")) { trash(row.entry) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!row.entry.canModify || model.operating || trashPending)
                    .accessibilityIdentifier("file-tree-trash")
                Divider()
                Button("Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([row.entry.finderURL(root: model.root)])
                }
                Button("パスをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(URL(fileURLWithPath: model.root).appendingPathComponent(row.id).path, forType: .string)
                }
                }
            })
            if row.entry.kind == .symlinkOutsideRoot, row.id == (blockedSelection ?? blockedPath) {
                Text(verbatim: row.entry.help)
                    .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSSpacing.s).padding(.vertical, DSSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.row))
                    .help(row.entry.help)
                    .accessibilityIdentifier("file-tree-blocked-reason")
            }
            if row.entry.canExpand, model.expanded.contains(row.id) {
                directoryStatus(row.id, depth: row.depth + 1)
            }
        }
    }

    @ViewBuilder
    private func directoryStatus(_ path: String, depth: Int) -> some View {
        if model.loading.contains(path) || model.errorsByDir[path] != nil {
            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Color.clear.frame(width: DSIconSize.m, height: 1)
                if model.loading.contains(path) {
                    ProgressView().controlSize(.mini).frame(width: DSIconSize.l)
                    Text("読み込み中…")
                } else if let error = model.errorsByDir[path] {
                    Image(systemName: "exclamationmark.circle").frame(width: DSIconSize.l)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("読み込めませんでした", bundle: localizationBundle).foregroundStyle(DSColor.textPrimary)
                        (Text(LocalizedStringKey(error), bundle: localizationBundle) + Text(verbatim: "（\(path)）"))
                            .font(DSFont.meta)
                    }
                }
            }
            .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
            .padding(.leading, CGFloat(depth) * (DSSpacing.m + DSSpacing.xxs))
            .padding(.vertical, DSSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.errorsByDir[path] != nil ? DSColor.fillSubtle : .clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
        }
    }

    @ViewBuilder
    private func omitted(_ path: String, depth: Int) -> some View {
        if let count = model.omittedByDir[path], count > 0 {
            HStack(spacing: DSSpacing.xs) {
                Color.clear.frame(width: DSIconSize.m, height: 1)
                Text("…").frame(width: DSIconSize.l).foregroundStyle(DSColor.textTertiary)
                Text("ほか \(count) 件（⌘P で開けます）")
                    .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
            }
            .padding(.leading, CGFloat(depth) * (DSSpacing.m + DSSpacing.xxs))
            .frame(minHeight: DSLayout.listRowHeight)
        }
    }

    private func rootError(_ error: String) -> some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 24, weight: .light)).foregroundStyle(DSColor.textSecondary)
            Text("フォルダを読み込めません", bundle: localizationBundle).font(DSFont.auxiliary.weight(.semibold))
            Text(LocalizedStringKey(error == "ファイルまたはフォルダが見つかりません。"
                 ? "作業ディレクトリが見つかりません。移動または削除された可能性があります。" : error), bundle: localizationBundle)
                .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
            Text(verbatim: (model.root as NSString).abbreviatingWithTildeInPath)
                .font(DSFont.monoCaption).foregroundStyle(DSColor.textTertiary)
                .lineLimit(1).truncationMode(.head).help(model.root)
            Button { Task { await model.refresh() } } label: {
                Text("更新", bundle: localizationBundle)
            }
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 12, padding: 12))
        }
        .multilineTextAlignment(.center).padding(.horizontal, DSSpacing.xl)
        .padding(.bottom, DSSpacing.xxl * 2 + DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func key(_ key: FileTreeRows.Key) -> KeyPress.Result {
        guard model.edit == nil, !trashPending else { return .ignored }
        model.operationFailure = nil
        keyboardMoving = true
        if selectedPath == nil, let first = model.rows.first {
            selectedPath = first.id
            if key == .up || key == .down { return .handled }
        }
        guard let action = FileTreeRows.action(for: selectedPath, key: key, rows: model.rows, expanded: model.expanded) else {
            return !model.rows.isEmpty && (key == .up || key == .down) ? .handled : .ignored
        }
        perform(action)
        return .handled
    }

    private func perform(_ action: FileTreeRows.Action?) {
        blockedSelection = nil
        switch action {
        case .select(let path): selectedPath = path
        case .expand(let path): Task { await model.expand(path) }
        case .collapse(let path):
            model.collapse(path)
            selectedPath = FileTreeRows.visibleSelection(selectedPath, rows: model.rows)
        case .open(let path):
            selectedPath = path
            open(path, false)
        case .rename(let path):
            if let entry = model.rows.first(where: { $0.id == path })?.entry { model.beginRename(entry) }
        case .explainBlocked(let path): blockedSelection = path
        case nil: break
        }
    }

    private func activate(_ row: FileTreeRows.Row) {
        model.edit = nil
        model.operationFailure = nil
        focused = true
        keyboardMoving = false
        selectedPath = row.id
        perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded))
    }

    private func isSelectedRow(_ row: FileTreeRows.Row) -> Bool {
        row.id == keyboardPath || ((focused || keyboardMoving) && row.id == selectedPath)
    }

    private func rowFill(_ row: FileTreeRows.Row) -> Color {
        if isSelectedRow(row) { return DSColor.selectionFill }
        return row.isOpen(openPath) || row.id == hoverPath ? DSColor.fillSubtle : .clear
    }

    private var selectedEntry: FileTreeEntry? { model.rows.first { $0.id == selectedPath }?.entry }
    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: localizationBundle) }
    private func beginCreate(_ entry: FileTreeEntry?, folder: Bool) {
        Task { await model.beginCreate(at: entry, folder: folder) }
    }
    @ViewBuilder private func createButtons(_ entry: FileTreeEntry?, shortcuts: Bool) -> some View {
        let disabled = entry?.canCreate == false || model.operating || trashPending
        Button(localized("新規ファイル")) { createFromMenu(entry, folder: false) }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("n", modifiers: [.command, .option]) : nil)
            .disabled(disabled).accessibilityIdentifier("file-tree-new-file")
        Button(localized("新規フォルダ")) { createFromMenu(entry, folder: true) }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("n", modifiers: [.command, .option, .shift]) : nil)
            .disabled(disabled).accessibilityIdentifier("file-tree-new-folder")
    }
    private func createFromMenu(_ entry: FileTreeEntry?, folder: Bool) {
        // 「＋」のクリックはルート、同じ項目のキー操作は選択行の場所。
        let event = NSApp.currentEvent
        let shortcut = event?.type == .keyDown && event?.charactersIgnoringModifiers?.lowercased() == "n"
            && event?.modifierFlags.contains([.command, .option]) == true
        beginCreate(shortcut ? selectedEntry : entry, folder: folder)
    }
    @ViewBuilder private func operationMenu(_ entry: FileTreeEntry?) -> some View {
        Section(URL(fileURLWithPath: model.root).lastPathComponent + localized("（ルート）")) {
            createButtons(entry, shortcuts: true)
            Divider()
            Button(localized("名前を変更")) {}.disabled(true).accessibilityIdentifier("file-tree-root-rename")
            Button(localized("ゴミ箱に入れる")) {}.keyboardShortcut(.delete, modifiers: .command)
                .disabled(true).accessibilityIdentifier("file-tree-root-trash")
            Divider()
            Button(localized("Finder で表示")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.root)]) }
            Button(localized("パスをコピー")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.root, forType: .string)
            }
        }
    }
    private func trash(_ entry: FileTreeEntry) {
        guard entry.canModify, !model.operating, !trashPending, let window = windowReference.window, let requestTrash else { return }
        model.edit = nil
        model.operationFailure = nil
        trashPending = true
        Task {
            await requestTrash(entry, window)
            trashPending = false
            focused = true
        }
    }
    private func editingRow(_ edit: FileTreeEdit, depth: Int) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Color.clear.frame(width: DSIconSize.m)
            Image(systemName: edit.folder ? "folder" : "doc").foregroundStyle(DSColor.textSecondary).frame(width: DSIconSize.l)
            FileTreeNameInput(edit: edit, label: String(format: localized(edit.isNew ? (edit.folder ? "新規フォルダの名前、%@ の中" : "新規ファイルの名前、%@ の中") : "名前を変更、%@ の中"),
                edit.parent.isEmpty ? URL(fileURLWithPath: model.root).lastPathComponent : (edit.parent as NSString).lastPathComponent)
                + (edit.error.map { " · " + localized("使えない名前") + ": " + localized($0) } ?? ""),
                update: { model.updateName($0) }, submit: {
                    guard let operation = model.submitEdit() else { return }
                    Task {
                        if let operate { await operate(operation) }
                        else { await model.perform(operation) }
                    }
                }, cancel: { model.edit = nil; focused = true }, requestsFocus: inputRequestsFocus,
                placeholder: localized(edit.isNew ? (edit.folder ? "フォルダ名" : "ファイル名") : "名前"))
                .frame(height: DSLayout.fileTreeInputHeight)
                .padding(.horizontal, DSSpacing.xs)
                .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: DSLayout.fileTreeInputRadius))
                .overlay(RoundedRectangle(cornerRadius: DSLayout.fileTreeInputRadius).stroke(DSColor.focusRing, lineWidth: DSSpacing.xxs))
                .overlay(alignment: .topLeading) {
                    if let error = edit.error {
                        FileTreeNameErrorView(message: error).offset(y: DSLayout.listRowHeight).zIndex(2)
                    }
                }
        }
        .padding(.leading, CGFloat(depth) * (DSSpacing.m + DSSpacing.xxs))
        .frame(height: DSLayout.listRowHeight)
        .disabled(model.operating)
        .accessibilityIdentifier("file-tree-editing-row")
        .onChange(of: edit.error) { _, error in
            guard let error else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: localized(error), .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

private struct FileTreeEditableRow<Content: View, Editing: View>: View {
    @Bindable var model: FileTreeModel
    let rowID: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let editing: (FileTreeEdit) -> Editing

    var body: some View {
        if let edit = model.edit, edit.rowID == rowID {
            editing(edit).zIndex(1)
        } else {
            content()
        }
    }
}
