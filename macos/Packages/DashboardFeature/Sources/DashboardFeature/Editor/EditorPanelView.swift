import SessionFeature
import SwiftUI

/// 変更ファイルの確認と保存を行う、容器に依存しないエディタパネル。
public struct EditorPanelView: View {
    @Bindable private var viewModel: EditorPanelViewModel
    @State private var showsConflictAlert = false
    @State private var previewLineLimit = 500

    public init(viewModel: EditorPanelViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            changeList
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)

            detailPane
                .frame(minWidth: 360)
        }
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

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Changes")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
            }

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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.changes, id: \.path) { change in
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
                                        viewModel.selectedPath == change.path ? Color.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding()
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
