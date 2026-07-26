import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/output-style` 相当。応答スタイルを選ぶ。
struct ClaudeOutputStylePane: View {
    @Bindable var model: ClaudeConsoleModel

    private var options: [ClaudeOutputStyleOption] {
        ClaudeOutputStyleSettings.availableOptions(paths: model.paths)
    }

    private var current: String? {
        ClaudeOutputStyleSettings.extract(from: model.settings)
    }

    var body: some View {
        AgentConsolePane(
            title: "出力スタイル",
            subtitle: "対話 TUI の /output-style に相当します。~/.claude/output-styles にファイルを置くと選択肢が増えます。"
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                ForEach(options) { option in
                    let isSelected = option.value == current
                    Button {
                        model.applySettings(
                            { ClaudeOutputStyleSettings.apply(option.value, to: $0) },
                            successMessage: "出力スタイルを「\(option.displayName)」にしました。"
                        )
                    } label: {
                        AgentConsoleCard(isHighlighted: isSelected) {
                            HStack(alignment: .top, spacing: DSSpacing.m) {
                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: DSIconSize.l))
                                    .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(DSFont.body.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(DSColor.textPrimary)
                                    Text(option.detail)
                                        .font(DSFont.caption)
                                        .foregroundStyle(DSColor.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .agentConsoleScrollBody()
        }
    }
}
