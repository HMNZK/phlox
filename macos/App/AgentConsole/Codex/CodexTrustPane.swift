import SwiftUI
import AgentConfigKit
import DesignSystem

/// `config.toml` の `[projects."<path>"]` を一覧して信頼を切り替える。
///
/// 数百件になるので、絞り込みと「信頼済みだけ」表示を用意する。
struct CodexTrustPane: View {
    @Bindable var model: CodexConsoleModel

    @State private var searchText = ""
    @State private var showsTrustedOnly = false

    private var filtered: [CodexProjectTrust] {
        model.projects.filter { entry in
            if showsTrustedOnly, !entry.isTrusted { return false }
            guard !searchText.isEmpty else { return true }
            return entry.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        AgentConsolePane(
            title: "信頼設定",
            subtitle: "Codex が「このディレクトリを信頼するか」を覚えている一覧です。削除すると次回また確認されます。",
            controls: AnyView(controls)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                AgentConsoleGroupHeader(
                    title: "登録済みディレクトリ",
                    systemImage: "folder.badge.person.crop",
                    detail: countLabel
                )
                if filtered.isEmpty {
                    AgentConsoleEmptyState(
                        symbolName: "folder",
                        message: model.projects.isEmpty ? "登録はありません。" : "該当するディレクトリはありません。"
                    )
                }
                ForEach(filtered) { entry in
                    row(entry)
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var countLabel: String {
        filtered.count == model.projects.count
            ? "\(model.projects.count) 件"
            : "\(filtered.count) / \(model.projects.count) 件"
    }

    private var controls: some View {
        HStack(spacing: DSSpacing.m) {
            AgentConsoleSearchField(text: $searchText, placeholder: "パスで絞り込み")
            Toggle("信頼済みだけ", isOn: $showsTrustedOnly)
                .font(DSFont.caption)
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private func row(_ entry: CodexProjectTrust) -> some View {
        AgentConsoleCard(isHighlighted: entry.isTrusted) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: entry.isTrusted ? "checkmark.seal.fill" : "questionmark.circle")
                    .font(.system(size: DSIconSize.l))
                    .foregroundStyle(entry.isTrusted ? DSColor.statusCompleted : DSColor.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayPath(homeDirectory: model.paths.homeDirectory))
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.trustLevel ?? "未設定")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }

                Spacer(minLength: DSSpacing.s)

                Toggle("", isOn: Binding(
                    get: { entry.isTrusted },
                    set: { newValue in
                        model.applyConfig(
                            { CodexProjectTrustSettings.setTrusted(newValue, path: entry.path, in: &$0) },
                            successMessage: newValue
                                ? "\(entry.path) を信頼しました。"
                                : "\(entry.path) の信頼を外しました。"
                        )
                    }
                ))
                .labelsHidden()
                .fixedSize()

                Button(role: .destructive) {
                    model.applyConfig(
                        { CodexProjectTrustSettings.remove(path: entry.path, in: &$0) },
                        successMessage: "\(entry.path) の登録を削除しました。"
                    )
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: DSIconSize.m, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help("この登録を削除")
            }
        }
    }
}
