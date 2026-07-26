import SwiftUI
import AgentConfigKit
import DesignSystem

/// `~/.cursor/mcp.json` の MCP サーバーを管理する。
///
/// `cursor-agent mcp list` は人間向けテキストしか出さないので、一覧は JSON を直接読む。
/// 有効・無効の切り替えだけ CLI に任せる（保存先が mcp.json ではないため）。
struct CursorMCPPane: View {
    @Bindable var model: CursorConsoleModel

    private enum Transport: String, CaseIterable, Identifiable {
        case stdio
        case http

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .stdio: return "コマンド"
            case .http: return "URL"
            }
        }

        var placeholder: String {
            switch self {
            case .stdio: return "npx -y @modelcontextprotocol/server-filesystem ~/Documents"
            case .http: return "https://example.com/mcp"
            }
        }
    }

    @State private var draftName = ""
    @State private var draftEndpoint = ""
    @State private var draftTransport: Transport = .stdio

    var body: some View {
        AgentConsolePane(
            title: "MCP",
            subtitle: "Cursor Agent が使う MCP サーバー。実体は ~/.cursor/mcp.json です。",
            toolbar: AnyView(toolbar),
            controls: AnyView(editor)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                AgentConsoleGroupHeader(
                    title: "登録済みサーバー",
                    systemImage: "server.rack",
                    detail: "\(model.mcpServers.count) 件"
                )
                if model.mcpServers.isEmpty {
                    AgentConsoleEmptyState(symbolName: "server.rack", message: "登録はありません。")
                }
                ForEach(model.mcpServers) { server in
                    row(server)
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if let operation = model.runningOperation {
                ProgressView().controlSize(.small)
                Text(operation)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                model.loadSettings()
            }
        }
        .disabled(model.runningOperation != nil)
    }

    private var editor: some View {
        HStack(spacing: DSSpacing.s) {
            Picker("", selection: $draftTransport) {
                ForEach(Transport.allCases) { transport in
                    Text(transport.displayName).tag(transport)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            TextField("名前", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            TextField(draftTransport.placeholder, text: $draftEndpoint)
                .textFieldStyle(.roundedBorder)
                .font(DSFont.monoCaption)
                .onSubmit(add)

            Button("追加", action: add)
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(!canAdd)
        }
        .disabled(model.runningOperation != nil)
    }

    private func row(_ server: CursorMCPServer) -> some View {
        AgentConsoleCard {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: "server.rack")
                    .font(.system(size: DSIconSize.l, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(server.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(server.endpoint)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textTertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    AgentConsoleMetaChip(text: server.transportType)
                }

                Spacer(minLength: DSSpacing.s)

                Menu {
                    Button("有効にする") {
                        Task { await model.setMCPEnabled(true, name: server.name) }
                    }
                    Button("無効にする") {
                        Task { await model.setMCPEnabled(false, name: server.name) }
                    }
                    Divider()
                    Button("削除", role: .destructive) {
                        model.applyMCP(
                            { CursorMCPServers.removing(name: server.name, from: $0) },
                            successMessage: "\(server.name) を削除しました。"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: DSIconSize.m, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .pointingHandCursor()
            }
        }
        .disabled(model.runningOperation != nil)
    }

    private var canAdd: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draftTransport {
        case .stdio:
            guard let parsed = CursorMCPServers.splitCommand(endpoint) else { return }
            model.applyMCP(
                {
                    CursorMCPServers.addingStdioServer(
                        name: name,
                        command: parsed.command,
                        arguments: parsed.arguments,
                        to: $0
                    )
                },
                successMessage: "\(name) を追加しました。"
            )
        case .http:
            model.applyMCP(
                { CursorMCPServers.addingHTTPServer(name: name, url: endpoint, to: $0) },
                successMessage: "\(name) を追加しました。"
            )
        }
        draftName = ""
        draftEndpoint = ""
    }
}
