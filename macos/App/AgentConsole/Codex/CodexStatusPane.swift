import SwiftUI
import AppKit
import AgentConfigKit
import DesignSystem

/// いまの Codex の構成をまとめて見せる。
struct CodexStatusPane: View {
    @Bindable var model: CodexConsoleModel

    var body: some View {
        AgentConsolePane(
            title: "状態",
            subtitle: "いまの Codex CLI の構成。値の実体は ~/.codex/config.toml です。",
            toolbar: AnyView(toolbar)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                summaryTiles
                AgentConsoleStatusSection(title: "CLI", systemImage: "terminal") {
                    AgentConsoleStatusRow(label: "バージョン", value: model.status.codexVersion ?? "—")
                    AgentConsoleStatusRow(label: "実行ファイル", mono: model.status.codexExecutablePath)
                }
                AgentConsoleStatusSection(title: "設定", systemImage: "gearshape") {
                    AgentConsoleStatusRow(
                        label: "config.toml",
                        mono: model.status.configFilePath,
                        note: model.status.configFileExists ? nil : "未作成"
                    )
                    AgentConsoleStatusRow(label: "モデル", value: model.status.model ?? "既定")
                    AgentConsoleStatusRow(label: "思考の深さ", value: model.status.reasoningEffort ?? "既定")
                    AgentConsoleStatusRow(label: "応答の人格", value: model.status.personality ?? "既定")
                    AgentConsoleStatusRow(label: "承認の求め方", value: model.status.approvalPolicy ?? "既定")
                    AgentConsoleStatusRow(label: "サンドボックス", value: model.status.sandboxMode ?? "既定")
                }
                AgentConsoleStatusSection(title: "メモリ", systemImage: "brain") {
                    ForEach(model.status.memoryFiles) { file in
                        AgentConsoleStatusRow(
                            label: file.displayPath,
                            value: file.exists ? "あり" : "未作成",
                            valueTint: file.exists ? DSColor.textSecondary : DSColor.textTertiary
                        )
                    }
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            AgentConsoleIconButton(systemName: "folder", help: "config.toml を Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: model.status.configFilePath)]
                )
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                model.loadConfig()
                Task {
                    await model.loadVersion()
                    await model.loadPlugins()
                    await model.loadMCPServers()
                }
            }
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: DSSpacing.m) {
            AgentConsoleStatusTile(
                title: "プラグイン",
                value: "\(model.status.installedPluginCount)",
                detail: "有効 \(model.status.enabledPluginCount)",
                systemImage: "puzzlepiece.extension.fill",
                tint: DSColor.accent
            )
            AgentConsoleStatusTile(
                title: "MCP",
                value: "\(model.status.mcpServerCount)",
                detail: "有効 \(model.status.enabledMCPServerCount)",
                systemImage: "server.rack",
                tint: DSColor.statusRunning
            )
            AgentConsoleStatusTile(
                title: "信頼済み",
                value: "\(model.status.trustedProjectCount)",
                detail: "全 \(model.status.projectCount)",
                systemImage: "folder.badge.person.crop",
                tint: DSColor.statusCompleted
            )
            AgentConsoleStatusTile(
                title: "マーケットプレイス",
                value: "\(model.status.marketplaceCount)",
                detail: nil,
                systemImage: "storefront.fill",
                tint: DSColor.statusAwaitingApproval
            )
        }
    }
}
