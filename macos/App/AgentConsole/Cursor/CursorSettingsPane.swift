import SwiftUI
import AgentConfigKit
import DesignSystem

/// `cli-config.json` のうち、意味の分かる設定項目だけを編集する。
///
/// 認証情報（`authInfo`）やキャッシュは画面に出さない。書き込みは部分更新なので、
/// ここで扱わないキーはそのまま残る。
struct CursorSettingsPane: View {
    @Bindable var model: CursorConsoleModel

    var body: some View {
        AgentConsolePane(
            title: "設定",
            subtitle: "~/.cursor/cli-config.json のよく変える項目。触っていないキーはそのまま残します。"
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                ForEach(CursorSettingKey.Group.allCases) { group in
                    groupSection(group)
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private func groupSection(_ group: CursorSettingKey.Group) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(title: group.displayName, systemImage: group.symbolName)
            VStack(spacing: 2) {
                ForEach(CursorGeneralSettings.keys(in: group)) { key in
                    settingRow(key)
                }
            }
        }
    }

    @ViewBuilder
    private func settingRow(_ key: CursorSettingKey) -> some View {
        AgentConsoleCard {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    if let explanation = key.explanation {
                        Text(explanation)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DSSpacing.m)
                control(key)
            }
        }
    }

    @ViewBuilder
    private func control(_ key: CursorSettingKey) -> some View {
        switch key.kind {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { CursorGeneralSettings.bool(key, in: model.settings) ?? false },
                set: { newValue in
                    model.applySettings(
                        { CursorGeneralSettings.setBool(newValue, for: key, in: $0) },
                        successMessage: "\(key.displayName)を\(newValue ? "オン" : "オフ")にしました。"
                    )
                }
            ))
            .labelsHidden()
            .fixedSize()

        case .choice:
            let current = CursorGeneralSettings.string(key, in: model.settings)
            Picker("", selection: Binding(
                get: { current ?? "" },
                set: { newValue in
                    guard !newValue.isEmpty, newValue != current else { return }
                    model.applySettings(
                        { CursorGeneralSettings.setString(newValue, for: key, in: $0) },
                        successMessage: "\(key.displayName)を「\(newValue)」にしました。"
                    )
                }
            )) {
                if current == nil {
                    Text("既定（未設定）").tag("")
                }
                ForEach(key.options(current: current), id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }
}
