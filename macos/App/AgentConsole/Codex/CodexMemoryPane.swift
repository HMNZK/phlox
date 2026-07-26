import SwiftUI
import AgentConfigKit
import DesignSystem

/// Codex が毎回読み込む AGENTS.md をその場で編集する。
struct CodexMemoryPane: View {
    @Bindable var model: CodexConsoleModel

    @State private var selectedFileID: String?
    @State private var draft = ""
    @State private var loadedFileID: String?

    private var selectedFile: AgentMemoryFile? {
        model.memoryFiles.first { $0.id == selectedFileID } ?? model.memoryFiles.first
    }

    private var isDirty: Bool {
        guard let selectedFile else { return false }
        return draft != model.readMemory(selectedFile)
    }

    var body: some View {
        AgentConsolePane(
            title: "メモリ",
            subtitle: "Codex が毎回読み込む指示ファイル（AGENTS.md）を編集します。",
            toolbar: AnyView(toolbar),
            controls: AnyView(filePicker)
        ) {
            editor
                .onAppear(perform: loadSelectedFileIfNeeded)
                .onChange(of: selectedFileID) { _, _ in
                    loadedFileID = nil
                    loadSelectedFileIfNeeded()
                }
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if isDirty {
                Text("未保存")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusAwaitingApproval)
            }
            Button("元に戻す") {
                loadedFileID = nil
                loadSelectedFileIfNeeded()
            }
            .buttonStyle(AgentConsoleActionButtonStyle())
            .disabled(!isDirty)

            Button("保存") {
                guard let selectedFile else { return }
                model.writeMemory(draft, to: selectedFile)
            }
            .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
            .keyboardShortcut("s", modifiers: .command)
            .disabled(selectedFile == nil || !isDirty)
        }
    }

    private var filePicker: some View {
        HStack(spacing: DSSpacing.s) {
            Picker("", selection: Binding(
                get: { selectedFile?.id ?? "" },
                set: { selectedFileID = $0 }
            )) {
                ForEach(model.memoryFiles) { file in
                    Text("\(file.scope.displayName): \(file.displayPath)").tag(file.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 380, alignment: .leading)

            if let selectedFile {
                if let target = model.symlinkTarget(of: selectedFile) {
                    // 実体が別ファイル（例: ~/.claude/AGENTS.md）なら、
                    // どこへ書くのかを先に見せる。
                    Label("実体は \(target)", systemImage: "arrow.turn.down.right")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if !selectedFile.exists {
                    Text("未作成（保存すると新規作成します）")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var editor: some View {
        TextEditor(text: $draft)
            .font(DSFont.mono)
            .scrollContentBackground(.hidden)
            .background(DSColor.background)
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
    }

    private func loadSelectedFileIfNeeded() {
        guard let selectedFile, loadedFileID != selectedFile.id else { return }
        draft = model.readMemory(selectedFile)
        loadedFileID = selectedFile.id
    }
}
