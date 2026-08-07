import DesignSystem
import SessionFeature
import SwiftUI

/// エディタパネルの内部レイアウトモードを、確定容器幅から純粋に決定する規則。
/// ドロワーの既定幅（`PanelDrawerLayout.preferredWidth`）では左右分割を表示し、
/// 最小幅（`.minimumWidth`）など幅が足りないときは変更リストと詳細ペインを縦積みへ
/// 切り替えて操作可能性を保つ。
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

    public static func mode(forWidth width: CGFloat) -> EditorPanelLayout {
        width >= splitMinimumWidth ? .split : .stacked
    }
}

func editorChangeIcon(for change: WorkingTreeChange) -> String {
    switch change.kind {
    case .modified: return "pencil"
    case .added: return "plus"
    case .untracked: return "plus.circle"
    case .deleted: return "minus"
    case .renamed: return "arrow.forward.square"
    }
}

func editorChangeColor(for change: WorkingTreeChange) -> Color {
    switch change.kind {
    case .added:
        return DSColor.diffAdded
    case .untracked:
        return DSColor.statusAwaitingApproval
    case .deleted:
        return DSColor.diffRemoved
    case .modified, .renamed:
        return DSColor.statusAwaitingApproval
    }
}

/// 変更ファイルの確認と保存を行う、容器に依存しないエディタパネル。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var showsConflictAlert = false
    @State private var previewLineLimit = 500
    @ScaledMetric(relativeTo: .body) private var splitChangeListMaxWidth: CGFloat = 320
    @ScaledMetric(relativeTo: .body) private var splitChangeListIdealWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var editorMinHeight: CGFloat = 160
    @ScaledMetric(relativeTo: .body) private var stackedDetailMinHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var stackedDetailIdealHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var stackedChangeListMinHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var stackedChangeListIdealHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var minimumTapTarget: CGFloat = 28
    /// ドロワー内での最上段要素にだけ 28pt（最前面オーバーレイのトップバーと非衝突分）を
    /// 付ける。容器（DashboardView）側が積み位置に応じて渡す。
    private let topInset: CGFloat

    public init(viewModel: EditorPanelViewModel, topInset: CGFloat = 28) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.topInset = topInset
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "doc.text")
                    .foregroundStyle(DSColor.textSecondary)
                Text("エディタ")
                    .font(DSFont.bodyMedium)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.l)
            .padding(.vertical, DSSpacing.s)

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
        .alert("ファイルがディスク上で変更されました", isPresented: $showsConflictAlert) {
            Button("上書き", role: .destructive) {
                Task { await overwrite() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("読み込み後にファイルが変更されました。下書きで上書きしますか？")
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
                        idealWidth: splitChangeListIdealWidth,
                        maxWidth: splitChangeListMaxWidth
                    )

                detailPane
                    .frame(minWidth: EditorPanelLayout.detailPaneMinWidth)
            }
        case .stacked:
            VSplitView {
                ScrollView {
                    changeFilesSection
                        .padding(DSSpacing.l)
                }
                .frame(
                    minHeight: stackedChangeListMinHeight,
                    idealHeight: stackedChangeListIdealHeight
                )

                if showsCommitPanel {
                    ScrollView {
                        GitCommitPanel(viewModel: viewModel)
                            .padding(.horizontal, DSSpacing.l)
                    }
                }

                detailPane
                    .frame(minHeight: stackedDetailMinHeight, idealHeight: stackedDetailIdealHeight)
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
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                changeFilesSection
                if showsCommitPanel {
                    Divider()
                    GitCommitPanel(viewModel: viewModel)
                }
            }
            .padding(DSSpacing.l)
        }
    }

    @ViewBuilder
    private var changeFilesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            if case .shared = viewModel.changeScope, !showsCommitPanel {
                ChangeScopeNotice()
            }
            changeFilesSectionHeader
            changeFilesBody
        }
    }

    @ViewBuilder
    private var changeFilesSectionHeader: some View {
        HStack {
            Text("変更")
                .font(DSFont.sectionHeader)
            Spacer()
            Button("更新") {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isRefreshing)
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("変更を更新中")
                .opacity(viewModel.isRefreshing ? 1 : 0)
                .accessibilityHidden(!viewModel.isRefreshing)
        }
    }

    @ViewBuilder
    private var changeFilesBody: some View {
        switch viewModel.listState {
        case .noProject:
            ContentUnavailableView("プロジェクトが選択されていません", systemImage: "folder")
        case .notARepository:
            ContentUnavailableView("Gitリポジトリではありません", systemImage: "exclamationmark.triangle")
        case .ready:
            if let listErrorMessage = viewModel.listErrorMessage {
                ContentUnavailableView(
                    "変更を読み込めません",
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
        LazyVStack(alignment: .leading, spacing: DSSpacing.xxs) {
            ForEach(viewModel.changes, id: \.path) { change in
                changeFileRow(change)
            }
        }
    }

    private func changeFileRow(_ change: WorkingTreeChange) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Button {
                viewModel.toggleCommitSelection(for: change.path)
            } label: {
                Image(
                    systemName: viewModel.pathsSelectedForCommit.contains(change.path)
                        ? "checkmark.square.fill"
                        : "square"
                )
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: minimumTapTarget, height: minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(change.path) をコミット対象に選択")
            .accessibilityIdentifier("git-commit-select-\(change.path)")

            Button {
                Task { await viewModel.select(change.path) }
            } label: {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: editorChangeIcon(for: change))
                        .foregroundStyle(editorChangeColor(for: change))
                    Text(change.path)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if change.isBinary {
                        Image(systemName: "doc.badge.ellipsis")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, DSSpacing.xs)
                .background(
                    viewModel.selectedPath == change.path
                        ? DSColor.fillSelected
                        : .clear,
                    in: RoundedRectangle(cornerRadius: DSRadius.m)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            detailPreview

            if let readOnlyMessage = viewModel.readOnlyMessage {
                Label(readOnlyMessage, systemImage: "eye")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if viewModel.canEdit {
                Divider()
                Text("編集")
                    .font(DSFont.sectionHeader)
                TextEditor(text: $viewModel.draft)
                    .font(DSFont.mono)
                    .frame(minHeight: editorMinHeight)

                HStack {
                    if viewModel.isDirty {
                        Text("未保存の変更")
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(!viewModel.isDirty)
                }
            }
        }
        .padding(DSSpacing.l)
    }

    @ViewBuilder
    private var detailPreview: some View {
        switch viewModel.detail {
        case .none:
            ContentUnavailableView("変更されたファイルを選択", systemImage: "doc.text")
        case .binary:
            ContentUnavailableView("バイナリファイル", systemImage: "doc.badge.ellipsis")
        case .diff(let diff):
            highlightedPreview(diff, title: "差分")
        case .content(let content):
            highlightedPreview(content, title: "内容")
        }
    }

    private func highlightedPreview(_ text: String, title: String) -> some View {
        let preview = preview(of: text)
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSFont.sectionHeader)
            ScrollView([.horizontal, .vertical]) {
                Text(ChatCodeHighlighter.highlight(preview.text))
                    .font(DSFont.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: editorMinHeight)
            if preview.isTruncated {
                Button("さらに500行を表示") {
                    previewLineLimit += 500
                }
                .font(DSFont.caption)
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
