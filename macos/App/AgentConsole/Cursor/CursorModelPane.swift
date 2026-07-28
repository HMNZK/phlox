import SwiftUI
import AgentConfigKit
import DesignSystem

/// 既定モデルを選ぶ。一覧は `cursor-agent models` から取る。
struct CursorModelPane: View {
    @Bindable var model: CursorConsoleModel

    private var currentModelID: String? {
        CursorModelSettings.currentModelID(in: model.settings)
    }

    var body: some View {
        AgentConsolePane(
            title: "モデル",
            subtitle: "Cursor Agent が既定で使うモデル。cli-config.json の model と selectedModel を揃えて書きます。",
            toolbar: AnyView(toolbar)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                AgentConsoleGroupHeader(
                    title: "選べるモデル",
                    systemImage: "cpu",
                    detail: "\(model.availableModels.count) 件"
                )
                if model.availableModels.isEmpty {
                    AgentConsoleEmptyState(
                        symbolName: "cpu",
                        message: model.isLoadingModels
                            ? "読み込み中…"
                            : "一覧を取得できませんでした。cursor-agent へのログインを確認してください。"
                    )
                }
                ForEach(model.availableModels) { option in
                    row(option)
                }

                if let currentModelID,
                   !model.availableModels.contains(where: { $0.modelID == currentModelID }) {
                    // 一覧に無いモデルが設定されている場合、勝手に上書きせず現状を見せる。
                    AgentConsoleGroupHeader(title: "いま設定されているモデル", systemImage: "questionmark.circle")
                    AgentConsoleCard(isHighlighted: true) {
                        HStack(spacing: DSSpacing.m) {
                            Text(currentModelID)
                                .font(DSFont.monoCaption)
                                .foregroundStyle(DSColor.textPrimary)
                                .textSelection(.enabled)
                            AgentConsoleMetaChip(text: "一覧にありません")
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if model.isLoadingModels {
                ProgressView().controlSize(.small)
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "一覧を取り直す") {
                Task { await model.loadVersionAndModels() }
            }
        }
    }

    private func row(_ option: CursorModelOption) -> some View {
        let isSelected = option.modelID == currentModelID
        return AgentConsoleCard(isHighlighted: isSelected) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DSIconSize.l))
                    .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(DSFont.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(option.modelID)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textTertiary)
                }

                Spacer(minLength: DSSpacing.s)

                if !isSelected {
                    Button("既定にする") {
                        model.applySettings(
                            { CursorModelSettings.apply(option, to: $0) },
                            successMessage: "既定モデルを「\(option.displayName)」にしました。"
                        )
                    }
                    .buttonStyle(AgentConsoleActionButtonStyle())
                }
            }
        }
    }
}
