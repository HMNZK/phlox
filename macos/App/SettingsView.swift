import SwiftUI
import AppKit
import AgentDomain
import DashboardFeature
import DesignSystem
import MobileProxy
import SessionFeature

struct SettingsView: View {
    @ObservedObject var appUpdater: AppUpdater
    let agentCatalog: AgentCatalog
    let hookDispatcherPath: String?
    /// モバイル端末の QR ペアリング・一覧・失効 VM。初期化前（composition 未完了）は nil。
    let mobileToken: MobileTokenViewModel?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    @AppStorage(NotificationSettings.bannerKey) private var bannerNotificationEnabled = true
    @AppStorage(NotificationSettings.soundKey) private var completionSoundEnabled = true

    @AppStorage(UsageSettings.autoRefreshKey) private var usageAutoRefresh = true
    @AppStorage(UsageSettings.claudeScrapeKey) private var claudeScrape = true
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailableUsage = false
    @AppStorage(UsageSettings.showInHeaderKey) private var showUsageInHeader = true

    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    @AppStorage(AppIconStore.iconKey) private var appIconID = AppIconStore.defaultOption.id

    @AppStorage(LanguageSettings.languageKey) private var appLanguageRaw = AppLanguage.system.rawValue

    @AppStorage(DefaultSessionBackendPreference.storageKey)
    private var defaultSessionBackendRaw = DefaultSessionBackendPreference.chat.rawValue

    @AppStorage(AgoraDiscussionSettings.maxUtterancesKey)
    private var agoraMaxUtterances = 30

    @AppStorage(AgoraDiscussionSettings.maxAgentsKey)
    private var agoraMaxAgents = 5

    @AppStorage(AgoraDiscussionSettings.turnTimeoutSecondsKey)
    private var agoraTurnTimeoutSeconds = 180

    @AppStorage(AgoraDiscussionSettings.schedulerKey)
    private var agoraSchedulerRaw = AgoraSchedulerKind.freeSpeech.rawValue

    @State private var selectedGroupID = "general"

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    private var defaultSessionBackendBinding: Binding<DefaultSessionBackendPreference> {
        Binding(
            get: { DefaultSessionBackendPreference(rawValue: defaultSessionBackendRaw) ?? .chat },
            set: { defaultSessionBackendRaw = $0.rawValue }
        )
    }

    private var agoraSchedulerBinding: Binding<AgoraSchedulerKind> {
        Binding(
            get: { AgoraSchedulerKind(rawValue: agoraSchedulerRaw) ?? .freeSpeech },
            set: { agoraSchedulerRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.l)
                .padding(.bottom, DSSpacing.s)

            TabView(selection: $selectedGroupID) {
                ForEach(SettingsGroup.all) { group in
                    groupForm(group)
                        .tabItem {
                            Label(group.title, systemImage: group.systemImage)
                        }
                        .tag(group.id)
                        .accessibilityIdentifier("settings-group-\(group.id)")
                }
            }
        }
        .frame(width: 520, height: 640)
        .background(DSColor.background)
        .preferredColorScheme(ThemeStore.active.preferredColorScheme)
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: DSSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.l)
                    .fill(DSColor.newSessionGradient)
                    .frame(width: 40, height: 40)
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(AppFlavor.current.displayName)
                    .font(DSFont.title)
                    .foregroundStyle(DSColor.textPrimary)
                Text("設定")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func groupForm(_ group: SettingsGroup) -> some View {
        Form {
            switch group.id {
            case "general":
                generalForm
            case "appearance":
                appearanceForm
            case "agents":
                agentsForm
            case "connection":
                if let mobileToken, MobileConnectionGuidePolicy.showsSettingsConnectionSection {
                    MobileTokenSection(viewModel: mobileToken)
                }
            case "advanced":
                advancedForm
            default:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(DSColor.accent)
        .toggleStyle(AccentSwitchToggleStyle())
    }

    @ViewBuilder
    private var generalForm: some View {
        Section {
            Picker(selection: appLanguageBinding) {
                Text("システム").tag(AppLanguage.system)
                Text("日本語").tag(AppLanguage.ja)
                Text("English").tag(AppLanguage.en)
            } label: {
                Label("表示言語", systemImage: "globe")
            }
        } header: {
            Text("言語")
        }

        Section {
            Picker(selection: defaultSessionBackendBinding) {
                Text("チャット").tag(DefaultSessionBackendPreference.chat)
                Text("ターミナル").tag(DefaultSessionBackendPreference.terminal)
            } label: {
                Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle")
            }
        } header: {
            Text("セッション")
        } footer: {
            Text("新規セッションをチャット画面かターミナルで開くかの既定です。チャット非対応のエージェントはターミナルで開きます。")
        }

        Section {
            Toggle(isOn: $bannerNotificationEnabled) {
                Label("セッション完了をバナーで通知", systemImage: "bell")
            }
            Toggle(isOn: $completionSoundEnabled) {
                Label("完了サウンド（Glass）を鳴らす", systemImage: "speaker.wave.2")
            }
            Button("通知テスト") {
                SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト"))
            }
            .buttonStyle(.bordered)
        } header: {
            Text("通知")
        }

        Section {
            Toggle(isOn: Binding(
                get: { appUpdater.automaticallyChecksForUpdates },
                set: { appUpdater.automaticallyChecksForUpdates = $0 }
            )) {
                Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath")
            }
            Button("今すぐ確認") {
                appUpdater.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .disabled(!appUpdater.canCheckForUpdates)
        } header: {
            Text("アップデート")
        }
    }

    @ViewBuilder
    private var appearanceForm: some View {
        Section {
            ForEach(ThemeStore.all) { theme in
                ThemeRowView(theme: theme, isSelected: theme.id == themeID) {
                    themeID = theme.id
                }
            }
        } header: {
            Text("外観")
        } footer: {
            Text("テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。")
        }

        Section {
            ForEach(AppIconStore.all) { option in
                AppIconRowView(option: option, isSelected: option.id == appIconID) {
                    appIconID = option.id
                    if let image = NSImage(named: option.assetName) {
                        NSApp.applicationIconImage = image
                    }
                }
            }
        } header: {
            Text("アプリアイコン")
        } footer: {
            Text("Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。")
        }
    }

    @ViewBuilder
    private var agentsForm: some View {
        Section {
            ForEach(agentCatalog.allDescriptors, id: \.ref) { descriptor in
                BypassToggleRow(descriptor: descriptor)
            }
        } header: {
            Text("権限")
        } footer: {
            Text(UIWording.settingsPermissionFooter(languageCode: languageCode))
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Button {
                openWindow(id: AgentConsoleCommands.windowID)
            } label: {
                Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.bordered)
        } header: {
            Text("エージェント")
        } footer: {
            Text("Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。")
        }
    }

    @ViewBuilder
    private var advancedForm: some View {
        Section {
            TextField("最大発言数", value: $agoraMaxUtterances, format: .number)
            TextField("最大エージェント数", value: $agoraMaxAgents, format: .number)
            TextField("ターンタイムアウト（秒）", value: $agoraTurnTimeoutSeconds, format: .number)
            Picker(selection: agoraSchedulerBinding) {
                Text("自由発言").tag(AgoraSchedulerKind.freeSpeech)
                Text("ラウンドロビン").tag(AgoraSchedulerKind.roundRobin)
            } label: {
                Label("スケジューラ", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("チームビュー討論")
        } footer: {
            Text("チームビュー討論の上限・タイムアウト・発言順の既定です。変更は次回の討論開始から反映されます。")
        }

        Section {
            Toggle(isOn: $usageAutoRefresh) {
                Label("使用量サイドバーを自動更新", systemImage: "arrow.clockwise")
            }
            Toggle(isOn: $claudeScrape) {
                Label("Claudeの使用量を取得", systemImage: "sparkles")
            }
            Toggle(isOn: $showUnavailableUsage) {
                Label("未取得のCLIも表示", systemImage: "eye.slash")
            }
            Toggle(isOn: $showUsageInHeader) {
                Label("ヘッダーに使用量を表示", systemImage: "menubar.rectangle")
            }
        } header: {
            Text("使用量")
        } footer: {
            Text("Codex・Cursor の使用量は自動で表示されます。Claude は Phlox 内で起動したセッションの使用量を表示します（直近に Phlox 内で Claude を起動していないと最新の値にならない場合があります）。")
        }

        Section {
            Link(destination: URL(string: "https://phlox.cc/privacy")!) {
                Label("プライバシーポリシー", systemImage: "hand.raised")
            }
            .pointingHandCursor()
        } header: {
            Text("プライバシー")
        }

        Section {
            LabeledContent("アプリ", value: AppFlavor.current.displayName)
            LabeledContent("バージョン", value: appVersion)
            LabeledContent("ビルド", value: buildNumber)
        } header: {
            Text("このアプリについて")
        }
    }

    // MARK: - テーマ選択行（ホバー対応）

    private struct BypassToggleRow: View {
        let descriptor: AgentDescriptor
        @AppStorage private var isEnabled: Bool
        @Environment(\.locale) private var locale

        private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

        init(descriptor: AgentDescriptor) {
            self.descriptor = descriptor
            _isEnabled = AppStorage(wrappedValue: true, descriptor.bypassKey)
        }

        private var agentKind: UIWording.PermissionAgent {
            switch descriptor.ref {
            case .builtin(.claudeCode): .claude
            case .builtin(.codex): .codex
            case .builtin(.cursor): .cursor
            default: .custom
            }
        }

        var body: some View {
            let wording = UIWording.launchPermission(agent: agentKind, displayName: descriptor.displayName, languageCode: languageCode)
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Label(wording.rowLabel, systemImage: descriptor.symbolName)
                    Text(wording.offExplanation)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(wording.onExplanation)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// モバイル端末のペアリング（QR 発行）・一覧・失効 UI。
    /// `@ObservedObject` を非 optional で受けるため、optional な VM は親で `if let` してから渡す。
    private struct MobileTokenSection: View {
        @ObservedObject var viewModel: MobileTokenViewModel
        @State private var newDeviceName = String(localized: "iPhone")

        var body: some View {
            Section {
                TextField("端末名", text: $newDeviceName)
                    .textFieldStyle(.roundedBorder)
                if let disabledReason = viewModel.pairingQRDisabledReason {
                    Text(disabledReason)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Button {
                    Task {
                        let name = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        await viewModel.showPairingQR(deviceName: name.isEmpty ? String(localized: "iPhone") : name)
                    }
                } label: {
                    Label("QR コードを表示", systemImage: "qrcode")
                }
                .disabled(!viewModel.isPairingQREnabled)
                if viewModel.isPairingQRVisible,
                   case .success(let payload) = viewModel.makePairingPayload()
                {
                    PairingQRView(payloadString: payload.urlString)
                }
                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.statusError)
                }
            } header: {
                Text("モバイル接続")
            } footer: {
                Text("iPhone アプリで QR コードを読み取ると、同一 Tailscale ネットワーク経由で接続できます。「QR コードを表示」を押すたびに新しい端末として発行されます。既存の端末は影響を受けません。")
            }
            .task {
                await viewModel.refreshReachability()
            }

            if !viewModel.devices.isEmpty {
                Section {
                    ForEach(viewModel.devices) { device in
                        MobileDeviceRow(device: device) {
                            Task { await viewModel.revoke(id: device.id) }
                        }
                    }
                } header: {
                    Text("接続済みの端末")
                }
            }
        }
    }

    /// ペアリング済み端末一覧の 1 行。名前・ペアリング日時（未ペアリングなら「未接続」）・失効ボタン。
    private struct MobileDeviceRow: View {
        let device: PairedDevice
        let onRevoke: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.s) {
                    Text(device.name)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: DSSpacing.s)
                    Button("失効", role: .destructive, action: onRevoke)
                        .buttonStyle(.borderless)
                        .foregroundStyle(DSColor.statusError)
                }
                Text(pairedAtText)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.vertical, DSSpacing.xxs)
        }

        private var pairedAtText: String {
            guard let pairedAt = device.pairedAt else {
                return String(localized: "未接続")
            }
            return pairedAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// テーマ選択行。ホバーで背景ハイライト＋手のカーソルを出し、クリック可能と分かるようにする。
    /// 候補ごとの ThemePreviewModel でアプリ外観の見本とターミナル配色の色帯を描く。
    private struct ThemeRowView: View {
        let theme: AppTheme
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovering = false

        var body: some View {
            let model = ThemePreviewModel.make(theme: theme)
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: DSSpacing.m) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(theme.name)
                            .foregroundStyle(DSColor.textPrimary)
                        HStack(alignment: .top, spacing: DSSpacing.m) {
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(model.appLabel)
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textTertiary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                ThemeAppPreview(model: model)
                            }
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(model.terminalLabel)
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textTertiary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                ThemeSwatchStrip(model: model)
                            }
                        }
                        .layoutPriority(1)
                    }
                    Spacer(minLength: DSSpacing.s)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DSColor.accent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, DSSpacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .listRowBackground(rowBackground)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
        }

        @ViewBuilder
        private var rowBackground: some View {
            if isSelected {
                DSColor.accent.opacity(isHovering ? 0.18 : 0.13)
            } else if isHovering {
                DSColor.fillSubtle
            } else {
                Color.clear
            }
        }
    }

    /// 候補テーマのアプリ外観見本。本文・現在の会話行・入力欄を model の RGB だけで描く。
    private struct ThemeAppPreview: View {
        let model: ThemePreviewModel

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(model.bodyText)
                    .font(DSFont.caption)
                    .foregroundStyle(model.textPrimary.color)
                    .lineLimit(1)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(model.background.color)
                    Rectangle()
                        .fill(model.selectedRow.rgb.color.opacity(model.selectedRow.opacity))
                    HStack(spacing: DSSpacing.xs) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(model.currentMarker.color)
                            .frame(width: 3, height: 10)
                        Text(model.selectedRowText)
                            .font(DSFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(model.textPrimary.color)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, DSSpacing.xs)
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s))

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(model.background.color)
                    RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                        .fill(model.inputFill.rgb.color.opacity(model.inputFill.opacity))
                    RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                        .strokeBorder(model.inputBorder.rgb.color.opacity(model.inputBorder.opacity), lineWidth: 1)
                    Text(model.inputText)
                        .font(DSFont.caption)
                        .foregroundStyle(model.textPrimary.color)
                        .lineLimit(1)
                        .padding(.horizontal, DSSpacing.xs)
                }
                .frame(height: 20)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
            }
            .padding(DSSpacing.xs)
            .frame(width: 148, alignment: .leading)
            .background(model.background.color)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
        }
    }

    /// アプリアイコン選択行。ThemeRowView と同じホバー挙動＋サムネイル＋チェックマーク。
    private struct AppIconRowView: View {
        let option: AppIconOption
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: DSSpacing.m) {
                    Image(option.assetName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                    Text(option.name)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: DSSpacing.s)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DSColor.accent)
                    }
                }
                .padding(.vertical, DSSpacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(rowBackground)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
        }

        @ViewBuilder
        private var rowBackground: some View {
            if isSelected {
                DSColor.accent.opacity(isHovering ? 0.18 : 0.13)
            } else if isHovering {
                DSColor.fillSubtle
            } else {
                Color.clear
            }
        }
    }

    /// ターミナル配色の色帯。model.terminalSwatches の順に描く。
    private struct ThemeSwatchStrip: View {
        let model: ThemePreviewModel

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(model.terminalSwatches.enumerated()), id: \.offset) { _, rgb in
                    Rectangle()
                        .fill(rgb.color)
                        .frame(width: 9, height: 22)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.s))
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
