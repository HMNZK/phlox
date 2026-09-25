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

/// 変更の子タブ（02 C・07 D2）。上から見出しの帯・共有の注意・変更一覧と差分／内容・下端に固定したコミット欄。
/// 編集はファイルの子タブで行う。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var previewLineLimit = 500
    @State private var showsContent = false
    @Environment(\.locale) private var locale
    private let projectName: String
    private let workingDirectory: String
    private let isDirty: (String) -> Bool
    /// 選んだ変更ファイルをファイルの子タブで開く。
    private let onEditFile: (String) -> Void

    /// 左右分割の一覧の幅（07 D2b）。
    static let splitChangeListWidth: CGFloat = 220
    /// 上下積みの一覧の高さの上限。
    static let stackedChangeListMaxHeight: CGFloat = 190

    public init(
        viewModel: EditorPanelViewModel,
        projectName: String = "",
        workingDirectory: String = "",
        isDirty: @escaping (String) -> Bool = { _ in false },
        onEditFile: @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.isDirty = isDirty
        self.onEditFile = onEditFile
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if case .shared = viewModel.changeScope {
                    ChangeScopeNotice()
                }
                switch viewModel.listState {
                case .noProject:
                    centeredMessage(Text("プロジェクトが選択されていません"), detail: nil)
                case .notARepository:
                    centeredMessage(
                        Text("Git リポジトリではありません"),
                        detail: Text(verbatim: String(
                            format: AppLocalizedString.string("%@ には .git がないため、変更の一覧とコミットは使えません。ファイルの編集はターミナルから行えます。", locale: locale),
                            abbreviatedWorkingDirectory
                        ))
                    )
                case .ready:
                    if let listErrorMessage = viewModel.listErrorMessage {
                        centeredMessage(Text("変更を読み込めません"), detail: Text(verbatim: listErrorMessage))
                    } else {
                        // 分割ビューが理想の高さで伸びてはみ出さないよう、残りの高さに収める。
                        editorContent(for: EditorPanelLayout.mode(forWidth: geometry.size.width))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                if showsCommitPanel {
                    GitCommitPanel(viewModel: viewModel)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("tab.changes"))
        .accessibilityIdentifier("editor-panel")
        .onChange(of: viewModel.selectedPath) { _, _ in
            previewLineLimit = 500
            showsContent = false
        }
    }

    private var abbreviatedWorkingDirectory: String {
        (workingDirectory as NSString).abbreviatingWithTildeInPath
    }

    /// 高さ 34・panel 面の帯。「エディタ」「プロジェクト · 変更 n」（Git でなければ場所）と更新。
    private var header: some View {
        HStack(spacing: 8) {
            Text("エディタ")
                .font(DSFont.auxiliary.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(verbatim: headerSubtitle)
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textSecondary)
                        .opacity(viewModel.isRefreshing ? 0 : 1)
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("変更を更新中")
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .disabled(viewModel.isRefreshing)
            .help(Text("変更を更新"))
            .accessibilityLabel(Text("変更を更新"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(DSColor.surface)
        .overlay(alignment: .bottom) { separator(horizontal: true) }
    }

    private var headerSubtitle: String {
        if case .notARepository = viewModel.listState { return abbreviatedWorkingDirectory }
        return String(format: AppLocalizedString.string("%@ · 変更 %lld", locale: locale), projectName, viewModel.changes.count)
    }

    private func centeredMessage(_ title: Text, detail: Text?) -> some View {
        VStack(spacing: 8) {
            title
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            if let detail {
                detail
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func separator(horizontal: Bool) -> some View {
        Rectangle()
            .fill(DSColor.separator)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : nil)
    }

    /// タブ幅に応じて左右分割・上下積みを切り替える。しきい値の判断は
    /// `EditorPanelLayout`（純粋型・白箱テスト対象）へ切り出してある。
    @ViewBuilder
    private func editorContent(for mode: EditorPanelLayout) -> some View {
        switch mode {
        case .split:
            HStack(spacing: 0) {
                changeList
                    .frame(width: Self.splitChangeListWidth)
                separator(horizontal: false)
                detailPane
            }
        case .stacked:
            VStack(spacing: 0) {
                changeList
                    .frame(maxHeight: Self.stackedChangeListMaxHeight)
                separator(horizontal: true)
                detailPane
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
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(viewModel.changes, id: \.path) { change in
                    changeFileRow(change)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    /// 高さ 34 の行。チェック（13×13）・種別の文字・名前とフォルダ・未保存の点。選択中は `--sel`。
    private func changeFileRow(_ change: WorkingTreeChange) -> some View {
        let checked = viewModel.pathsSelectedForCommit.contains(change.path)
        return HStack(spacing: 4) {
            Button {
                viewModel.toggleCommitSelection(for: change.path)
            } label: {
                CommitCheckbox(isOn: checked)
                    .padding(.horizontal, 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(change.path) をコミット対象に選択")
            .accessibilityAddTraits(checked ? .isSelected : [])
            .accessibilityIdentifier("git-commit-select-\(change.path)")

            Button {
                Task { await viewModel.select(change.path) }
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: editorChangeLetter(for: change))
                        .font(DSFont.monoCaption.weight(.bold))
                        .foregroundStyle(editorChangeColor(for: change))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: (change.path as NSString).lastPathComponent)
                            .font(DSFont.auxiliary)
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
                    if isDirty(change.path) {
                        Circle()
                            .fill(DSColor.textPrimary)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(Text("未保存"))
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: change.path))
            .accessibilityLabel(Text(verbatim: "\(editorChangeLetter(for: change)) \(change.path)"))
            .accessibilityAddTraits(viewModel.selectedPath == change.path ? .isSelected : [])
        }
        .padding(.leading, 4)
        .frame(height: 34)
        .background(
            viewModel.selectedPath == change.path ? DSColor.fillSelected : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    /// 行の 2 行目。フォルダ（バイナリは「（バイナリ）」を足す）。
    private func directoryText(for change: WorkingTreeChange) -> String {
        let directory = (change.path as NSString).deletingLastPathComponent
        let binary = change.isBinary ? AppLocalizedString.string("（バイナリ）", locale: locale) : ""
        return directory + binary
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            switch viewModel.detail {
            case .none:
                placeholder(Text("変更されたファイルを選択"))
            case .binary:
                detailHeader(canSwitch: false)
                placeholder(Text("バイナリファイル"))
            case .diff(let diff):
                // 差分のとき、中身を読めていれば「差分 / 内容」を切り替えられる（07 の対応表）。
                detailHeader(canSwitch: viewModel.canEdit)
                if showsContent && viewModel.canEdit {
                    codeLines(EditorCodeLines.content(viewModel.draft), isDiff: false)
                } else {
                    codeLines(EditorCodeLines.diff(diff), isDiff: true)
                }
            case .content(let content):
                detailHeader(canSwitch: false)
                codeLines(EditorCodeLines.content(content), isDiff: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func placeholder(_ text: Text) -> some View {
        text
            .font(DSFont.auxiliary)
            .foregroundStyle(DSColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 高さ 30 の帯。「差分 / 内容」・ファイル名・（読むだけの理由）・ファイルタブで編集。
    private func detailHeader(canSwitch: Bool) -> some View {
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
            }
            if let path = viewModel.selectedPath {
                Text(verbatim: (path as NSString).lastPathComponent)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(Text(verbatim: path))
            }
            Spacer(minLength: 0)
            if let readOnlyMessage = viewModel.readOnlyMessage {
                Text(verbatim: readOnlyMessage)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(Text(verbatim: readOnlyMessage))
            }
            if viewModel.canEdit, let path = viewModel.selectedPath {
                Button("ファイルタブで編集") {
                    onEditFile(path)
                }
                .buttonStyle(.ds(.secondary, height: 20, fontSize: 11, padding: 8))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay(alignment: .bottom) { separator(horizontal: true) }
    }

    /// 11.5pt の等幅・行の高さ 1.7。左に幅 28 の行番号、追加・削除は行全体を塗って「+ 」「− 」を付ける。
    private func codeLines(_ lines: [EditorCodeLine], isDiff: Bool) -> some View {
        let shown = Array(lines.prefix(previewLineLimit))
        let rest = EditorCodeLines.remainder(of: lines, after: previewLineLimit)
        return GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                        codeLine(line, isDiff: isDiff)
                            .frame(minWidth: viewport.size.width, alignment: .leading)
                            .background(lineTint(line.kind))
                    }
                    if rest.lines > 0 {
                        Button(moreLabel(rest, isDiff: isDiff)) {
                            previewLineLimit += 500
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.accentInk)
                        .padding(.leading, 50)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func moreLabel(_ rest: (hunks: Int, lines: Int), isDiff: Bool) -> String {
        if isDiff {
            return String(format: AppLocalizedString.string("さらに表示（残り %lld 塊 · %lld 行）", locale: locale), rest.hunks, rest.lines)
        }
        return String(format: AppLocalizedString.string("さらに表示（残り %lld 行）", locale: locale), rest.lines)
    }

    private func codeLine(_ line: EditorCodeLine, isDiff: Bool) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: line.number.map(String.init) ?? "")
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: 28, alignment: .trailing)
                .padding(.trailing, 10)
            Text(lineText(line, isDiff: isDiff))
                .fixedSize()
                .textSelection(.enabled)
        }
        // 読み上げは「行番号 記号 本文」を 1 つにまとめる（+ / − で追加・削除が分かる）。
        .accessibilityElement(children: .combine)
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(minHeight: 19.5)
    }

    private func lineText(_ line: EditorCodeLine, isDiff: Bool) -> AttributedString {
        guard isDiff else { return ChatCodeHighlighter.highlight(line.text) }
        var text: AttributedString
        switch line.kind {
        case .added:
            text = AttributedString("+ " + line.text)
            text.foregroundColor = DSColor.diffAdded
        case .removed:
            text = AttributedString("− " + line.text)
            text.foregroundColor = DSColor.diffRemoved
        case .context:
            text = AttributedString("  " + line.text)
            text.foregroundColor = DSColor.textPrimary
        case .hunk:
            text = AttributedString(line.text)
            text.foregroundColor = DSColor.textTertiary
        }
        return text
    }

    private func lineTint(_ kind: EditorCodeLine.Kind) -> Color {
        switch kind {
        case .added: DSColor.diffAddedTint
        case .removed: DSColor.diffRemovedTint
        case .context, .hunk: .clear
        }
    }
}

/// コミット対象のチェック（07 D2）。13×13・角丸 3.5。オンは accentFill に白の ✓、オフは 1.2pt の fg3 の枠。
struct CommitCheckbox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 3.5).fill(DSColor.accentFill)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: 3.5).strokeBorder(DSColor.textTertiary, lineWidth: 1.2)
            }
        }
        .frame(width: 13, height: 13)
    }
}
