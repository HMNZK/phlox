import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/plugin` 相当。`claude plugin ...`（非対話）でプラグインとマーケットプレイスを管理する。
struct ClaudePluginsPane: View {
    @Bindable var model: ClaudeConsoleModel

    @State private var searchText = ""
    @State private var showsAvailable = false
    @State private var installScope: ClaudePluginScope = .user
    @State private var marketplaceSource = ""
    @State private var showsMarketplaces = false

    var body: some View {
        AgentConsolePane(
            title: "プラグイン",
            subtitle: "対話 TUI の /plugin に相当します。Phlox が claude plugin コマンドを実行します。",
            toolbar: AnyView(toolbar),
            controls: AnyView(controls)
        ) {
            if !model.isClaudeAvailable {
                AgentConsoleUnavailableNotice(commandName: "claude")
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.l) {
                    if showsMarketplaces { marketplaceEditor }
                    if showsAvailable { availableList } else { installedList }
                }
                .agentConsoleScrollBody()
            }
        }
    }

    // MARK: - 見出し右（状態とアイコン操作だけ）

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

    // MARK: - 見出し下の操作帯

    private var controls: some View {
        HStack(spacing: DSSpacing.m) {
            Picker("", selection: $showsAvailable) {
                Text("インストール済み").tag(false)
                Text("追加できるもの").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DSIconSize.m))
                    .foregroundStyle(DSColor.textTertiary)
                TextField("絞り込み", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DSFont.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DSIconSize.m))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(DSColor.fillSubtle)
            }
            .frame(maxWidth: 220)

            if showsAvailable {
                Picker("", selection: $installScope) {
                    ForEach(ClaudePluginScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 132)
                .help("インストール先")
            }

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
                InstalledPluginRow(plugin: plugin, model: model)
            }
        }
    }

    private var availableList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(
                title: "追加できるもの",
                systemImage: "square.and.arrow.down",
                detail: countLabel(filteredAvailable.count, of: notInstalled.count)
            )
            if filteredAvailable.isEmpty {
                AgentConsoleEmptyState(
                    symbolName: "square.and.arrow.down",
                    message: model.isLoadingPlugins ? "読み込み中…" : "追加できるプラグインが見つかりません。"
                )
            }
            ForEach(filteredAvailable) { plugin in
                AvailablePluginRow(plugin: plugin, scope: installScope, model: model)
            }
        }
    }

    private func countLabel(_ shown: Int, of total: Int) -> String {
        shown == total ? "\(total) 件" : "\(shown) / \(total) 件"
    }

    private var installedIDs: Set<String> { Set(model.installedPlugins.map(\.pluginID)) }

    private var notInstalled: [ClaudeAvailablePlugin] {
        model.availablePlugins.filter { !installedIDs.contains($0.id) }
    }

    private var filteredInstalled: [ClaudeInstalledPlugin] {
        guard !searchText.isEmpty else { return model.installedPlugins }
        return model.installedPlugins.filter { $0.pluginID.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAvailable: [ClaudeAvailablePlugin] {
        guard !searchText.isEmpty else { return notInstalled }
        return notInstalled.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
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
                    TextField("owner/repo または URL", text: $marketplaceSource)
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
                                try await $0.updateMarketplaces()
                            }
                        }
                    }
                    .buttonStyle(AgentConsoleActionButtonStyle())
                }
            }
        }
        .disabled(model.runningOperation != nil)
    }
}

// MARK: - 行

private struct InstalledPluginRow: View {
    let plugin: ClaudeInstalledPlugin
    @Bindable var model: ClaudeConsoleModel

    var body: some View {
        AgentConsoleCard(isHighlighted: plugin.isEnabled) {
            HStack(alignment: .center, spacing: DSSpacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(plugin.isEnabled ? DSColor.accent.opacity(0.18) : DSColor.fillSubtle)
                        .frame(width: 32, height: 32)
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: DSIconSize.l, weight: .semibold))
                        .foregroundStyle(plugin.isEnabled ? DSColor.accent : DSColor.textTertiary)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(plugin.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    HStack(spacing: DSSpacing.xs) {
                        if let scope = plugin.scope {
                            ClaudePluginScopeChip(scope: scope)
                        }
                        if let version = plugin.version {
                            AgentConsoleMetaChip(text: "v\(version)")
                        }
                        if let marketplace = plugin.marketplace {
                            AgentConsoleMetaChip(text: marketplace)
                        }
                        if !plugin.mcpServerNames.isEmpty {
                            AgentConsoleMetaChip(
                                text: "MCP: \(plugin.mcpServerNames.joined(separator: ", "))",
                                symbolName: "server.rack"
                            )
                        }
                    }
                }

                Spacer(minLength: DSSpacing.s)

                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { newValue in
                        Task {
                            await model.performPluginOperation(newValue ? "\(plugin.name) を有効に" : "\(plugin.name) を無効に") {
                                try await $0.setEnabled(newValue, pluginID: plugin.pluginID, scope: model.scope(for: plugin))
                            }
                        }
                    }
                ))
                .labelsHidden()
                .fixedSize()

                Menu {
                    Button("更新") {
                        Task {
                            await model.performPluginOperation("\(plugin.name) を更新") {
                                try await $0.update(pluginID: plugin.pluginID, scope: model.scope(for: plugin) ?? .user)
                            }
                        }
                    }
                    Button("アンインストール", role: .destructive) {
                        Task {
                            await model.performPluginOperation("\(plugin.name) をアンインストール") {
                                try await $0.uninstall(pluginID: plugin.pluginID, scope: model.scope(for: plugin) ?? .user)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: DSIconSize.m, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .pointingHandCursor()
            }
        }
        .disabled(model.runningOperation != nil)
    }
}

private struct AvailablePluginRow: View {
    let plugin: ClaudeAvailablePlugin
    let scope: ClaudePluginScope
    @Bindable var model: ClaudeConsoleModel

    var body: some View {
        AgentConsoleCard {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(DSColor.fillSubtle)
                        .frame(width: 32, height: 32)
                    Image(systemName: "shippingbox")
                        .font(.system(size: DSIconSize.l, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(plugin.name)
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    if let marketplaceName = plugin.marketplaceName {
                        AgentConsoleMetaChip(text: marketplaceName)
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
                            try await $0.install(pluginID: plugin.id, scope: scope)
                        }
                    }
                }
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
            }
        }
        .disabled(model.runningOperation != nil)
    }
}

/// user / project を色で見分けるチップ。
private struct ClaudePluginScopeChip: View {
    let scope: String

    var body: some View {
        let tint = scope == "project" ? DSColor.statusRunning : DSColor.textSecondary
        Text(scope)
            .font(DSFont.monoCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, 1)
            .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}

