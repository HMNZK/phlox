import DesignSystem
import SessionFeature
import SwiftUI

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

/// Git タブで選んだ 1 ファイルの差分／内容を表示する子タブ。
/// 編集はファイルの子タブで行う。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var previewLineLimit = 500
    @State private var showsContent = false
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle
    private let projectName: String
    private let workingDirectory: String
    private let isDirty: (String) -> Bool
    private let focusRequest: Int
    @FocusState private var detailFocused: Bool
    /// 選んだ変更ファイルをファイルの子タブで開く。
    private let onEditFile: (String) -> Void

    public init(
        viewModel: EditorPanelViewModel,
        projectName: String = "",
        workingDirectory: String = "",
        isDirty: @escaping (String) -> Bool = { _ in false },
        onEditFile: @escaping (String) -> Void = { _ in },
        focusRequest: Int = 0
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.isDirty = isDirty
        self.onEditFile = onEditFile
        self.focusRequest = focusRequest
    }

    public var body: some View {
        VStack(spacing: 0) {
            if case .shared = viewModel.changeScope { ChangeScopeNotice() }
            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("tab.changes", bundle: bundle))
        .accessibilityIdentifier("editor-panel")
        .onChange(of: viewModel.gitSelection) { _, _ in
            previewLineLimit = 500
            showsContent = false
        }
        .onChange(of: focusRequest, initial: true) { _, request in if request > 0 { detailFocused = true } }
    }

    private func separator(horizontal: Bool) -> some View {
        Rectangle().fill(DSColor.separator)
            .frame(width: horizontal ? nil : DSLayout.paneSeparatorWidth,
                   height: horizontal ? DSLayout.paneSeparatorWidth : nil)
    }

    @ViewBuilder private var sourceLabel: some View {
        switch viewModel.selectedSource {
        case .worktree: Text("作業ツリー", bundle: bundle)
        case .staged: Text("ステージ済み", bundle: bundle)
        case .commit(let id): Text("コミット \(String(id.prefix(7)))", bundle: bundle)
        case .stash(_, let name): Text(verbatim: name)
        }
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            switch viewModel.detail {
            case .none:
                detailHeader(canSwitch: true)
                VStack(spacing: DSSpacing.s) {
                    Image(systemName: "sidebar.right").font(DSFont.title).accessibilityHidden(true)
                    Text("Git タブで変更を選んでください", bundle: bundle)
                        .font(DSFont.auxiliary.weight(.semibold))
                        .accessibilityIdentifier("editor-no-selection")
                    Text("右の Git タブで変更・コミット・スタッシュのファイルを押すと、ここにその差分を出します。", bundle: bundle)
                        .font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("editor-no-selection-help")
                    HStack(spacing: DSSpacing.chip) {
                        Text("Git タブを表示", bundle: bundle)
                        Text(verbatim: "⇧⌃⌘G").font(DSFont.monoCaption)
                    }.font(DSFont.meta).accessibilityIdentifier("editor-git-shortcut")
                }.multilineTextAlignment(.center).padding(DSSpacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(DSColor.textTertiary)
            case .binary:
                detailHeader(canSwitch: false)
                placeholder(Text("バイナリファイル", bundle: bundle))
            case .diff(let diff):
                // 差分のとき、中身を読めていれば「差分 / 内容」を切り替えられる（07 の対応表）。
                detailHeader(canSwitch: viewModel.canViewContent)
                if showsContent && viewModel.canViewContent {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("変更", bundle: bundle))
        .accessibilityIdentifier("editor-diff")
    }

    private func placeholder(_ text: Text) -> some View {
        text
            .font(DSFont.auxiliary)
            .foregroundStyle(DSColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 高さ 30 の帯。「差分 / 内容」・ファイル名・（読むだけの理由）・ファイルタブで編集。
    private func detailHeader(canSwitch: Bool) -> some View {
        HStack(spacing: DSSpacing.s) {
            if canSwitch {
                NeutralSegmentedControl(
                    selection: $showsContent,
                    options: [(false, "差分"), (true, "内容")],
                    fillsWidth: false,
                    height: DSLayout.fileTreeInputHeight,
                    fontSize: DSFont.monoCaptionSize
                )
                .fixedSize()
                .disabled(viewModel.selectedPath == nil)
            }
            if let path = viewModel.selectedPath {
                Text(verbatim: (path as NSString).lastPathComponent)
                    .font(DSFont.monoCaption).foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1).truncationMode(.middle).help(Text(verbatim: path))
                Text(verbatim: (path as NSString).deletingLastPathComponent)
                    .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1).truncationMode(.head)
                    .accessibilityIdentifier("editor-diff-folder")
                sourceLabel
                    .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.xs).padding(.vertical, DSSpacing.xxs)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s))
                    .accessibilityIdentifier("editor-diff-source")
                let counts = viewModel.selectedSource.isHistory ? nil : viewModel.selectedSource == .staged ? viewModel.stagedLineCounts[path] : viewModel.unstagedLineCounts[path]
                if let counts {
                    HStack(spacing: DSSpacing.xs) {
                        if counts.added > 0 { Text(verbatim: "+\(counts.added)").foregroundStyle(DSColor.diffAdded) }
                        if counts.deleted > 0 { Text(verbatim: "−\(counts.deleted)").foregroundStyle(DSColor.diffRemoved) }
                    }.font(DSFont.monoCaption).fixedSize()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("editor-diff-counts")
                }
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
            if viewModel.canViewContent || viewModel.selectedPath == nil {
                Button {
                    if let path = viewModel.selectedPath { onEditFile(path) }
                } label: { Text("ファイルタブで編集", bundle: bundle) }
                .buttonStyle(.ds(.secondary, height: DSLayout.fileTreeInputHeight, fontSize: DSFont.monoCaptionSize, padding: DSSpacing.s))
                .accessibilityLabel(Text("ファイルタブで編集", bundle: bundle))
                .accessibilityIdentifier("editor-open-file")
                .disabled(viewModel.selectedPath == nil)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .frame(height: DSLayout.gitDiffHeaderHeight)
        .overlay(alignment: .bottom) { separator(horizontal: true) }
    }

    /// 11.5pt の等幅・行の高さ 1.7。左に幅 28 の行番号、追加・削除は行全体を塗って「+ 」「− 」を付ける。
    private func codeLines(_ lines: [EditorCodeLine], isDiff: Bool) -> some View {
        let shown = Array(lines.prefix(previewLineLimit))
        let path = viewModel.selectedPath ?? ""
        let bodies = viewModel.shouldHighlightPreview(isDiff: isDiff)
            ? EditorCodeLines.highlightedBodies(shown) { ChatCodeHighlighter.highlightLines($0, path: path) }
            : shown.map { AttributedString($0.text) }
        let rest = EditorCodeLines.remainder(of: lines, after: previewLineLimit)
        return GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                        codeLine(line, body: bodies[index], isDiff: isDiff)
                            .frame(minWidth: viewport.size.width, alignment: .leading)
                            .background(lineTint(line.kind))
                            .accessibilityIdentifier("editor-code-line-\(index)")
                    }
                    if rest.lines > 0 {
                        Button(moreLabel(rest, isDiff: isDiff)) {
                            previewLineLimit += 500
                        }
                        .buttonStyle(.plain)
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.leading, DSLayout.gitLineNumberWidth + DSSpacing.m)
                        .padding(.top, DSSpacing.xs)
                    }
                }
                .padding(.vertical, DSSpacing.chip)
                .frame(minHeight: viewport.size.height, alignment: .topLeading)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .focusable().focused($detailFocused).focusEffectDisabled()
            .accessibilityLabel(Text(isDiff ? "差分" : "内容", bundle: bundle))
            .accessibilityIdentifier("editor-diff-scroll")
        }
    }

    private func moreLabel(_ rest: (hunks: Int, lines: Int), isDiff: Bool) -> String {
        if isDiff {
            return String(format: AppLocalizedString.string("さらに表示（残り %lld 塊 · %lld 行）", locale: locale, bundle: bundle), rest.hunks, rest.lines)
        }
        return String(format: AppLocalizedString.string("さらに表示（残り %lld 行）", locale: locale, bundle: bundle), rest.lines)
    }

    private func codeLine(_ line: EditorCodeLine, body: AttributedString, isDiff: Bool) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: line.number.map(String.init) ?? "")
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: DSLayout.gitLineNumberWidth, alignment: .trailing)
                .padding(.trailing, DSSpacing.m)
            Text(lineText(line, body: body, isDiff: isDiff))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize()
                .textSelection(.enabled)
        }
        // 読み上げは「行番号 記号 本文」を 1 つにまとめる（+ / − で追加・削除が分かる）。
        .accessibilityElement(children: .combine)
        .font(DSFont.monoCaption)
        .padding(.leading, DSSpacing.m)
        .padding(.trailing, DSSpacing.m)
        .frame(minHeight: DSLayout.gitDiffLineHeight)
    }

    /// 本文は拡張子に合わせて色分けし、差分は先頭に色つきの「+ 」「− 」を付ける。
    private func lineText(_ line: EditorCodeLine, body: AttributedString, isDiff: Bool) -> AttributedString {
        guard isDiff else { return body }
        var marker: AttributedString
        switch line.kind {
        case .added:
            marker = AttributedString("+ ")
            marker.foregroundColor = DSColor.diffAdded
        case .removed:
            marker = AttributedString("− ")
            marker.foregroundColor = DSColor.diffRemoved
        case .context:
            marker = AttributedString("  ")
        case .hunk:
            var text = AttributedString(line.text)
            text.foregroundColor = DSColor.textTertiary
            return text
        }
        return marker + body
    }

    private func lineTint(_ kind: EditorCodeLine.Kind) -> Color {
        switch kind {
        case .added: DSColor.diffAddedTint
        case .removed: DSColor.diffRemovedTint
        case .context, .hunk: .clear
        }
    }
}
