import SwiftUI
import AppKit
import AgentConfigKit
import DesignSystem

/// `/status` 相当。いまの Claude Code の構成をまとめて見せる。
struct ClaudeStatusPane: View {
    @Bindable var model: ClaudeConsoleModel

    var body: some View {
        AgentConsolePane(
            title: "状態",
            subtitle: "いまの Claude Code の構成。対話 TUI の /status に相当します。",
            toolbar: AnyView(toolbar)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                summaryTiles
                AgentConsoleStatusSection(title: "CLI", systemImage: "terminal") {
                    AgentConsoleStatusRow(label: "バージョン", value: model.status.claudeVersion ?? "—")
                    AgentConsoleStatusRow(label: "実行ファイル", mono: model.status.claudeExecutablePath)
                }
                AgentConsoleStatusSection(title: "設定", systemImage: "gearshape") {
                    AgentConsoleStatusRow(
                        label: "settings.json",
                        mono: model.status.settingsFilePath,
                        note: model.status.settingsFileExists ? nil : "未作成"
                    )
                    AgentConsoleStatusRow(label: "モデル", value: model.status.model ?? "既定")
                    AgentConsoleStatusRow(label: "思考の深さ", value: model.status.effortLevel ?? "既定")
                    AgentConsoleStatusRow(label: "出力スタイル", value: model.status.outputStyle ?? "既定")
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
            AgentConsoleIconButton(systemName: "folder", help: "設定ファイルを Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: model.status.settingsFilePath)]
                )
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                model.loadSettings()
                Task {
                    await model.loadVersion()
                    await model.loadPlugins()
                }
            }
        }
    }

    /// 数だけの情報は行で並べるより、タイルで一目に見せる。
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
                title: "マーケットプレイス",
                value: "\(model.status.marketplaceCount)",
                detail: nil,
                systemImage: "storefront.fill",
                tint: DSColor.statusRunning
            )
            AgentConsoleStatusTile(
                title: "権限ルール",
                value: "\(model.status.permissionRuleCount)",
                detail: nil,
                systemImage: "checkmark.shield.fill",
                tint: DSColor.statusCompleted
            )
            AgentConsoleStatusTile(
                title: "フック",
                value: "\(model.status.hookCount)",
                detail: nil,
                systemImage: "link",
                tint: DSColor.statusAwaitingApproval
            )
        }
    }
}
