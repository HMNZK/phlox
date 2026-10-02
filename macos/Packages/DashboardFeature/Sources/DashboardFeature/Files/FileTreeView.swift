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
    @State private var root: String?
    @State private var requestedWorkingDirectory: String?

    var body: some View {
        Group {
            if let session, let root, let requestedWorkingDirectory, let model = models[root] {
                FileTreeView(model: model, openPath: openPath(session.id)) { path, split in
                    files.openFileTab(
                        sessionID: session.id, root: root, relativePath: path, split: split, router: router,
                        requestedWorkingDirectory: requestedWorkingDirectory,
                        currentWorkingDirectory: self.session?.rawWorkspacePath
                    )
                }
                .id(session.id)
            } else if session != nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("セッションを選ぶと、その作業ディレクトリのファイルが表示されます")
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(DSSpacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct FileTreeView: View {
    @Bindable var model: FileTreeModel
    let openPath: String?
    let open: (String, Bool) -> Void
    @State private var selectedPath: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            list
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: (model.root as NSString).abbreviatingWithTildeInPath)
                    .font(DSFont.monoCaption)
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.root)
                Text(verbatim: model.branch)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .frame(height: DSSpacing.l)
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
        List(selection: $selectedPath) {
                directoryStatus("", depth: 0)
                ForEach(model.rows) { row in
                    rowView(row)
                }
            }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.row)
                        .strokeBorder(focused ? DSColor.focusRing : Color.clear, lineWidth: DSSpacing.xxs)
                        .allowsHitTesting(false)
                }
                .onKeyPress(.rightArrow) { key(.right) }
                .onKeyPress(.leftArrow) { key(.left) }
                .onKeyPress(.return) { key(.activate) }
                .onChange(of: model.rows) { _, rows in
                    selectedPath = selectedPath == nil
                        ? FileTreeRows.selection(openPath: openPath, selectedPath: nil, rows: rows)
                        : FileTreeRows.visibleSelection(selectedPath, rows: rows)
                }
                .onChange(of: openPath, initial: true) { _, path in
                    selectedPath = FileTreeRows.selection(openPath: path, selectedPath: selectedPath, rows: model.rows)
                }
                .accessibilityIdentifier("file-tree")
    }

    private func rowView(_ row: FileTreeRows.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: row.entry.canExpand
                      ? (model.expanded.contains(row.id) ? "chevron.down" : "chevron.right") : "")
                    .font(DSFont.iconTiny).frame(width: DSIconSize.m)
                Image(systemName: row.entry.isFolder ? "folder" : "doc")
                    .foregroundStyle(DSColor.textSecondary)
                Text(verbatim: row.entry.name)
                    .font(DSFont.auxiliary.weight(row.isOpen(openPath) ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                if row.entry.resolvedPath != nil {
                    Image(systemName: "arrow.up.right").font(DSFont.iconTiny)
                }
                if row.entry.kind == .symlinkOutsideRoot {
                    Text("ルート外").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                } else if row.entry.kind == .unavailable {
                    Text("開けません").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(row.entry.canOpen || row.entry.canExpand
                             ? DSColor.textPrimary : DSColor.textTertiary)
            .padding(.leading, CGFloat(row.depth) * DSSpacing.l)
            .frame(minHeight: DSLayout.listRowHeight)
            .background(row.isOpen(openPath) ? DSColor.fillSelected : Color.clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
            .contentShape(Rectangle())
            .onTapGesture {
                selectedPath = row.id
                perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded))
            }
            .help(row.entry.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(row.entry.name)、\(row.entry.kindLabel)"))
            .accessibilityValue(Text("レベル \(row.depth + 1)" + (row.entry.canExpand ? "、" + (model.expanded.contains(row.id) ? "展開" : "折りたたみ") : "")))
            .accessibilityAction { perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded)) }
            .accessibilityActions {
                if row.entry.canExpand {
                    Button(model.expanded.contains(row.id) ? "折りたたみ" : "展開") {
                        perform(FileTreeRows.action(for: row.id, key: .activate, rows: model.rows, expanded: model.expanded))
                    }
                }
            }
            .accessibilityIdentifier("file-tree-row-\(row.id)")
            .contextMenu {
                if row.entry.canOpen {
                    Button("右に分割して開く") {
                        selectedPath = row.id
                        open(row.id, true)
                    }
                }
                Button("Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([row.entry.finderURL(root: model.root)])
                }
                Button("パスをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(URL(fileURLWithPath: model.root).appendingPathComponent(row.id).path, forType: .string)
                }
            }
            if row.entry.canExpand, model.expanded.contains(row.id) {
                directoryStatus(row.id, depth: row.depth + 1)
            }
        }
        .tag(row.id)
        .listRowInsets(EdgeInsets(top: 0, leading: DSSpacing.xs, bottom: 0, trailing: DSSpacing.xs))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func directoryStatus(_ path: String, depth: Int) -> some View {
        if model.loading.contains(path) || model.errorsByDir[path] != nil || (model.omittedByDir[path] ?? 0) > 0 {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if model.loading.contains(path) { Text("読み込み中…") }
                if let error = model.errorsByDir[path] { Text(verbatim: error) }
                if let count = model.omittedByDir[path], count > 0 {
                    Text("ほか \(count) 件（⌘P で開けます）")
                }
            }
            .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
            .padding(.leading, CGFloat(depth) * DSSpacing.l)
        }
    }

    private func key(_ key: FileTreeRows.Key) -> KeyPress.Result {
        guard let action = FileTreeRows.action(for: selectedPath, key: key, rows: model.rows, expanded: model.expanded) else { return .ignored }
        perform(action)
        return .handled
    }

    private func perform(_ action: FileTreeRows.Action?) {
        switch action {
        case .select(let path): selectedPath = path
        case .expand(let path): Task { await model.expand(path) }
        case .collapse(let path):
            model.collapse(path)
            selectedPath = FileTreeRows.visibleSelection(selectedPath, rows: model.rows)
        case .open(let path):
            selectedPath = path
            open(path, false)
        case nil: break
        }
    }
}
