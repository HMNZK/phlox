import SwiftUI
import AgentConfigKit
import DesignSystem

/// `codex plugin ...` でプラグインとマーケットプレイスを管理する。
struct CodexPluginsPane: View {
    @Bindable var model: CodexConsoleModel

    @State private var searchText = ""
    @State private var showsAvailable = false
    @State private var showsMarketplaces = false
    @State private var marketplaceSource = ""

    var body: some View {
        AgentConsolePane(
            title: "プラグイン",
            subtitle: "Phlox が codex plugin コマンドを実行します。設定の書き込みは CLI に任せます。",
            toolbar: AnyView(toolbar),
            controls: AnyView(controls)
        ) {
            if !model.isAvailable {
                AgentConsoleUnavailableNotice(commandName: "codex")
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.l) {
                    if showsMarketplaces { marketplaceEditor }
                    if showsAvailable { availableList } else { installedList }
                }
                .agentConsoleScrollBody()
                .task { await model.loadPlugins() }
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
            } else if model.isLoadingPlugins {
                ProgressView().controlSize(.small)
            }

            AgentConsoleIconButton(
                systemName: showsMarketplaces ? "storefront.fill" : "storefront",
                help: "マーケットプレイス"
            ) {
                showsMarketplaces.toggle()
            }
            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                Task { await model.loadPlugins() }
            }
        }
        .disabled(model.runningOperation != nil)
    }

    private var controls: some View {
        HStack(spacing: DSSpacing.m) {
            Picker("", selection: $showsAvailable) {
                Text("インストール済み").tag(false)
                Text("追加できるもの").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            AgentConsoleSearchField(text: $searchText, maxWidth: 220)
            Spacer(minLength: 0)
        }
        .disabled(model.runningOperation != nil)
    }

    // MARK: - 一覧

    private var installedList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(
                title: "インストール済み",
                systemImage: "puzzlepiece.extension.fill",
                detail: countLabel(filteredInstalled.count, of: model.installedPlugins.count)
            )
            if filteredInstalled.isEmpty {
                AgentConsoleEmptyState(
                    symbolName: "puzzlepiece.extension",
                    message: model.isLoadingPlugins ? "読み込み中…" : "該当するプラグインはありません。"
                )
            }
            ForEach(filteredInstalled) { plugin in
                installedRow(plugin)
            }
        }
    }

    private var availableList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(
                title: "追加できるもの",
                systemImage: "square.and.arrow.down",
                detail: countLabel(filteredAvailable.count, of: model.availablePlugins.count)
            )
            if filteredAvailable.isEmpty {
                AgentConsoleEmptyState(
                    symbolName: "square.and.arrow.down",
                    message: model.isLoadingPlugins ? "読み込み中…" : "追加できるプラグインが見つかりません。"
                )
            }
            ForEach(filteredAvailable) { plugin in
                availableRow(plugin)
            }
        }
    }

    private func installedRow(_ plugin: CodexInstalledPlugin) -> some View {
        AgentConsoleCard(isHighlighted: plugin.isEnabled) {
            HStack(spacing: DSSpacing.m) {
                pluginIcon(isActive: plugin.isEnabled, symbolName: "puzzlepiece.extension.fill")
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(plugin.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    HStack(spacing: DSSpacing.xs) {
                        if let version = plugin.version {
                            AgentConsoleMetaChip(text: "v\(version)")
                        }
                        if let marketplace = plugin.marketplaceName {
                            AgentConsoleMetaChip(text: marketplace)
                        }
                        AgentConsoleMetaChip(text: plugin.isEnabled ? "有効" : "無効")
                    }
                }
                Spacer(minLength: DSSpacing.s)
                Button("削除") {
                    Task {
                        await model.performPluginOperation("\(plugin.name) を削除") {
                            try await $0.uninstall(pluginID: plugin.pluginID)
                        }
                    }
                }
                .buttonStyle(AgentConsoleActionButtonStyle())
            }
        }
        .disabled(model.runningOperation != nil)
    }

    private func availableRow(_ plugin: CodexAvailablePlugin) -> some View {
        AgentConsoleCard {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                pluginIcon(isActive: false, symbolName: "shippingbox")
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(plugin.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    if let marketplace = plugin.marketplaceName {
                        AgentConsoleMetaChip(text: marketplace)
                    }
                    if let description = plugin.description {
                        Text(description)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DSSpacing.s)
                Button("インストール") {
                    Task {
                        await model.performPluginOperation("\(plugin.name) をインストール") {
                            try await $0.install(pluginID: plugin.pluginID)
                        }
                    }
                }
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
            }
        }
        .disabled(model.runningOperation != nil)
    }

    private func pluginIcon(isActive: Bool, symbolName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .fill(isActive ? DSColor.accent.opacity(0.18) : DSColor.fillSubtle)
                .frame(width: 32, height: 32)
            Image(systemName: symbolName)
                .font(.system(size: DSIconSize.l, weight: .semibold))
                .foregroundStyle(isActive ? DSColor.accent : DSColor.textTertiary)
        }
    }

    // MARK: - マーケットプレイス

    private var marketplaceEditor: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(
                title: "マーケットプレイス",
                systemImage: "storefront.fill",
                detail: "\(model.marketplaces.count) 件"
            )

            ForEach(model.marketplaces) { marketplace in
                AgentConsoleCard {
                    HStack(spacing: DSSpacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(marketplace.name)
                                .font(DSFont.body)
                                .foregroundStyle(DSColor.textPrimary)
                            Text(marketplace.originDescription)
                                .font(DSFont.monoCaption)
                                .foregroundStyle(DSColor.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: DSSpacing.s)
                        Button("削除") {
                            Task {
                                await model.performPluginOperation("\(marketplace.name) を削除") {
                                    try await $0.removeMarketplace(name: marketplace.name)
                                }
                            }
                        }
                        .buttonStyle(AgentConsoleActionButtonStyle())
                    }
                }
            }

            AgentConsoleCard {
                HStack(spacing: DSSpacing.s) {
                    TextField("owner/repo またはローカルパス", text: $marketplaceSource)
                        .textFieldStyle(.roundedBorder)
                    Button("追加") {
                        let source = marketplaceSource
                        marketplaceSource = ""
                        Task {
                            await model.performPluginOperation("\(source) を追加") {
                                try await $0.addMarketplace(source: source)
                            }
                        }
                    }
                    .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                    .disabled(marketplaceSource.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("すべて更新") {
                        Task {
                            await model.performPluginOperation("マーケットプレイスを更新") {
                                try await $0.upgradeMarketplaces()
                            }
                        }
                    }
                    .buttonStyle(AgentConsoleActionButtonStyle())
                }
            }
        }
        .disabled(model.runningOperation != nil)
    }

    // MARK: - 絞り込み

    private func countLabel(_ shown: Int, of total: Int) -> String {
        shown == total ? "\(total) 件" : "\(shown) / \(total) 件"
    }

    private var filteredInstalled: [CodexInstalledPlugin] {
        guard !searchText.isEmpty else { return model.installedPlugins }
        return model.installedPlugins.filter { $0.pluginID.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAvailable: [CodexAvailablePlugin] {
        guard !searchText.isEmpty else { return model.availablePlugins }
        return model.availablePlugins.filter {
            $0.pluginID.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}
