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

    @AppStorage(ChatFontSettings.scaleKey) private var chatFontScale = Double(ChatFontSettings.defaultScale)
    @AppStorage(TerminalFontSettings.fontSizeKey) private var terminalFontSize = Double(NSFont.systemFontSize)

    @State private var selectedGroupID = "general"
    /// ターミナルの文字サイズの入力中の値。範囲外なら保存せず、欄から離れても戻さない（10 Settings T6b）。
    @State private var terminalFontDraft: String?

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

    /// モバイル連携のタブは、トークンがあり案内の方針が表示を許すときだけ出す（現行どおり）。
    private var visibleGroups: [SettingsGroup] {
        let showsMobile = mobileToken != nil && MobileConnectionGuidePolicy.showsSettingsConnectionSection
        return SettingsGroup.all.filter { $0.id != "mobile" || showsMobile }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.l)
                .padding(.bottom, DSSpacing.s)

            TabView(selection: $selectedGroupID) {
                ForEach(visibleGroups) { group in
                    groupForm(group)
                        .tabItem {
                            Label(AppLocalizedString.string(group.title, locale: locale), systemImage: group.systemImage)
                        }
                        .tag(group.id)
                        .accessibilityIdentifier("settings-group-\(group.id)")
                }
            }
        }
        .frame(width: 640, height: 680)
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
            .accessibilityHidden(true)
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
            case "notifications":
                notificationsForm
            case "agents":
                agentsForm
            case "usage":
                usageForm
            case "mobile":
                if let mobileToken {
                    MobileTokenSection(viewModel: mobileToken)
                }
            default:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(DSColor.accent)
        .toggleStyle(AccentSwitchToggleStyle())
    }

    // MARK: - 一般

    @ViewBuilder
    private var generalForm: some View {
        Section {
            Picker(selection: appLanguageBinding) {
                Text("システムに合わせる").tag(AppLanguage.system)
                Text(verbatim: "日本語").tag(AppLanguage.ja)
                Text(verbatim: "English").tag(AppLanguage.en)
            } label: {
                Text("表示言語")
            }
            // Form の中の Picker は見出しが読み上げ名にならないため、明示する。
            .accessibilityLabel(Text("表示言語"))
            Picker(selection: defaultSessionBackendBinding) {
                Text("チャット").tag(DefaultSessionBackendPreference.chat)
                Text("ターミナル").tag(DefaultSessionBackendPreference.terminal)
            } label: {
                SettingsRowLabel(title: "新規セッションの既定の開き方", detail: "⌘N や起動カードで ↩ を押したときの開き方。チャット非対応のエージェントはターミナルで開きます。")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("新規セッションの既定の開き方"))
        } header: {
            Text("言語と起動")
        }

        Section {
            Toggle(isOn: Binding(
                get: { appUpdater.automaticallyChecksForUpdates },
                set: { appUpdater.automaticallyChecksForUpdates = $0 }
            )) {
                Text("起動時に自動でアップデートを確認")
            }
            LabeledContent {
                Button("今すぐ確認") {
                    appUpdater.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .disabled(!appUpdater.canCheckForUpdates)
            } label: {
                Text("アップデートを確認")
            }
        } header: {
            Text("アップデート")
        }

        Section {
            LabeledContent {
                Text(verbatim: "\(AppFlavor.current.displayName) \(appVersion)（\(buildNumber)）")
                    .textSelection(.enabled)
            } label: {
                Text("バージョン")
            }
            LabeledContent {
                Link(destination: URL(string: "https://phlox.cc/privacy")!) {
                    Text(verbatim: "phlox.cc/privacy ↗")
                }
                .pointingHandCursor()
            } label: {
                Text("プライバシーポリシー")
            }
        } header: {
            Text("このアプリについて")
        }
    }

    // MARK: - 外観

    @ViewBuilder
    private var appearanceForm: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: DSSpacing.m)], spacing: DSSpacing.m) {
                ForEach(ThemeStore.all) { theme in
                    ThemeTile(theme: theme, isSelected: theme.id == themeID) {
                        themeID = theme.id
                    }
                }
            }
            .padding(.vertical, DSSpacing.xs)
        } header: {
            Text("テーマ")
        } footer: {
            Text("テーマはターミナルの配色とアプリ全体に効き、変更はすぐに反映されます。アクセントの色はすべてのテーマで共通です。")
        }

        Section {
            HStack(spacing: DSSpacing.l) {
                ForEach(AppIconStore.all) { option in
                    AppIconTile(option: option, isSelected: option.id == appIconID) {
                        appIconID = option.id
                        if let image = NSImage(named: option.assetName) {
                            NSApp.applicationIconImage = image
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpacing.xs)
        } header: {
            Text("アプリアイコン")
        } footer: {
            Text("Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。")
        }

        Section {
            LabeledContent {
                HStack(spacing: DSSpacing.s) {
                    // 端の値はスライダーの外の文字にする（minimumValueLabel はボタンになり、Tab の焦点が名前の無いまま止まる）。
                    Text(verbatim: "\(percent(ChatFontSettings.minScale))%")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                    Slider(
                        value: $chatFontScale,
                        in: Double(ChatFontSettings.minScale)...Double(ChatFontSettings.maxScale),
                        step: Double(ChatFontSettings.step)
                    ) {
                        Text("チャット本文")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    Text(verbatim: "\(percent(ChatFontSettings.maxScale))%")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(percent(chatFontScale))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } label: {
                SettingsRowLabel(title: "チャット本文", detail: "⌘+ / ⌘− でも変えられます（フォーカス中の領域に効きます）。")
            }
            terminalFontRow
        } header: {
            Text("文字の大きさ")
        }
    }

    private func percent(_ scale: some BinaryFloatingPoint) -> Int {
        Int((Double(scale) * 100).rounded())
    }

    /// ターミナルの文字サイズ。整数を直接入れるか ▲▼ で変える。範囲外は保存せず理由と現在の値を出す。
    private var terminalFontRow: some View {
        let current = Int(terminalFontSize.rounded())
        let draft = terminalFontDraft ?? String(current)
        let isInvalid = TerminalFontSettings.parse(draft) == nil
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            LabeledContent {
                HStack(spacing: DSSpacing.xs) {
                    TextField(text: Binding(
                        get: { draft },
                        set: { terminalFontDraft = $0 }
                    )) {
                        Text("ターミナル")
                    }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 48)
                    .onSubmit(commitTerminalFont)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isInvalid ? DSColor.statusError : Color.clear, lineWidth: 1)
                    )
                    Stepper(
                        value: Binding(
                            get: { terminalFontSize },
                            set: { terminalFontSize = $0; terminalFontDraft = nil }
                        ),
                        in: Double(TerminalFontSettings.minSize)...Double(TerminalFontSettings.maxSize),
                        step: Double(TerminalFontSettings.step)
                    ) {
                        Text("ターミナル")
                    }
                    .labelsHidden()
                    Text(verbatim: "pt")
                        .foregroundStyle(DSColor.textSecondary)
                }
            } label: {
                SettingsRowLabel(
                    title: "ターミナル",
                    detail: isInvalid ? nil : "ターミナルパネル・グリッドのターミナル・単体表示で共通です。"
                )
            }
            if isInvalid {
                Text(String(
                    format: AppLocalizedString.string("%lld〜%lld の整数を入力してください。保存していません（現在の値: %lld）", locale: locale),
                    Int(TerminalFontSettings.minSize), Int(TerminalFontSettings.maxSize), current
                ))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.statusError)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func commitTerminalFont() {
        guard let draft = terminalFontDraft, let size = TerminalFontSettings.parse(draft) else { return }
        terminalFontSize = Double(size)
        terminalFontDraft = nil
    }

    // MARK: - 通知

    @ViewBuilder
    private var notificationsForm: some View {
        Section {
            Toggle(isOn: $bannerNotificationEnabled) {
                SettingsRowLabel(title: "バナーで知らせる", detail: "承認待ち・質問待ち・完了・エラーを macOS の通知で知らせます。")
            }
            Toggle(isOn: $completionSoundEnabled) {
                Text("完了サウンド（Glass）を鳴らす")
            }
            LabeledContent {
                Button("通知テスト") {
                    SessionCompletionNotifier.notifyTest()
                }
                .buttonStyle(.bordered)
            } label: {
                Text("通知をテスト")
            }
        } header: {
            Text("セッションが止まったとき")
        }
    }

    // MARK: - エージェント

    @ViewBuilder
    private var agentsForm: some View {
        Section {
            ForEach(agentCatalog.allDescriptors, id: \.ref) { descriptor in
                BypassToggleRow(descriptor: descriptor)
            }
        } header: {
            Text("フルアクセス（権限の確認を省く）")
        } footer: {
            Text(UIWording.settingsPermissionFooter(languageCode: languageCode))
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            LabeledContent {
                HStack(spacing: DSSpacing.s) {
                    Text(verbatim: "⇧⌘,")
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                    Button {
                        openWindow(id: AgentConsoleCommands.windowID)
                    } label: {
                        Text("エージェント管理を開く")
                    }
                    .buttonStyle(.bordered)
                }
            } label: {
                SettingsRowLabel(
                    title: "エージェント管理",
                    detail: "CLI ごとの設定ファイル（settings.json・config.toml・cli-config.json）を直接編集します。対話 TUI のスラッシュコマンドや手編集でしか触れない項目が対象です。"
                )
            }
            LabeledContent {
                Text(verbatim: (CustomAgentRegistryLoader.defaultURL().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            } label: {
                Text("カスタムエージェントの定義")
            }
        } header: {
            Text("詳しい設定")
        }
    }

    // MARK: - 使用量

    @ViewBuilder
    private var usageForm: some View {
        Section {
            Toggle(isOn: $usageAutoRefresh) {
                Text("自動で更新する")
            }
            Toggle(isOn: $claudeScrape) {
                SettingsRowLabel(title: "Claude の使用量を取得する", detail: "Claude はほかの CLI と取得方法が異なるため、個別にオフにできます。")
            }
            Toggle(isOn: $showUnavailableUsage) {
                SettingsRowLabel(title: "取得できない CLI も表示する", detail: "未インストールの CLI をインスペクタに「未取得」として並べます。")
            }
            Toggle(isOn: $showUsageInHeader) {
                SettingsRowLabel(title: "上部バーに使用量を表示する", detail: "インスペクタの開閉とは関係なく表示します。")
            }
        } header: {
            Text("使用量")
        } footer: {
            Text("Codex・Cursor の使用量は自動で表示されます。Claude は Phlox 内で起動したセッションの使用量を表示します（直近に Phlox 内で Claude を起動していないと最新の値にならない場合があります）。")
        }
    }

    // MARK: - 行の部品

    /// 行の見出しと、その下の補足（10 Settings の行の形）。
    private struct SettingsRowLabel: View {
        let title: LocalizedStringKey
        var detail: LocalizedStringKey?

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: descriptor.displayName)
                    Text(verbatim: AppLocalizedString.string("オン", locale: locale) + ": " + wording.onExplanation)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: AppLocalizedString.string("オフ", locale: locale) + ": " + wording.offExplanation)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel(Text(verbatim: wording.rowLabel))
        }
    }

    /// モバイル端末のペアリング（QR 発行）・一覧・失効 UI。
    /// `@ObservedObject` を非 optional で受けるため、optional な VM は親で `if let` してから渡す。
    private struct MobileTokenSection: View {
        @ObservedObject var viewModel: MobileTokenViewModel
        @State private var newDeviceName = "iPhone"
        /// 失効の確認（09 A 型）。
        @State private var pendingRevoke: PairedDevice?
        @Environment(\.locale) private var locale

        var body: some View {
            Section {
                TextField(text: $newDeviceName) {
                    Text("端末の名前")
                }
                .accessibilityLabel(Text("端末の名前"))
                LabeledContent {
                    Button {
                        Task {
                            let name = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                            await viewModel.showPairingQR(deviceName: name.isEmpty ? "iPhone" : name)
                        }
                    } label: {
                        viewModel.isPairingQRVisible ? Text("表示中") : Text("QR コードを表示")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.accentFill)
                    .disabled(!viewModel.isPairingQREnabled || viewModel.isPairingQRVisible)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QR コードでペアリング")
                        if let disabledReason = viewModel.pairingQRDisabledReason {
                            Text(verbatim: AppLocalizedString.string(disabledReason, locale: locale))
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if viewModel.isPairingQRVisible,
                   case .success(let payload) = viewModel.makePairingPayload()
                {
                    HStack(alignment: .center, spacing: DSSpacing.l) {
                        PairingQRView(payloadString: payload.urlString, warningText: "", imageSize: 160)
                            .fixedSize()
                        VStack(alignment: .leading, spacing: DSSpacing.s) {
                            Text("iPhone の Phlox で読み取ってください")
                            if let hidesAt = viewModel.pairingQRHidesAt {
                                Text("あと \(Text(timerInterval: Date()...max(Date(), hidesAt), countsDown: true)) で非表示になります")
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                                    .monospacedDigit()
                            }
                            Button("今すぐ隠す") { viewModel.hidePairingQR() }
                                .buttonStyle(.bordered)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let lastError = viewModel.lastError {
                    Text(verbatim: AppLocalizedString.string(lastError, locale: locale))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.statusError)
                }
            } header: {
                Text("新しい端末をつなぐ")
            } footer: {
                Text("QR にはフルアクセス権限のトークンが含まれます。60 秒後に自動的に非表示になります。iPhone アプリで読み取ると、同一 Tailscale ネットワーク経由で接続できます。「QR コードを表示」を押すたびに新しい端末として発行され、既存の端末は影響を受けません。")
            }
            .task {
                await viewModel.refreshReachability()
            }
            .dsDialog(item: $pendingRevoke) { device in
                DSDialog(
                    .irreversible,
                    title: String(format: AppLocalizedString.string("「%@」を失効させますか?", locale: locale), device.name),
                    message: AppLocalizedString.string("この端末は Phlox に接続できなくなります。もう一度つなぐには QR コードでペアリングし直します。元に戻せません。", locale: locale),
                    buttons: [
                        DSDialogButton("失効", role: .destructive) {
                            pendingRevoke = nil
                            Task { await viewModel.revoke(id: device.id) }
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingRevoke = nil },
                    ],
                    onCancel: { pendingRevoke = nil }
                )
            }

            if !viewModel.devices.isEmpty {
                Section {
                    ForEach(viewModel.devices) { device in
                        MobileDeviceRow(device: device) { pendingRevoke = device }
                    }
                } header: {
                    Text("接続済みの端末")
                }
            }
        }
    }

    /// ペアリング済み端末一覧の 1 行。名前・ペアリング日（未ペアリングなら「未接続」）・失効ボタン。
    private struct MobileDeviceRow: View {
        let device: PairedDevice
        let onRevoke: () -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            LabeledContent {
                Button("失効", role: .destructive, action: onRevoke)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DSColor.statusError)
                    .accessibilityLabel(Text(verbatim: String(format: AppLocalizedString.string("「%@」を失効", locale: locale), device.name)))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: device.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(verbatim: pairedAtText)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }

        private var pairedAtText: String {
            guard let pairedAt = device.pairedAt else {
                return AppLocalizedString.string("未接続", locale: locale)
            }
            return String(
                format: AppLocalizedString.string("%@にペアリング", locale: locale),
                pairedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
            )
        }
    }

    /// テーマの見本タイル（10 Settings: 格子で並べ、名前は下）。選んでいるものはアクセントの枠。
    private struct ThemeTile: View {
        let theme: AppTheme
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            let model = ThemePreviewModel.make(theme: theme)
            Button(action: onSelect) {
                VStack(spacing: DSSpacing.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        ThemeAppPreview(model: model)
                        ThemeSwatchStrip(model: model)
                    }
                    .frame(width: 148)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.m)
                            .strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1)
                    )
                    Text(verbatim: theme.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel(Text(verbatim: theme.name))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// アプリアイコンのタイル。選んだ時点で Dock に反映する。
    private struct AppIconTile: View {
        let option: AppIconOption
        let isSelected: Bool
        let onSelect: () -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            Button(action: onSelect) {
                VStack(spacing: DSSpacing.xs) {
                    Image(option.assetName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(isSelected ? DSColor.accent : Color.clear, lineWidth: 2)
                        )
                    Text(verbatim: AppLocalizedString.string(option.name, locale: locale))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel(Text(verbatim: AppLocalizedString.string(option.name, locale: locale)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// 候補テーマのアプリ外観見本。本文・現在の会話行・入力欄を model の RGB だけで描く。
    private struct ThemeAppPreview: View {
        let model: ThemePreviewModel
        @Environment(\.locale) private var locale

        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: AppLocalizedString.string(model.bodyText, locale: locale))
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
                        Text(verbatim: AppLocalizedString.string(model.selectedRowText, locale: locale))
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
                    Text(verbatim: AppLocalizedString.string(model.inputText, locale: locale))
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

    /// ターミナル配色の色帯。model.terminalSwatches の順に描く。
    private struct ThemeSwatchStrip: View {
        let model: ThemePreviewModel

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(model.terminalSwatches.enumerated()), id: \.offset) { _, rgb in
                    Rectangle()
                        .fill(rgb.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
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
