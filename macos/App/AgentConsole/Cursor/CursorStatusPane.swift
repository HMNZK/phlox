import SwiftUI
import AppKit
import AgentConfigKit
import DesignSystem

/// いまの Cursor Agent の構成をまとめて見せる。
struct CursorStatusPane: View {
    @Bindable var model: CursorConsoleModel

    var body: some View {
        AgentConsolePane(
            title: "状態",
            subtitle: "いまの Cursor Agent の構成。値の実体は ~/.cursor/cli-config.json です。",
            toolbar: AnyView(toolbar)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                summaryTiles
                AgentConsoleStatusSection(title: "CLI", systemImage: "terminal") {
                    AgentConsoleStatusRow(label: "バージョン", value: model.status.cursorVersion ?? "—")
                    AgentConsoleStatusRow(label: "実行ファイル", mono: model.status.cursorExecutablePath)
                }
                AgentConsoleStatusSection(title: "設定", systemImage: "gearshape") {
                    AgentConsoleStatusRow(
                        label: "cli-config.json",
                        mono: model.status.configFilePath,
                        note: model.status.configFileExists ? nil : "未作成"
                    )
                    AgentConsoleStatusRow(label: "mcp.json", mono: model.status.mcpFilePath)
                    AgentConsoleStatusRow(
                        label: "モデル",
                        value: model.status.modelDisplayName ?? model.status.modelID ?? "既定"
                    )
                    AgentConsoleStatusRow(label: "承認の求め方", value: model.status.approvalMode ?? "既定")
                    AgentConsoleStatusRow(label: "サンドボックス", value: model.status.sandboxMode ?? "既定")
                }
                // cli-config.json には認証情報も入っている。画面には出さないことを明記する。
                Label(
                    "認証情報とキャッシュは画面に出さず、書き込みでも触りません。",
                    systemImage: "lock"
                )
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
            }
            .agentConsoleScrollBody()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if model.isLoadingModels {
                ProgressView().controlSize(.small)
            }
            AgentConsoleIconButton(systemName: "folder", help: "cli-config.json を Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: model.status.configFilePath)]
                )
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                model.loadSettings()
                Task { await model.loadVersionAndModels() }
            }
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: DSSpacing.m) {
            AgentConsoleStatusTile(
                title: "許可ルール",
                value: "\(model.status.allowRuleCount)",
                detail: nil,
                systemImage: "checkmark.shield.fill",
                tint: DSColor.statusCompleted
            )
            AgentConsoleStatusTile(
                title: "拒否ルール",
                value: "\(model.status.denyRuleCount)",
                detail: nil,
                systemImage: "hand.raised.fill",
                tint: DSColor.statusError
            )
            AgentConsoleStatusTile(
                title: "MCP",
                value: "\(model.status.mcpServerCount)",
                detail: nil,
                systemImage: "server.rack",
                tint: DSColor.statusRunning
            )
            AgentConsoleStatusTile(
                title: "選べるモデル",
                value: "\(model.availableModels.count)",
                detail: model.availableModels.isEmpty ? "未取得" : nil,
                systemImage: "cpu",
                tint: DSColor.accent
            )
        }
    }
}
