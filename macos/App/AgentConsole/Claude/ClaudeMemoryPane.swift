import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/memory` 相当。CLAUDE.md / AGENTS.md をその場で編集する。
struct ClaudeMemoryPane: View {
    @Bindable var model: ClaudeConsoleModel

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
            subtitle: "対話 TUI の /memory に相当します。Claude Code が毎回読み込む指示ファイルを編集します。",
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

            if let selectedFile, !selectedFile.exists {
                Text("未作成（保存すると新規作成します）")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    /// 等幅の素の編集面。行数が多い前提なので、カードで囲わず窓いっぱいに使う。
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
