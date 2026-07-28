import SwiftUI
import AgentConfigKit
import DesignSystem

/// `codex mcp ...` で MCP サーバーを管理する。
///
/// 実体は `config.toml` の `[mcp_servers.*]` だが、追加・削除は CLI に任せる
/// （引数の引用やテーブルの組み立てを Phlox が真似ると壊しやすいため）。
struct CodexMCPPane: View {
    @Bindable var model: CodexConsoleModel

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
            subtitle: "Codex が使う MCP サーバー。追加・削除は codex mcp コマンドが行います。",
            toolbar: AnyView(toolbar),
            controls: AnyView(editor)
        ) {
            if !model.isAvailable {
                AgentConsoleUnavailableNotice(commandName: "codex")
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    AgentConsoleGroupHeader(
                        title: "登録済みサーバー",
                        systemImage: "server.rack",
                        detail: "\(model.mcpServers.count) 件"
                    )
                    if model.mcpServers.isEmpty {
                        AgentConsoleEmptyState(
                            symbolName: "server.rack",
                            message: model.isLoadingMCP ? "読み込み中…" : "登録はありません。"
                        )
                    }
                    ForEach(model.mcpServers) { server in
                        row(server)
                    }
                }
                .agentConsoleScrollBody()
                .task { await model.loadMCPServers() }
            }
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
            } else if model.isLoadingMCP {
                ProgressView().controlSize(.small)
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                Task { await model.loadMCPServers() }
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
        .disabled(model.runningOperation != nil || !model.isAvailable)
    }

    private func row(_ server: CodexMCPServer) -> some View {
        AgentConsoleCard(isHighlighted: server.isEnabled) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: "server.rack")
                    .font(.system(size: DSIconSize.l, weight: .semibold))
                    .foregroundStyle(server.isEnabled ? DSColor.statusCompleted : DSColor.textTertiary)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(server.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    if let endpoint = server.endpoint {
                        Text(endpoint)
                            .font(DSFont.monoCaption)
                            .foregroundStyle(DSColor.textTertiary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: DSSpacing.xs) {
                        if let transportType = server.transportType {
                            AgentConsoleMetaChip(text: transportType)
                        }
                        if let authStatus = server.authStatus {
                            AgentConsoleMetaChip(text: authStatus, symbolName: "key")
                        }
                        if let reason = server.disabledReason {
                            AgentConsoleMetaChip(text: reason, tint: DSColor.statusError)
                        }
                    }
                }

                Spacer(minLength: DSSpacing.s)

                Button(role: .destructive) {
                    Task {
                        await model.performMCPOperation("\(server.name) を削除") {
                            try await $0.remove(name: server.name)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: DSIconSize.m, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help("このサーバーを削除")
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
        let transport = draftTransport
        draftName = ""
        draftEndpoint = ""
        Task {
            await model.performMCPOperation("\(name) を追加") { service in
                switch transport {
                case .stdio:
                    let parts = endpoint.split(separator: " ", omittingEmptySubsequences: true)
                        .map(String.init)
                    try await service.addStdioServer(name: name, command: parts)
                case .http:
                    try await service.addHTTPServer(name: name, url: endpoint)
                }
            }
        }
    }
}
