import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/hooks` 相当。`settings.json` の `hooks` を一覧・追加・削除する。
struct ClaudeHooksPane: View {
    @Bindable var model: ClaudeConsoleModel

    @State private var draftEvent = ClaudeHookSettings.knownEvents.first ?? "PreToolUse"
    @State private var draftMatcher = ""
    @State private var draftCommand = ""
    @State private var draftTimeout = ""
    @State private var isAdding = false

    private var entries: [ClaudeHookEntry] {
        ClaudeHookSettings.entries(from: model.settings)
    }

    /// イベントごとにまとめて見せる（同じ event が連続で並ぶだけの一覧は読みにくい）。
    private var groups: [(event: String, entries: [ClaudeHookEntry])] {
        Dictionary(grouping: entries, by: \.event)
            .map { (event: $0.key, entries: $0.value) }
            .sorted { $0.event < $1.event }
    }

    var body: some View {
        AgentConsolePane(
            title: "フック",
            subtitle: "対話 TUI の /hooks に相当します。ツール実行の前後などに走らせるコマンドを管理します。",
            toolbar: AnyView(
                Button(isAdding ? "閉じる" : "追加") {
                    withAnimation(.easeInOut(duration: 0.15)) { isAdding.toggle() }
                }
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: !isAdding))
            ),
            controls: isAdding ? AnyView(editor) : nil
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                if entries.isEmpty {
                    AgentConsoleEmptyState(symbolName: "link", message: "登録されているフックはありません。")
                }
                ForEach(groups, id: \.event) { group in
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        AgentConsoleGroupHeader(
                            title: group.event,
                            systemImage: "bolt.horizontal",
                            detail: "\(group.entries.count) 件"
                        )
                        ForEach(group.entries) { entry in
                            hookCard(entry)
                        }
                    }
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private func hookCard(_ entry: ClaudeHookEntry) -> some View {
        AgentConsoleCard {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xs) {
                        ClaudeHookMetaChip(
                            text: entry.matcher ?? "すべてのツール",
                            symbolName: "line.3.horizontal.decrease"
                        )
                        if let timeout = entry.timeoutSeconds {
                            ClaudeHookMetaChip(text: "\(timeout)s", symbolName: "timer")
                        }
                    }
                    Text(entry.command)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DSSpacing.s)
                Button(role: .destructive) {
                    model.applySettings(
                        { ClaudeHookSettings.removing(entry, from: $0) },
                        successMessage: "\(entry.event) のフックを削除しました。"
                    )
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: DSIconSize.m, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help("このフックを削除")
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                Picker("", selection: $draftEvent) {
                    ForEach(ClaudeHookSettings.knownEvents, id: \.self) { event in
                        Text(event).tag(event)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                TextField("対象ツール（空ならすべて）", text: $draftMatcher)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                TextField("タイムアウト秒", text: $draftTimeout)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            HStack(spacing: DSSpacing.s) {
                TextField("実行するシェルコマンド", text: $draftCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(DSFont.monoCaption)
                    .onSubmit(addHook)
                Button("この内容で追加", action: addHook)
                    .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                    .disabled(draftCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DSSpacing.m)
        .background {
            RoundedRectangle(cornerRadius: AgentConsoleStyle.cardRadius, style: .continuous)
                .fill(DSColor.fillSubtle)
        }
    }

    private func addHook() {
        let event = draftEvent
        let matcher = draftMatcher
        let command = draftCommand
        let timeout = Int(draftTimeout.trimmingCharacters(in: .whitespaces))
        model.applySettings(
            {
                ClaudeHookSettings.adding(
                    event: event,
                    matcher: matcher,
                    command: command,
                    timeoutSeconds: timeout,
                    to: $0
                )
            },
            successMessage: "\(event) にフックを追加しました。"
        )
        draftMatcher = ""
        draftCommand = ""
        draftTimeout = ""
        isAdding = false
    }
}

private struct ClaudeHookMetaChip: View {
    let text: String
    let symbolName: String

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: symbolName)
                .font(.system(size: DSIconSize.s, weight: .semibold))
            Text(text)
                .font(DSFont.monoCaption)
        }
        .foregroundStyle(DSColor.textTertiary)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 1)
        .background(DSColor.fillSubtle, in: Capsule(style: .continuous))
    }
}
