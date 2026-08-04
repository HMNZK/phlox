import SessionFeature
import SwiftUI

/// エディタパネルの内部レイアウトモードを、確定容器幅から純粋に決定する規則。
/// ドロワーの既定幅・最小幅（`PanelDrawerLayout.preferredWidth` / `.minimumWidth`）は
/// 左右分割表示の内在最小幅（`splitMinimumWidth`）より狭いため、幅が足りないときは
/// 変更リストと詳細ペインを縦積みへ切り替えて操作可能性を保つ。
public enum EditorPanelLayout: Equatable {
    case split
    case stacked

    /// 左右分割時の変更リストペインの最小幅。
    public static let changeListMinWidth: CGFloat = 180
    /// 左右分割時の詳細ペインの最小幅。
    public static let detailPaneMinWidth: CGFloat = 360
    /// HSplitView の区切り線幅の概算。
    private static let dividerWidth: CGFloat = 1

    /// 左右分割表示が内在的に必要とする最小幅。これを下回る幅では `.stacked` を選ぶ。
    public static let splitMinimumWidth: CGFloat =
        changeListMinWidth + detailPaneMinWidth + dividerWidth

    /// stacked 時の変更リスト領域の最小高（ファイル行スクロール領域）。
    /// ターミナルと同時表示でもエディタ枠内に収めるため内在最小高は抑える。
    /// コミット UI の可視性は独立ペイン化・`GitCommitPanel` のコンパクト化と
    /// `stackedCommitPanelBudget` で担保する。
    public static let stackedChangeListMinHeight: CGFloat = 72
    /// stacked 時の変更リストの理想高。
    public static let stackedChangeListIdealHeight: CGFloat = 180
    /// stacked 時に `GitCommitPanel` が占有してよい最大固有高（変更リスト行の残りを確保）。
    public static let stackedCommitPanelBudget: CGFloat = 168
    /// `workflowStatusMessage` 表示の最大高。長い git 出力でもボタン列を押し出さない。
    public static let commitStatusMaxHeight: CGFloat = 40

    public static func mode(forWidth width: CGFloat) -> EditorPanelLayout {
        width >= splitMinimumWidth ? .split : .stacked
    }
}

/// 変更ファイルの確認と保存を行う、容器に依存しないエディタパネル。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var showsConflictAlert = false
    @State private var previewLineLimit = 500
    /// ドロワー内での最上段要素にだけ 28pt（最前面オーバーレイのトップバーと非衝突分）を
    /// 付ける。容器（DashboardView）側が積み位置に応じて渡す。
    private let topInset: CGFloat

    public init(viewModel: EditorPanelViewModel, topInset: CGFloat = 28) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.topInset = topInset
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text("エディタ")
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            GeometryReader { geometry in
                editorContent(for: EditorPanelLayout.mode(forWidth: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, topInset)
        .accessibilityIdentifier("editor-panel")
        .onChange(of: viewModel.selectedPath) { _, _ in
            previewLineLimit = 500
        }
        .alert("File changed on disk", isPresented: $showsConflictAlert) {
            Button("Overwrite", role: .destructive) {
                Task { await overwrite() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was changed after it was loaded. Overwrite it with your draft?")
        }
    }

    /// ドロワー幅に応じて左右分割・上下積みを切り替える。しきい値の判断は
    /// `EditorPanelLayout`（純粋型・白箱テスト対象）へ切り出してある。
    @ViewBuilder
    private func editorContent(for mode: EditorPanelLayout) -> some View {
        switch mode {
        case .split:
            HSplitView {
                changeList
                    .frame(
                        minWidth: EditorPanelLayout.changeListMinWidth,
                        idealWidth: 240,
                        maxWidth: 320
                    )

                detailPane
                    .frame(minWidth: EditorPanelLayout.detailPaneMinWidth)
            }
        case .stacked:
            VSplitView {
                ScrollView {
                    changeFilesSection(embedsFileListInScrollView: false)
                        .padding()
                }
                .frame(
                    minHeight: EditorPanelLayout.stackedChangeListMinHeight,
                    idealHeight: EditorPanelLayout.stackedChangeListIdealHeight
                )

                if showsCommitPanel {
                    GitCommitPanel(viewModel: viewModel)
                        .padding(.horizontal)
                        .frame(maxHeight: EditorPanelLayout.stackedCommitPanelBudget)
                }

                detailPane
                    .frame(minHeight: 72, idealHeight: 100)
            }
        }
    }

    private var showsCommitPanel: Bool {
        switch viewModel.listState {
        case .ready:
            return viewModel.listErrorMessage == nil
        case .noProject, .notARepository:
            return false
        }
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            changeFilesSection(embedsFileListInScrollView: true)
            if showsCommitPanel {
                Divider()
                GitCommitPanel(viewModel: viewModel)
            }
        }
        .padding()
    }

    /// 変更一覧のファイル行だけ（Commit パネルは含めない）。
    /// - Parameter embedsFileListInScrollView: split 列内ではファイル行だけを ScrollView に包む。
    ///   stacked では外側 ScrollView がスクロールを担うため `false` にする。
    @ViewBuilder
    private func changeFilesSection(embedsFileListInScrollView: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            changeFilesSectionHeader
            if embedsFileListInScrollView && showsChangeFileRows {
                ScrollView {
                    changeFilesBody
                }
            } else {
                changeFilesBody
            }
        }
    }

    private var showsChangeFileRows: Bool {
        if case .ready = viewModel.listState, viewModel.listErrorMessage == nil {
            return true
        }
        return false
    }

    @ViewBuilder
    private var changeFilesSectionHeader: some View {
        if case .shared = viewModel.changeScope {
            Label {
                Text(
                    "このプロジェクトの全変更を表示しており、このセッションの変更とは限らないことがあります。"
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "このプロジェクトの全変更を表示しており、このセッションの変更とは限らないことがあります。"
            )
            .accessibilityIdentifier("session-change-scope-notice")
        }

        HStack {
            Text("Changes")
                .font(.headline)
            Spacer()
            Button("Refresh") {
                Task { await viewModel.refresh() }
            }
        }
    }

    @ViewBuilder
    private var changeFilesBody: some View {
        switch viewModel.listState {
        case .noProject:
            ContentUnavailableView("No project selected", systemImage: "folder")
        case .notARepository:
            ContentUnavailableView("Not a Git repository", systemImage: "exclamationmark.triangle")
        case .ready:
            if let listErrorMessage = viewModel.listErrorMessage {
                ContentUnavailableView(
                    "Unable to load changes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(listErrorMessage)
                )
            } else {
                changeFileRows
            }
        }
    }

    @ViewBuilder
    private var changeFileRows: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(viewModel.changes, id: \.path) { change in
                changeFileRow(change)
            }
        }
    }

    private func changeFileRow(_ change: WorkingTreeChange) -> some View {
        HStack(spacing: 6) {
            Button {
                viewModel.toggleCommitSelection(for: change.path)
            } label: {
                Image(
                    systemName: viewModel.pathsSelectedForCommit.contains(change.path)
                        ? "checkmark.square.fill"
                        : "square"
                )
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(change.path) for commit")
            .accessibilityIdentifier("git-commit-select-\(change.path)")

            Button {
                Task { await viewModel.select(change.path) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: change))
                    Text(change.path)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if change.isBinary {
                        Image(systemName: "doc.badge.ellipsis")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(
                    viewModel.selectedPath == change.path
                        ? Color.accentColor.opacity(0.16)
                        : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailPreview

            if let readOnlyMessage = viewModel.readOnlyMessage {
                Label(readOnlyMessage, systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.canEdit {
                Divider()
                Text("Edit")
                    .font(.headline)
                TextEditor(text: $viewModel.draft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)

                HStack {
                    if viewModel.isDirty {
                        Text("Unsaved changes")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!viewModel.isDirty)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var detailPreview: some View {
        switch viewModel.detail {
        case .none:
            ContentUnavailableView("Select a changed file", systemImage: "doc.text")
        case .binary:
            ContentUnavailableView("Binary file", systemImage: "doc.badge.ellipsis")
        case .diff(let diff):
            highlightedPreview(diff, title: "Diff")
        case .content(let content):
            highlightedPreview(content, title: "Contents")
        }
    }

    private func highlightedPreview(_ text: String, title: String) -> some View {
        let preview = preview(of: text)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Text(ChatCodeHighlighter.highlight(preview.text))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
            if preview.isTruncated {
                Button("Show 500 more lines") {
                    previewLineLimit += 500
                }
                .font(.caption)
            }
        }
    }

    private func preview(of text: String) -> (text: String, isTruncated: Bool) {
        var end = text.startIndex
        for _ in 0..<previewLineLimit {
            guard let newline = text[end...].firstIndex(of: "\n") else {
                return (text, false)
            }
            end = text.index(after: newline)
        }
        return (String(text[..<end]), end < text.endIndex)
    }

    private func icon(for change: WorkingTreeChange) -> String {
        if change.isBinary { return "doc.badge.ellipsis" }
        switch change.kind {
        case .modified: return "pencil"
        case .added, .untracked: return "plus"
        case .deleted: return "minus"
        case .renamed: return "arrow.left.arrow.right"
        }
    }

    private func save() async {
        do {
            if try await viewModel.save() == .conflictDetected {
                showsConflictAlert = true
            }
        } catch {
            // 選択対象が消えた場合は VM が公開状態を安全な空状態へ戻す。
        }
    }

    private func overwrite() async {
        do {
            try await viewModel.overwrite()
        } catch {
            // 上書き対象が消えた場合も VM の公開状態は維持する。
        }
    }
}
