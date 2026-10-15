import AppKit
import DesignSystem
import SwiftUI

/// 変更タブと一覧を共有する読み取り専用の小さな差分。
struct GitInspectorView: View {
    @Bindable var model: EditorPanelViewModel
    let workingDirectory: String
    var openChanges: (String?, Bool) -> Void
    var openFile: (String) -> Void
    var focusRequest = 0
    @State private var selection: String?
    @State private var loader = GitDetailLoader()
    @State private var retryToken = 0
    @AppStorage("phlox.inspector.git.listHeight") var savedListHeight = Double(DSLayout.gitListInitialHeight)
    private var listHeight: CGFloat {
        get { CGFloat(savedListHeight) }
        nonmutating set { savedListHeight = Double(newValue) }
    }
    @State private var dragStart: CGFloat?
    @State private var splitHovered = false
    @FocusState private var listFocused: Bool
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    // 画面外描画にも実物の差分部品を使う。
    var previewPath: String? = nil
    var previewDetail: WorkingTreeDetail? = nil
    var loadsDetail = true

    private var selected: String? { selection ?? previewPath }
    private var shownDetail: WorkingTreeDetail? { loader.detail ?? previewDetail }
    private var state: GitTabPolicy.State {
        if model.listState == .noProject && !workingDirectory.isEmpty { return .loading }
        return GitTabPolicy.state(list: model.listState, refreshing: model.isRefreshing, error: model.listErrorMessage, count: model.changes.count)
    }
    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                switch state {
                case .changes:
                    VStack(spacing: 0) {
                        changeList.frame(height: clampedListHeight(geometry.size.height))
                        Rectangle().fill(splitHovered ? DSColor.focusRing : DSColor.separator).frame(height: DSLayout.paneSeparatorWidth)
                            .overlay {
                                Rectangle().fill(splitHovered ? DSColor.focusRing : DSColor.clear)
                                    .frame(height: splitHovered ? DSLayout.gitSplitHoverHeight : DSLayout.paneSeparatorWidth)
                                    .frame(height: DSLayout.gitSplitHitHeight)
                                    .contentShape(Rectangle())
                                    .onHover { hovered in
                                        splitHovered = hovered
                                        if hovered { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                                    }
                                    .gesture(DragGesture().onChanged { value in
                                        if dragStart == nil { dragStart = clampedListHeight(geometry.size.height) }
                                        listHeight = min(max(DSLayout.gitListMinimumHeight, (dragStart ?? listHeight) + value.translation.height),
                                                         max(DSLayout.gitListMinimumHeight, geometry.size.height - DSLayout.gitDiffMinimumHeight))
                                    }.onEnded { _ in dragStart = nil })
                            }
                            .accessibilityElement()
                            .accessibilityLabel(Text("一覧と差分の境目", bundle: bundle))
                            .accessibilityIdentifier("git-inspector-divider")
                            .accessibilityAdjustableAction { direction in
                                listHeight = min(max(DSLayout.gitListMinimumHeight, listHeight + (direction == .increment ? DSSpacing.xl : -DSSpacing.xl)),
                                                 max(DSLayout.gitListMinimumHeight, geometry.size.height - DSLayout.gitDiffMinimumHeight))
                            }
                        diffPane(width: geometry.size.width)
                    }
                    .onChange(of: geometry.size.height) { old, new in
                        guard old > 0 else { return }
                        listHeight = min(max(DSLayout.gitListMinimumHeight, listHeight * new / old), max(DSLayout.gitListMinimumHeight, new - DSLayout.gitDiffMinimumHeight))
                    }
                case .loading:
                    HStack(spacing: DSSpacing.s) { ProgressView().controlSize(.small); Text("変更を読み込んでいます…", bundle: bundle) }
                        .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .clean: empty("変更はありません", explanation: localized("作業ツリーは HEAD と同じです"))
                case .notRepository: empty("Git 管理外のフォルダです", explanation: (workingDirectory as NSString).abbreviatingWithTildeInPath, path: true)
                case .noProject: empty("プロジェクトが選択されていません", explanation: "")
                case .failed(let reason): empty("変更を取得できませんでした", explanation: reason, retry: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Git", bundle: bundle))
        .accessibilityIdentifier("inspector-git")
        .onChange(of: focusRequest, initial: true) { _, request in if request > 0 { listFocused = true } }
        .onChange(of: state) { _, current in if current == .changes, focusRequest > 0 { listFocused = true } }
        .onChange(of: model.changes.count) { old, new in
            guard loadsDetail, old != new else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: summary, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .onChange(of: model.changes.map(\.path), initial: true) { _, paths in
            if let selected, paths.contains(selected) { return }
            selection = paths.first
            loader.clear()
        }
        .onChange(of: selected) { _, _ in loader.clear() }
        .task(id: "\(ObjectIdentifier(model)): \(selected ?? ""): \(model.refreshRevision): \(retryToken)") {
            guard loadsDetail, let path = selected else { return }
            await loader.load(path: path) { try await model.gitDetail(for: $0) }
        }
    }

    private func clampedListHeight(_ total: CGFloat) -> CGFloat {
        min(listHeight, max(DSLayout.gitListMinimumHeight, total - DSLayout.gitDiffMinimumHeight))
    }

    private var header: some View {
        HStack(spacing: DSSpacing.xs) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xs) {
                    if model.listState == .notARepository {
                        Text("Git 管理外", bundle: bundle).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    else {
                        Image(systemName: "arrow.branch").accessibilityHidden(true)
                        Text(verbatim: model.branchLabel).lineLimit(1).truncationMode(.tail)
                    }
                }.font(DSFont.monoCaption).foregroundStyle(DSColor.textPrimary)
                Text(verbatim: summary).font(DSFont.meta).foregroundStyle(DSColor.textSecondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.listState != .notARepository && !workingDirectory.isEmpty {
                Button(localized("コミット…")) { openChanges(nil, true) }
                    .font(DSFont.auxiliary).buttonStyle(.plain)
                    .padding(.horizontal, DSSpacing.s).frame(height: DSLayout.fileTreeInputHeight)
                    .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: DSRadius.s))
                    .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.controlBorder, lineWidth: DSLayout.controlBorderWidth))
                    .disabled(state != .changes || model.isRefreshing)
                    .help(Text("『変更』タブのコミット欄を開く", bundle: bundle))
                    .accessibilityLabel(Text("『変更』タブのコミット欄を開く", bundle: bundle))
                    .accessibilityIdentifier("git-inspector-commit")
            }
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).frame(width: DSSpacing.xl, height: DSLayout.fileTreeInputHeight)
                .disabled(model.isRefreshing)
                .help(Text("更新", bundle: bundle))
                .accessibilityLabel(Text("変更を更新", bundle: bundle))
                .accessibilityIdentifier("git-inspector-refresh")
        }
        .padding(.leading, DSLayout.gitSignWidth).padding(.trailing, DSSpacing.s).padding(.bottom, DSSpacing.s)
        .frame(height: DSLayout.gitHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
    }

    private var summary: String {
        switch state {
        case .loading: return localized("読み込み中…")
        case .clean: return localized("変更なし")
        case .failed: return localized("取得できませんでした")
        case .notRepository, .noProject: return (workingDirectory as NSString).abbreviatingWithTildeInPath
        case .changes:
            let count = String(format: localized("%lld 件の変更"), model.changes.count)
            return model.newChangeCount == 0 ? count : count + " · " + String(format: localized("%lld 件増えました"), model.newChangeCount)
        }
    }

    private var changeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.changes, id: \.path) { change in
                        changeRow(change).id(change.path)
                    }
                }.padding(.horizontal, DSSpacing.s).padding(.vertical, DSSpacing.xs)
            }
            .focusable().focused($listFocused).focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.return) { if let selected { openChanges(selected, false) }; return .handled }
            .onChange(of: selected) { _, path in if let path { proxy.scrollTo(path) } }
            .accessibilityIdentifier("git-inspector-list")
            .accessibilityLabel(Text("変更ファイル", bundle: bundle))
        }
    }

    private func move(_ offset: Int) {
        let paths = model.changes.map(\.path)
        guard !paths.isEmpty else { return }
        let index = selected.flatMap { paths.firstIndex(of: $0) } ?? 0
        selection = paths[min(max(0, index + offset), paths.count - 1)]
        if let selection { model.markGitPathSeen(selection) }
    }

    private func changeRow(_ change: WorkingTreeChange) -> some View {
        let isSelected = selected == change.path
        let url = URL(fileURLWithPath: change.path)
        let folder = (change.path as NSString).deletingLastPathComponent
        let count = model.lineCounts[change.path]
        return HStack(spacing: DSSpacing.chip) {
            Text(verbatim: GitTabPolicy.letter(change.kind)).font(DSFont.monoCaption.weight(.bold))
                .foregroundStyle(isSelected ? DSColor.textPrimary : change.kind == .added ? DSColor.diffAdded : change.kind == .deleted ? DSColor.diffRemoved : DSColor.textSecondary)
                .frame(width: DSLayout.gitKindSize, height: DSLayout.gitKindSize)
                .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.border, lineWidth: DSLayout.paneSeparatorWidth))
                .fixedSize()
            Text(verbatim: url.lastPathComponent).font(DSFont.row.weight(model.freshPaths.contains(change.path) ? .semibold : .regular))
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Text(verbatim: folder).font(DSFont.meta).foregroundStyle(DSColor.textSecondary).lineLimit(1).truncationMode(.head)
                .frame(minWidth: DSSpacing.xl, maxWidth: .infinity, alignment: .leading)
            if let count {
                if count.added > 0 { Text(verbatim: "+\(count.added)").foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.diffAdded).fixedSize() }
                if count.deleted > 0 { Text(verbatim: "−\(count.deleted)").foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.diffRemoved).fixedSize() }
            }
        }
        .font(DSFont.monoCaption).foregroundStyle(DSColor.textPrimary)
        .padding(.leading, DSSpacing.xs).padding(.trailing, DSSpacing.s).frame(height: DSLayout.gitRowHeight)
        .background(isSelected ? (listFocused ? DSColor.selectionFill : DSColor.fillSelected) : DSColor.clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selection = change.path; model.markGitPathSeen(change.path); openChanges(change.path, false) }
        .onTapGesture { selection = change.path; model.markGitPathSeen(change.path); listFocused = true }
        .contextMenu {
            Button(localized("『変更』タブで開く")) { openChanges(change.path, false) }.accessibilityIdentifier("git-row-changes")
            Button(localized("ファイルを開く")) { openFile(change.path) }.disabled(change.kind == .deleted).accessibilityIdentifier("git-row-file")
            Divider()
            Button(localized("Finder で表示")) { if let file = fileURL(change.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) } }.accessibilityIdentifier("git-row-finder")
            Button(localized("パスをコピー")) {
                if let file = fileURL(change.path) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string) }
            }.accessibilityIdentifier("git-row-copy-path")
        }
        .help(Text(verbatim: localized(GitTabPolicy.kindKey(change.kind)) + " · " + change.path))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rowLabel(change)))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("『変更』タブで開く", bundle: bundle)) { openChanges(change.path, false) }
        .accessibilityIdentifier("git-change-\(change.path)")
    }

    private func rowLabel(_ change: WorkingTreeChange) -> String {
        var label = localized(GitTabPolicy.kindKey(change.kind)) + ", " + change.path
        if change.isBinary { label += ", " + localized("バイナリファイル") }
        if let count = model.lineCounts[change.path] {
            label += ", " + String(format: localized("%lld 行追加、%lld 行削除"), count.added, count.deleted)
        }
        if model.freshPaths.contains(change.path) { label += ", " + localized("新しく出た") }
        return label
    }

    private func fileURL(_ path: String) -> URL? {
        let root = model.changeScope.repositoryRoot ?? workingDirectory
        return try? WorkingTreeService.relativeURL(for: path, relativeTo: URL(fileURLWithPath: root))
    }

    private func diffPane(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Text(verbatim: detailSummary).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { if let selected { openChanges(selected, false) } } label: {
                    Text("『変更』タブで開く", bundle: bundle) + Text(verbatim: " ↩").foregroundColor(DSColor.textSecondary)
                }
                    .buttonStyle(.plain).disabled(selected == nil)
                    .accessibilityLabel(Text("『変更』タブで開く", bundle: bundle))
                    .accessibilityIdentifier("git-inspector-open-changes")
            }.font(DSFont.meta).padding(.leading, DSSpacing.m).padding(.trailing, DSSpacing.s).frame(height: DSLayout.gitDiffHeaderHeight)
            if let detailError = loader.error { empty("差分を読み込めませんでした", explanation: detailError, retry: true) }
            else if let shownDetail {
                if shownDetail == .binary {
                    VStack(spacing: DSSpacing.chip) {
                        Text("バイナリファイル", bundle: bundle).font(DSFont.row.weight(.semibold))
                        Text(verbatim: binarySummary).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                        Text("差分は出しません。中身は「ファイルを開く」で確かめられます", bundle: bundle)
                            .font(DSFont.meta).foregroundStyle(DSColor.textSecondary).lineSpacing(DSSpacing.xxs)
                    }.multilineTextAlignment(.center).padding(DSSpacing.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else {
                    let preview = GitPreview.make(shownDetail)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(preview.lines.indices, id: \.self) { index in
                                diffLine(preview.lines[index], showNumbers: GitTabPolicy.showsLineNumbers(width: width))
                            }
                        }.padding(.vertical, DSSpacing.xs)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    if preview.remaining > 0 {
                        HStack(spacing: DSSpacing.s) {
                            Text(verbatim: String(format: localized("ほか %lld 行"), preview.remaining)).foregroundStyle(DSColor.textSecondary)
                            Button(localized("続きを『変更』タブで見る")) { if let selected { openChanges(selected, false) } }
                                .buttonStyle(.plain).underline()
                                .accessibilityLabel(Text("続きを『変更』タブで見る", bundle: bundle))
                                .accessibilityIdentifier("git-inspector-more")
                        }.font(DSFont.meta).padding(DSSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
                    }
                }
            } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("git-inspector-diff")
        .accessibilityLabel(Text("差分", bundle: bundle) + Text(verbatim: "、" + (selected.map { ($0 as NSString).lastPathComponent } ?? "")))
    }

    private var detailSummary: String {
        guard let change = model.changes.first(where: { $0.path == selected }) else { return "" }
        let kind = localized(GitTabPolicy.kindKey(change.kind))
        if change.isBinary { return kind + " · " + localized("バイナリ") }
        guard let counts = model.lineCounts[change.path] else { return kind }
        if change.kind == .untracked { return kind + " · " + String(format: localized("全 %lld 行"), counts.added) }
        var summary = kind + " · +\(counts.added) −\(counts.deleted)"
        if case .diff(let text) = shownDetail {
            let hunks = GitPreview.textLines(text).filter { $0.hasPrefix("@@") }.count
            if hunks > 0 { summary += " · " + String(format: localized("%lld か所"), hunks) }
        }
        return summary
    }

    private func diffLine(_ line: GitPreviewLine, showNumbers: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if showNumbers {
                Text(verbatim: line.number.map(String.init) ?? "").foregroundStyle(DSColor.textSecondary)
                    .frame(width: DSLayout.gitLineNumberWidth, alignment: .trailing).padding(.trailing, DSSpacing.xs).accessibilityHidden(true)
            }
            Text(verbatim: line.sign).frame(width: DSLayout.gitSignWidth)
            GitWrappedText(text: line.text.isEmpty ? " " : line.text, color: lineColor(line.kind))
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.font(DSFont.monoCaption)
        .frame(minHeight: DSLayout.gitDiffLineHeight)
        .foregroundStyle(lineColor(line.kind))
        .padding(.leading, showNumbers ? 0 : DSSpacing.xxs)
        .padding(.trailing, DSSpacing.s)
        .background(line.kind == .added ? DSColor.diffAddedTint.opacity(0.8) : line.kind == .deleted ? DSColor.diffRemovedTint.opacity(0.8) : DSColor.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: (line.kind == .added ? localized("追加") + ": " : line.kind == .deleted ? localized("削除") + ": " : "") + line.text))
    }

    private func lineColor(_ kind: GitPreviewLine.Kind) -> Color {
        kind == .added ? DSColor.diffAdded : kind == .deleted ? DSColor.diffRemoved : kind == .hunk ? DSColor.textSecondary : DSColor.textPrimary
    }

    private var binarySummary: String {
        guard let change = model.changes.first(where: { $0.path == selected }) else { return "" }
        var parts = [(change.path as NSString).lastPathComponent, localized(GitTabPolicy.kindKey(change.kind))]
        if let url = fileURL(change.path), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func empty(_ title: LocalizedStringKey, explanation: String, retry: Bool = false, path: Bool = false) -> some View {
        VStack(spacing: DSSpacing.s) {
            if retry {
                Image(systemName: "exclamationmark.circle").font(DSFont.gitFailureIcon)
                    .foregroundStyle(DSColor.attentionMark(.error)).accessibilityHidden(true)
            }
            Text(title, bundle: bundle).font(DSFont.row).foregroundStyle(retry || path ? DSColor.textPrimary : DSColor.textSecondary)
            Text(verbatim: explanation).font(retry || path ? DSFont.monoCaption : DSFont.meta).foregroundStyle(DSColor.textSecondary).textSelection(.enabled).lineSpacing(DSSpacing.xs)
            if retry {
                Button(localized("再試行")) {
                    Task {
                        if loader.error != nil { retryToken &+= 1 }
                        else { await model.refresh() }
                    }
                }.accessibilityLabel(Text("再試行", bundle: bundle)).accessibilityIdentifier("git-inspector-retry")
            }
        }.multilineTextAlignment(.center).padding(DSSpacing.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// コードの文字列を変えず、選択・コピーもできる文字単位の折り返し。
private struct GitWrappedText: NSViewRepresentable {
    var text: String
    var color: Color
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.isSelectable = true
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byCharWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        field.font = .monospacedSystemFont(ofSize: DSFont.monoCaptionSize, weight: .regular)
        field.textColor = NSColor(color)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: width, height: max(DSLayout.gitDiffLineHeight, size.height))
    }
}
