import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

extension Notification.Name {
    static let fileTreeFileSaved = Notification.Name("phlox.fileTreeFileSaved")
}

struct FileTreeInspectorView: View {
    @Bindable var router: AppRouter
    let session: SessionNode?
    @Binding var models: [String: FileTreeModel]
    let files: FileTabDocuments
    var isOverlay = false
    @State private var root: String?
    @State private var requestedWorkingDirectory: String?

    var body: some View {
        Group {
            if let session, let root, let requestedWorkingDirectory, let model = models[root] {
                FileTreeView(model: model, openPath: openPath(session.id), open: { path, split in
                    files.openFileTab(
                        sessionID: session.id, root: root, relativePath: path, split: split, router: router,
                        requestedWorkingDirectory: requestedWorkingDirectory,
                        currentWorkingDirectory: self.session?.rawWorkspacePath
                    )
                }, isOverlay: isOverlay)
                .id(session.id)
            } else if session != nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileTreeEmptyView(isOverlay: isOverlay)
            }
        }
        .accessibilityIdentifier("inspector-files")
        .task(id: session.map { "\($0.id):\($0.rawWorkspacePath)" }) {
            root = nil
            requestedWorkingDirectory = nil
            guard let session else { return }
            let resolved = await FileTabOpening.root(for: session.rawWorkspacePath)
            guard !Task.isCancelled else { return }
            let model = FileTreeModel.model(for: resolved, in: models)
            models[resolved] = model
            requestedWorkingDirectory = session.rawWorkspacePath
            root = resolved
            await model.refresh()
        }
    }

    private func openPath(_ id: SessionID) -> String? {
        FileTreeRows.openPath(selected: router.tabs.layout(for: id).selected,
                              viewMode: router.viewMode, commonTerminalSelected: router.commonTerminalSelected)
    }
}

struct FileTreeEmptyView: View {
    var isOverlay = false
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "folder").font(DSFont.emptyTitle).foregroundStyle(DSColor.textTertiary)
            Text("セッションが選ばれていません").font(DSFont.auxiliary.weight(.semibold))
            Text("セッションを選ぶと、その作業ディレクトリのファイルが表示されます")
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
    @Bindable var model: FileTreeModel
    let openPath: String?
    let open: (String, Bool) -> Void
    var keyboardPath: String? = nil
    var hoverPath: String? = nil
    var contextPath: String? = nil
    var showsFocus = false
    var isOverlay = false
    var blockedPath: String? = nil
    @State private var selectedPath: String?
    @State private var keyboardMoving = false
    @State private var blockedSelection: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            if let error = model.errorsByDir[""] {
                rootError(error)
            } else {
                list
            }
        }
        .background(isOverlay ? DSColor.popoverBackground : DSColor.panelBackground)
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
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: DSHitTarget.icon, height: DSHitTarget.icon)
            }
            .buttonStyle(.plain)
            .help("更新").accessibilityLabel("更新")
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
                        rowView(row).id(row.id)
                        if row.entry.canExpand, model.expanded.contains(row.id),
                           model.childrenByDir[row.id]?.isEmpty != false {
                            omitted(row.id, depth: row.depth + 1)
                        }
                        ForEach(FileTreeRows.finishedDirectories(after: index, rows: rows), id: \.self) { path in
                            omitted(path, depth: path.split(separator: "/").count)
                        }
                    }
                    omitted("", depth: 0)
                }.padding(.horizontal, DSSpacing.s).padding(.vertical, DSSpacing.xs)
            }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.row)
                        .strokeBorder(focused || showsFocus ? DSColor.accent.opacity(DSColor.isDark ? 0.6 : 1) : Color.clear, lineWidth: DSSpacing.xxs)
                        .allowsHitTesting(false)
                }
                .onKeyPress(.rightArrow) { key(.right) }
                .onKeyPress(.leftArrow) { key(.left) }
                .onKeyPress(.upArrow) { key(.up) }
                .onKeyPress(.downArrow) { key(.down) }
                .onKeyPress(.return) { key(.activate) }
                .onChange(of: selectedPath) { _, path in
                    if let path, keyboardMoving { proxy.scrollTo(path) }
                }
                .onChange(of: model.rows) { _, rows in
                    selectedPath = selectedPath == nil
                        ? FileTreeRows.selection(openPath: openPath, selectedPath: nil, rows: rows)
                        : FileTreeRows.visibleSelection(selectedPath, rows: rows)
                }
                .onChange(of: openPath, initial: true) { _, path in
                    selectedPath = FileTreeRows.selection(openPath: path, selectedPath: selectedPath, rows: model.rows)
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
                    Text("ルート外").font(DSFont.meta)
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
                                     hoverFill: isKeyboardRow(row) ? DSColor.textPrimary.opacity(0.16) : DSColor.fillSubtle,
                                     borderColor: .clear, hoverBorderColor: .clear)
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.row)
                    .strokeBorder(row.id == contextPath ? DSColor.accent : .clear, lineWidth: DSSpacing.xxs)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focused = true
                keyboardMoving = false
                selectedPath = row.id
                perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded))
            }
            .help(row.entry.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(row.entry.name)、\(row.entry.kindLabel)"))
            .accessibilityValue(Text("レベル \(row.depth + 1)" + (row.entry.canExpand ? "、" + (model.expanded.contains(row.id) ? "展開" : "折りたたみ") : "") + (row.isOpen(openPath) ? "、開いています" : "")))
            .accessibilityAction { perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded)) }
            .accessibilityActions {
                if row.entry.canExpand {
                    Button(model.expanded.contains(row.id) ? "折りたたみ" : "展開") {
                        perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded))
                    }
                }
            }
            .accessibilityIdentifier("file-tree-row-\(row.id)")
            .modifier(SidebarMenuOpenRing {
                if row.entry.canOpen {
                    Button("右に分割して開く") {
                        selectedPath = row.id
                        open(row.id, true)
                    }
                    Divider()
                }
                Button("Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([row.entry.finderURL(root: model.root)])
                }
                Button("パスをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(URL(fileURLWithPath: model.root).appendingPathComponent(row.id).path, forType: .string)
                }
            })
            if row.entry.kind == .symlinkOutsideRoot, row.id == (blockedSelection ?? blockedPath) {
                Text(verbatim: row.entry.help)
                    .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
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
                        Text("読み込めませんでした").foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: error).font(DSFont.meta)
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
            Image(systemName: "exclamationmark.circle").font(DSFont.emptyTitle).foregroundStyle(DSColor.textSecondary)
            Text("フォルダを読み込めません").font(DSFont.auxiliary.weight(.semibold))
            Text(verbatim: error == "ファイルまたはフォルダが見つかりません。"
                 ? "作業ディレクトリが見つかりません。移動または削除された可能性があります。" : error)
                .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
            Text(verbatim: (model.root as NSString).abbreviatingWithTildeInPath)
                .font(DSFont.monoCaption).foregroundStyle(DSColor.textTertiary)
                .lineLimit(1).truncationMode(.middle).help(model.root)
            Button("更新") { Task { await model.refresh() } }
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 12, padding: 12))
        }
        .multilineTextAlignment(.center).padding(.horizontal, DSSpacing.xl)
        .padding(.bottom, DSSpacing.xxl * 2 + DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func key(_ key: FileTreeRows.Key) -> KeyPress.Result {
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
        case .explainBlocked(let path): blockedSelection = path
        case nil: break
        }
    }

    private func isKeyboardRow(_ row: FileTreeRows.Row) -> Bool {
        row.id == keyboardPath || (keyboardMoving && row.id == selectedPath)
    }

    private func rowFill(_ row: FileTreeRows.Row) -> Color {
        if isKeyboardRow(row) { return DSColor.textPrimary.opacity(0.16) }
        return row.isOpen(openPath) || row.id == hoverPath ? DSColor.fillSubtle : .clear
    }
}
