import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/statusline` 相当。ステータス行を描く外部コマンドを設定する。
struct ClaudeStatusLinePane: View {
    @Bindable var model: ClaudeConsoleModel

    @State private var isEnabled = false
    @State private var command = ""
    @State private var padding = ""
    @State private var didLoad = false

    private var isDirty: Bool {
        let saved = ClaudeStatusLineSettings.extract(from: model.settings)
        return saved.isEnabled != isEnabled
            || saved.command != command
            || (saved.padding.map(String.init) ?? "") != padding
    }

    var body: some View {
        AgentConsolePane(
            title: "ステータスライン",
            subtitle: "対話 TUI の /statusline に相当します。指定したコマンドの出力がステータス行になります。",
            toolbar: AnyView(toolbar)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                AgentConsoleGroup {
                    VStack(alignment: .leading, spacing: DSSpacing.l) {
                        Toggle("ステータスラインを使う", isOn: $isEnabled)
                            .font(DSFont.body)

                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text("コマンド")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                            TextField("", text: $command, prompt: Text("例: ~/.claude/statusline.sh"))
                                .textFieldStyle(.roundedBorder)
                                .font(DSFont.monoCaption)
                                .disabled(!isEnabled)
                        }

                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text("余白（省略可）")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                            TextField("", text: $padding, prompt: Text("0"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                                .disabled(!isEnabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.l)
                }

                Label(
                    "コマンドは標準入力でセッション情報（JSON）を受け取り、標準出力の1行がそのまま表示されます。",
                    systemImage: "info.circle"
                )
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
            }
            .agentConsoleScrollBody()
            .onAppear { load(force: false) }
        }
    }

    /// 操作系は他のペインに合わせて見出し右側へ置く。
    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if isDirty {
                Text("未保存")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusAwaitingApproval)
            }
            Button("元に戻す") { load(force: true) }
                .buttonStyle(AgentConsoleActionButtonStyle())
                .disabled(!isDirty)
            Button("保存", action: save)
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(!isDirty || (isEnabled && command.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    private func load(force: Bool) {
        guard force || !didLoad else { return }
        let settings = ClaudeStatusLineSettings.extract(from: model.settings)
        isEnabled = settings.isEnabled
        command = settings.command
        padding = settings.padding.map(String.init) ?? ""
        didLoad = true
    }

    private func save() {
        let next = ClaudeStatusLineSettings(
            isEnabled: isEnabled,
            command: command,
            padding: Int(padding.trimmingCharacters(in: .whitespaces))
        )
        model.applySettings(
            next.apply(to:),
            successMessage: isEnabled ? "ステータスラインを設定しました。" : "ステータスラインを無効にしました。"
        )
    }
}
