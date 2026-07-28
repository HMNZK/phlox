import SwiftUI
import AgentConfigKit
import DesignSystem

/// `config.toml` のトップレベル設定を編集する。
///
/// 変更は選んだ瞬間に1行だけ書き換わる（`TOMLDocument` の外科的編集）。
/// 書き込み前の内容は `config.toml.phlox-backup` に残る。
struct CodexSettingsPane: View {
    @Bindable var model: CodexConsoleModel

    /// モデル名だけは自由入力なので、確定するまでの下書きを持つ。
    @State private var modelDraft = ""
    @State private var loadedModelValue: String?

    var body: some View {
        AgentConsolePane(
            title: "設定",
            subtitle: "~/.codex/config.toml のよく変える項目。変更した行だけを書き換え、他の記述はそのまま残します。"
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                ForEach(CodexGeneralSettings.editableKeys) { key in
                    settingRow(key)
                }

                Label(
                    "書き込み前の内容は \(model.backupPath) に控えます。",
                    systemImage: "info.circle"
                )
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
            }
            .agentConsoleScrollBody()
            .onAppear(perform: syncModelDraft)
            .onChange(of: model.status.model) { _, _ in syncModelDraft() }
        }
    }

    @ViewBuilder
    private func settingRow(_ key: CodexSettingKey) -> some View {
        let current = CodexGeneralSettings.value(key, in: model.config)
        AgentConsoleGroup {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.displayName)
                            .font(DSFont.body.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(key.explanation)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DSSpacing.m)
                    Text(key.rawValue)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textTertiary)
                }

                if key.isEnumerated {
                    choiceControl(key, current: current)
                } else {
                    modelControl(current: current)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.l)
        }
    }

    /// 選択肢のあるキー。「既定」を選ぶとキーごと消える。
    private func choiceControl(_ key: CodexSettingKey, current: String?) -> some View {
        Picker("", selection: Binding(
            get: { current ?? "" },
            set: { newValue in
                guard newValue != (current ?? "") else { return }
                model.applyConfig(
                    { CodexGeneralSettings.setValue(newValue, for: key, in: &$0) },
                    successMessage: newValue.isEmpty
                        ? "\(key.displayName)を既定へ戻しました。"
                        : "\(key.displayName)を「\(newValue)」にしました。"
                )
            }
        )) {
            Text("既定（未設定）").tag("")
            ForEach(key.options(current: current), id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 280, alignment: .leading)
    }

    /// モデル名は自由入力。空にすると設定ごと消える。
    private func modelControl(current: String?) -> some View {
        HStack(spacing: DSSpacing.s) {
            TextField("例: gpt-5.6-sol", text: $modelDraft)
                .textFieldStyle(.roundedBorder)
                .font(DSFont.monoCaption)
                .frame(maxWidth: 320)
                .onSubmit { commitModel(current: current) }
            Button("適用") { commitModel(current: current) }
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(modelDraft == (current ?? ""))
        }
    }

    private func commitModel(current: String?) {
        let next = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != (current ?? "") else { return }
        model.applyConfig(
            { CodexGeneralSettings.setValue(next, for: .model, in: &$0) },
            successMessage: next.isEmpty ? "モデルを既定へ戻しました。" : "モデルを「\(next)」にしました。"
        )
    }

    private func syncModelDraft() {
        let current = CodexGeneralSettings.value(.model, in: model.config) ?? ""
        guard loadedModelValue != current else { return }
        modelDraft = current
        loadedModelValue = current
    }
}
