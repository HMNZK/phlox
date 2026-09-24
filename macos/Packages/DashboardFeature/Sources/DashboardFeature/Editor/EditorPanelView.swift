import DesignSystem
import SessionFeature
import SwiftUI

/// エディタパネルの内部レイアウトモードを、確定容器幅から純粋に決定する規則。
/// 変更タブが広ければ左右分割を表示し、左右分割の片側（最小 320pt）など幅が足りないときは
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

    public static func mode(forWidth width: CGFloat) -> EditorPanelLayout {
        width >= splitMinimumWidth ? .split : .stacked
    }
}

/// 変更の種類の SF Symbol。画面は文字（`editorChangeLetter`）で描くようにしたが、凍結テスト
/// `EditorPanelIconWhiteboxTests` が固定しているので残している。
func editorChangeIcon(for change: WorkingTreeChange) -> String {
    switch change.kind {
    case .modified: return "pencil"
    case .added: return "plus"
    case .untracked: return "plus.circle"
    case .deleted: return "minus"
    case .renamed: return "arrow.forward.square"
    }
}

/// 変更の種類の文字（07 D2: M / A / R / D / U）。バイナリは「B」。
func editorChangeLetter(for change: WorkingTreeChange) -> String {
    if change.isBinary { return "B" }
    switch change.kind {
    case .modified: return "M"
    case .added: return "A"
    case .untracked: return "U"
    case .deleted: return "D"
    case .renamed: return "R"
    }
}

/// 追加は差分の緑、削除は差分の赤、ほかは無彩色（状態の色は対応待ちだけに使う）。
func editorChangeColor(for change: WorkingTreeChange) -> Color {
    if change.isBinary { return DSColor.textTertiary }
    switch change.kind {
    case .added, .untracked:
        return DSColor.diffAdded
    case .deleted:
        return DSColor.diffRemoved
    case .modified, .renamed:
        return DSColor.textSecondary
    }
}

/// 変更の子タブ（02 C）。変更一覧・差分／内容・コミット。編集はファイルの子タブで行う。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var previewLineLimit = 500
    @State private var showsContent = false
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var splitChangeListMaxWidth: CGFloat = 320
    @ScaledMetric(relativeTo: .body) private var splitChangeListIdealWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var editorMinHeight: CGFloat = 160
    @ScaledMetric(relativeTo: .body) private var stackedDetailMinHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var stackedDetailIdealHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var stackedChangeListMinHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var stackedChangeListIdealHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var minimumTapTarget: CGFloat = 28
    /// 選んだ変更ファイルをファイルの子タブで開く。
    private let onEditFile: (String) -> Void

    public init(viewModel: EditorPanelViewModel, onEditFile: @escaping (String) -> Void = { _ in }) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.onEditFile = onEditFile
    }

    public var body: some View {
        GeometryReader { geometry in
            // 分割ビューが理想の高さで伸びてはみ出さないよう、タブの大きさに固定する。
            editorContent(for: EditorPanelLayout.mode(forWidth: geometry.size.width))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("tab.changes"))
        .accessibilityIdentifier("editor-panel")
        .onChange(of: viewModel.selectedPath) { _, _ in
            previewLineLimit = 500
            showsContent = false
        }
    }

    /// タブ幅に応じて左右分割・上下積みを切り替える。しきい値の判断は
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
                        maxWidth: splitChangeListMaxWidth,
                        maxHeight: .infinity,
                        alignment: .top
                    )

                detailPane
                    .frame(minWidth: EditorPanelLayout.detailPaneMinWidth, maxHeight: .infinity, alignment: .top)
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
            Text("tab.changes")
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
                HStack(spacing: 8) {
                    Text(verbatim: editorChangeLetter(for: change))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(editorChangeColor(for: change))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: (change.path as NSString).lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: directoryText(for: change))
                            .font(.system(size: 10.5))
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, DSSpacing.xs)
                .background(
                    viewModel.selectedPath == change.path
                        ? DSColor.fillSelected
                        : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: change.path))
            .accessibilityLabel(Text(verbatim: "\(editorChangeLetter(for: change)) \(change.path)"))
        }
    }

    /// 行の 2 行目。フォルダ（バイナリは「（バイナリ）」を足す）。
    private func directoryText(for change: WorkingTreeChange) -> String {
        let directory = (change.path as NSString).deletingLastPathComponent
        let binary = change.isBinary ? AppLocalizedString.string("（バイナリ）", locale: locale) : ""
        return directory + binary
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            detailPreview

            if let readOnlyMessage = viewModel.readOnlyMessage {
                Label(readOnlyMessage, systemImage: "eye")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if viewModel.canEdit, let path = viewModel.selectedPath {
                HStack {
                    Spacer()
                    Button("ファイルタブで編集") {
                        onEditFile(path)
                    }
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
            // 差分のとき、中身を読めていれば「差分 / 内容」を切り替えられる（07 の対応表）。
            if showsContent && viewModel.canEdit {
                highlightedPreview(viewModel.draft, canSwitch: true)
            } else {
                highlightedPreview(diff, canSwitch: viewModel.canEdit, isDiff: true)
            }
        case .content(let content):
            highlightedPreview(content, canSwitch: false)
        }
    }

    private func highlightedPreview(_ text: String, canSwitch: Bool, isDiff: Bool = false) -> some View {
        let preview = preview(of: text)
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: 8) {
                if canSwitch {
                    NeutralSegmentedControl(
                        selection: $showsContent,
                        options: [(false, "差分"), (true, "内容")],
                        fillsWidth: false,
                        height: 20,
                        fontSize: 11.5
                    )
                    .fixedSize()
                } else {
                    Text("内容")
                        .font(DSFont.sectionHeader)
                }
                if let path = viewModel.selectedPath {
                    Text(verbatim: (path as NSString).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(isDiff ? Self.diffHighlight(preview.text) : ChatCodeHighlighter.highlight(preview.text))
                    .font(DSFont.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: editorMinHeight)
            if preview.remainingLines > 0 {
                Button(String(format: AppLocalizedString.string("さらに表示（残り %lld 行）", locale: locale), preview.remainingLines)) {
                    previewLineLimit += 500
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.accentInk)
            }
        }
    }

    /// 差分の行を追加は緑・削除は赤で塗る（07 D2）。見出し（+++ / ---）は塗らない。
    private static func diffHighlight(_ text: String) -> AttributedString {
        var output = AttributedString()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var chunk = AttributedString(line + "\n")
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                chunk.foregroundColor = DSColor.diffAdded
                chunk.backgroundColor = DSColor.diffAdded.opacity(0.1)
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                chunk.foregroundColor = DSColor.diffRemoved
                chunk.backgroundColor = DSColor.diffRemoved.opacity(0.09)
            } else {
                chunk.foregroundColor = DSColor.textPrimary
            }
            output += chunk
        }
        return output
    }

    private func preview(of text: String) -> (text: String, remainingLines: Int) {
        var end = text.startIndex
        for _ in 0..<previewLineLimit {
            guard let newline = text[end...].firstIndex(of: "\n") else {
                return (text, 0)
            }
            end = text.index(after: newline)
        }
        guard end < text.endIndex else { return (text, 0) }
        let rest = text[end...]
        return (String(text[..<end]), rest.reduce(into: 0) { if $1 == "\n" { $0 += 1 } } + (rest.last == "\n" ? 0 : 1))
    }
}
