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
    // 読む側（NotificationSettings）と同じ保存先に書く。
    @AppStorage(NotificationSettings.dockBadgeKey, store: .phloxDefaults()) private var dockBadgeCount = NotificationSettings.DockBadgeCount.attention

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

    private var currentGroup: SettingsGroup {
        visibleGroups.first { $0.id == selectedGroupID } ?? visibleGroups[0]
    }

    var body: some View {
        let group = currentGroup
        VStack(spacing: 0) {
            SettingsTabBar(groups: visibleGroups, selection: $selectedGroupID)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    groupContent(group)
                }
                .padding(EdgeInsets(top: 20, leading: 28, bottom: 24, trailing: 28))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(group.id)
            .accessibilityIdentifier("settings-group-\(group.id)")
        }
        // 10 Settings: 幅 700、高さはタブごと（見本の窓全体の値からタイトルバーの 28 を引く。中身が長ければスクロールする）。
        .frame(width: 700, height: Self.windowHeight(for: group.id) - 28)
        .background(DSColor.settingsBackground)
        .toggleStyle(AccentSwitchToggleStyle())
        // 題名はタイトルバーの中央（見本 10 の窓）。窓の題名は読み上げと「ウインドウ」メニューのために残し、表示だけ隠す。
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                Text(verbatim: AppLocalizedString.string(group.title, locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .navigationTitle(Text(AppLocalizedString.string(group.title, locale: locale)))
        .background(SettingsWindowChrome(groupID: group.id))
        .preferredColorScheme(ThemeStore.active.preferredColorScheme)
    }

    static func windowHeight(for groupID: String) -> CGFloat {
        switch groupID {
        case "appearance": 660
        case "notifications": 480
        case "usage": 440
        case "mobile": 560
        default: 620
        }
    }

    @ViewBuilder
    private func groupContent(_ group: SettingsGroup) -> some View {
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

    // MARK: - 一般

    @ViewBuilder
    private var generalForm: some View {
        SettingsGroupBox("言語と起動") {
            SettingsRow {
                SettingsLabel(title: Text("表示言語"))
                Picker(selection: appLanguageBinding) {
                    Text("システムに合わせる").tag(AppLanguage.system)
                    Text(verbatim: "日本語").tag(AppLanguage.ja)
                    Text(verbatim: "English").tag(AppLanguage.en)
                } label: {
                    Text("表示言語")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            SettingsDivider()
            SettingsRow {
                SettingsLabel(title: Text("新規セッションの既定の開き方"), detail: Text("⌘N や起動カードで ↩ を押したときの開き方"))
                SettingsSegmented(
                    selection: defaultSessionBackendBinding,
                    options: [(.chat, "チャット"), (.terminal, "ターミナル")]
                )
                .accessibilityLabel(Text("新規セッションの既定の開き方"))
            }
        }

        SettingsGroupBox("アップデート") {
            SettingsRow {
                Toggle(isOn: Binding(
                    get: { appUpdater.automaticallyChecksForUpdates },
                    set: { appUpdater.automaticallyChecksForUpdates = $0 }
                )) {
                    SettingsLabel(title: Text("起動時に自動でアップデートを確認"))
                }
            }
            SettingsDivider()
            SettingsRow {
                SettingsLabel(title: Text("アップデートを確認"))
                Button("今すぐ確認…") {
                    appUpdater.checkForUpdates()
                }
                .buttonStyle(.ds(.secondary, height: 22, fontSize: 12.5, padding: 11, fill: DSColor.settingsControlBackground, cornerRadius: 5))
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }

        SettingsGroupBox("このアプリについて") {
            SettingsRow {
                SettingsLabel(title: Text("バージョン"))
                Text(verbatim: "\(AppFlavor.current.displayName) \(appVersion)（\(buildNumber)）")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
            }
            SettingsDivider()
            SettingsRow {
                SettingsLabel(title: Text("プライバシーポリシー"))
                Link(destination: URL(string: "https://phlox.cc/privacy")!) {
                    Text(verbatim: "phlox.cc/privacy ↗")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DSColor.accentInk)
                }
                .pointingHandCursor()
            }
        }
    }

    // MARK: - 外観

    @ViewBuilder
    private var appearanceForm: some View {
        SettingsGroupBox("テーマ", footer: Text("アクセントの色（コーラル）はすべてのテーマで共通。テーマはターミナルの配色とアプリ全体に効き、すぐに反映される。")) {
            SettingsRow {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(ThemeStore.all) { theme in
                        ThemeTile(theme: theme, isSelected: theme.id == themeID) {
                            themeID = theme.id
                        }
                    }
                }
                .modifier(TileRadioGroup(
                    label: Text("テーマ"),
                    options: ThemeStore.all.map { ($0.id, $0.name) },
                    columns: 5,
                    selection: themeID
                ) { themeID = $0 })
            }
        }

        SettingsGroupBox("アプリアイコン") {
            SettingsRow {
                HStack(spacing: 14) {
                    ForEach(AppIconStore.all) { option in
                        AppIconTile(option: option, isSelected: option.id == appIconID) {
                            selectAppIcon(option)
                        }
                    }
                }
                .modifier(TileRadioGroup(
                    label: Text("アプリアイコン"),
                    options: AppIconStore.all.map { ($0.id, AppLocalizedString.string($0.name, locale: locale)) },
                    columns: AppIconStore.all.count,
                    selection: appIconID
                ) { id in
                    if let option = AppIconStore.all.first(where: { $0.id == id }) { selectAppIcon(option) }
                })
                Spacer(minLength: 0)
            }
        }

        SettingsGroupBox("文字の大きさ") {
            SettingsRow {
                SettingsLabel(title: Text("チャット本文"), detail: Text("⌘+ / ⌘− でも変えられる（フォーカス中の領域に効く）"))
                HStack(spacing: 10) {
                    // 端の値はスライダーの外の文字にする（minimumValueLabel はボタンになり、Tab の焦点が名前の無いまま止まる）。
                    Text(verbatim: "\(percent(ChatFontSettings.minScale))%")
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                    // step を渡すと目盛りが出る（見本に無い）。刻みは値を丸めて守る。
                    Slider(
                        value: Binding(
                            get: { chatFontScale },
                            set: { chatFontScale = Double(ChatFontSettings.snapped(CGFloat($0))) }
                        ),
                        in: Double(ChatFontSettings.minScale)...Double(ChatFontSettings.maxScale)
                    ) {
                        Text("チャット本文")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(DSColor.accentFill)
                    .frame(width: 150)
                    // 丸めで戻らないよう、← → と読み上げの増減は 1 刻みずつ動かす。
                    .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                        nudgeChatFont(press.key == .rightArrow ? 1 : -1)
                        return .handled
                    }
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: nudgeChatFont(1)
                        case .decrement: nudgeChatFont(-1)
                        @unknown default: break
                        }
                    }
                    Text(verbatim: "\(percent(ChatFontSettings.maxScale))%")
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(percent(chatFontScale))%")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            SettingsDivider()
            terminalFontRow
        }
    }

    private func nudgeChatFont(_ steps: Int) {
        let next = ChatFontSettings.adjusted(from: CGFloat(chatFontScale), by: ChatFontSettings.step * CGFloat(steps))
        chatFontScale = Double(ChatFontSettings.snapped(next))
    }

    private func percent(_ scale: some BinaryFloatingPoint) -> Int {
        Int((Double(scale) * 100).rounded())
    }

    /// ターミナルの文字サイズ。整数を直接入れるか ▲▼ で変える。範囲外は保存せず理由と現在の値を出す（T6b）。
    private var terminalFontRow: some View {
        let current = Int(terminalFontSize.rounded())
        let draft = terminalFontDraft ?? String(current)
        let isInvalid = TerminalFontSettings.parse(draft) == nil
        return SettingsRow(error: isInvalid ? Text(String(
            format: AppLocalizedString.string("%lld〜%lld の整数を入力してください。保存していません（現在の値: %lld）", locale: locale),
            Int(TerminalFontSettings.minSize), Int(TerminalFontSettings.maxSize), current
        )) : nil) {
            SettingsLabel(
                title: Text("ターミナル"),
                detail: isInvalid ? nil : Text("ターミナルパネル・グリッドのターミナル・単体表示で共通")
            )
            HStack(spacing: 6) {
                TextField(text: Binding(
                    get: { draft },
                    set: { terminalFontDraft = $0 }
                )) {
                    Text("ターミナル")
                }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .settingsField(width: 56, isInvalid: isInvalid)
                .onSubmit(commitTerminalFont)
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
                .controlSize(.small)
                Text(verbatim: "pt")
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(minWidth: 14, alignment: .leading)
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
        SettingsGroupBox("セッションが止まったとき") {
            SettingsRow {
                Toggle(isOn: $bannerNotificationEnabled) {
                    SettingsLabel(title: Text("バナーで知らせる"), detail: Text("承認待ち・質問待ち・完了・エラーを macOS の通知で出す"))
                }
            }
            SettingsDivider()
            SettingsRow {
                Toggle(isOn: $completionSoundEnabled) {
                    SettingsLabel(title: Text("完了サウンド（Glass）を鳴らす"))
                }
            }
            SettingsDivider()
            SettingsRow {
                SettingsLabel(title: Text("通知をテスト"))
                Button("テスト通知を送る") {
                    SessionCompletionNotifier.notifyTest()
                }
                .buttonStyle(.ds(.secondary, height: 22, fontSize: 12.5, padding: 11, fill: DSColor.settingsControlBackground, cornerRadius: 5))
            }
        }

        SettingsGroupBox("Dock") {
            SettingsRow {
                SettingsLabel(title: Text("バッジに出す数"), detail: Text("対応待ちは承認待ち・質問待ち・エラー・無応答"))
                Picker(selection: $dockBadgeCount) {
                    Text("対応待ちの数").tag(NotificationSettings.DockBadgeCount.attention)
                    Text("未読の完了の数").tag(NotificationSettings.DockBadgeCount.unseenCompletions)
                } label: {
                    Text("バッジに出す数")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    // MARK: - エージェント

    private var permissionFooter: String {
        let lead = AppLocalizedString.string("オンの間は、エージェントがファイルの変更やコマンドを確認なしで実行します。", locale: locale)
        // 日本語の文は空白を挟まずに続ける。
        return lead + (lead.hasSuffix("。") ? "" : " ") + UIWording.settingsPermissionFooter(languageCode: languageCode)
    }

    @ViewBuilder
    private var agentsForm: some View {
        SettingsGroupBox(
            "フルアクセス（権限の確認を省く）",
            // 見本の注記（確認なしで実行する）に、エージェントごとに違う点の注記（既存の文）を続ける（C-53）。
            footer: Text(verbatim: permissionFooter)
        ) {
            ForEach(Array(agentCatalog.allDescriptors.enumerated()), id: \.element.ref) { index, descriptor in
                if index > 0 { SettingsDivider() }
                BypassToggleRow(descriptor: descriptor)
            }
        }

        SettingsGroupBox("詳しい設定") {
            SettingsRow {
                SettingsLabel(
                    title: Text("エージェント管理"),
                    detail: Text("CLI ごとの設定ファイル（settings.json・config.toml・cli-config.json）を直接編集する")
                )
                Button {
                    openWindow(id: AgentConsoleCommands.windowID)
                } label: {
                    Text("開く…")
                }
                .buttonStyle(.ds(.secondary, keyHint: "⇧⌘,", height: 22, fontSize: 12.5, padding: 11, fill: DSColor.settingsControlBackground, cornerRadius: 5))
                // 読み上げでは何を開くかが分かる名前にする。
                .accessibilityLabel(Text("エージェント管理を開く"))
            }
            SettingsDivider()
            SettingsRow {
                SettingsLabel(title: Text("カスタムエージェントの定義"))
                Text(verbatim: (CustomAgentRegistryLoader.defaultURL().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - 使用量

    @ViewBuilder
    private var usageForm: some View {
        SettingsGroupBox("使用量") {
            SettingsRow {
                Toggle(isOn: $usageAutoRefresh) {
                    SettingsLabel(title: Text("自動で更新する"))
                }
            }
            SettingsDivider()
            SettingsRow {
                Toggle(isOn: $claudeScrape) {
                    SettingsLabel(title: Text("Claude の使用量を取得する"), detail: Text("Claude はほかの CLI と取得方法が異なるため、個別にオフにできる"))
                }
            }
            SettingsDivider()
            SettingsRow {
                Toggle(isOn: $showUnavailableUsage) {
                    SettingsLabel(title: Text("取得できない CLI も表示する"), detail: Text("未インストールの CLI をインスペクタに「未取得」として並べる"))
                }
            }
            SettingsDivider()
            SettingsRow {
                Toggle(isOn: $showUsageInHeader) {
                    SettingsLabel(title: Text("上部バーに使用量を表示する"), detail: Text("インスペクタの開閉とは関係なく表示する"))
                }
            }
        }
    }

    // MARK: - 行の部品

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

        /// 10 Settings T4: オンのとき付けるものを 1 行で。オフのときの違いは「オフにすると」で続ける。
        private var summary: LocalizedStringKey {
            switch agentKind {
            case .claude: "bypassPermissions を指定する。オフにすると auto"
            case .codex: "チャットは never・danger-full-access、ターミナルは解除の引数を付ける。オフにすると、チャットは on-request・workspace-write、ターミナルは Codex の設定に従う"
            case .cursor: "--force --sandbox disabled。オフにすると --auto-review --sandbox enabled"
            case .custom: "agents.json の定義に従う"
            }
        }

        var body: some View {
            let wording = UIWording.launchPermission(agent: agentKind, displayName: descriptor.displayName, languageCode: languageCode)
            SettingsRow {
                Toggle(isOn: $isEnabled) {
                    SettingsLabel(title: Text(verbatim: descriptor.displayName), detail: Text(summary))
                }
                .accessibilityLabel(Text(verbatim: wording.rowLabel))
            }
        }
    }

    /// モバイル端末のペアリング（QR 発行）・一覧・失効 UI。
    /// `@ObservedObject` を非 optional で受けるため、optional な VM は親で `if let` してから渡す。
    private struct MobileTokenSection: View {
        @ObservedObject var viewModel: MobileTokenViewModel
        @AppStorage(NotificationSettings.pushKey, store: .phloxDefaults()) private var pushNotificationEnabled = true
        @State private var newDeviceName = "iPhone"
        /// 失効の確認（09 A 型）。
        @State private var pendingRevoke: PairedDevice?
        @Environment(\.locale) private var locale

        var body: some View {
            // L5: QR を作れなかったときは内容の先頭に帯で出す。
            if let lastError = viewModel.lastError {
                SettingsErrorBanner(text: AppLocalizedString.string(lastError, locale: locale))
            }
            SettingsGroupBox("新しい端末をつなぐ", footer: Text("QR にはフルアクセス権限のトークンが含まれます。60 秒後に自動的に非表示になります。")) {
                SettingsRow {
                    SettingsLabel(title: Text("端末の名前"))
                    TextField(text: $newDeviceName) {
                        Text("端末の名前")
                    }
                    .labelsHidden()
                    .settingsField(width: 180, isInvalid: false)
                    .accessibilityLabel(Text("端末の名前"))
                }
                SettingsDivider()
                SettingsRow {
                    // L4: 押せない理由は承認待ちと同じ琥珀の文字（見本の色の指定）。
                    SettingsLabel(
                        title: Text("QR コードでペアリング"),
                        detail: viewModel.pairingQRDisabledReason.map { Text(verbatim: AppLocalizedString.string($0, locale: locale)) },
                        detailColor: DSColor.attentionInk(.approval)
                    )
                    let isPrimary = viewModel.isPairingQREnabled && !viewModel.isPairingQRVisible
                    Button {
                        Task {
                            let name = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                            await viewModel.showPairingQR(deviceName: name.isEmpty ? "iPhone" : name)
                        }
                    } label: {
                        viewModel.isPairingQRVisible ? Text("表示中") : Text("QR コードを表示")
                    }
                    .buttonStyle(.ds(isPrimary ? .primary : .secondary, height: 22, fontSize: 12.5, padding: 11, fill: DSColor.settingsControlBackground, cornerRadius: 5))
                    .disabled(!isPrimary)
                }
                if viewModel.isPairingQRVisible,
                   case .success(let payload) = viewModel.makePairingPayload()
                {
                    SettingsRow {
                        HStack(alignment: .center, spacing: 16) {
                            if let image = PairingQRView.makeQRImage(from: payload.urlString, targetSize: 112) {
                                Image(nsImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 112, height: 112)
                                    .frame(width: 132, height: 132)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.separator, lineWidth: 1))
                                    .accessibilityLabel(Text("ペアリング用 QR コード"))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("iPhone の Phlox で読み取ってください")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DSColor.textPrimary)
                                if let hidesAt = viewModel.pairingQRHidesAt {
                                    Text("あと \(Text(timerInterval: Date()...max(Date(), hidesAt), countsDown: true)) で非表示になります")
                                        .font(.system(size: 12))
                                        .monospacedDigit()
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                                Button("今すぐ隠す") { viewModel.hidePairingQR() }
                                    .buttonStyle(.ds(.secondary, height: 22, fontSize: 12, padding: 10, fill: DSColor.settingsControlBackground, cornerRadius: 5))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
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
                SettingsGroupBox("接続済みの端末") {
                    ForEach(Array(viewModel.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { SettingsDivider() }
                        MobileDeviceRow(device: device, lastSeenAt: viewModel.lastSeenAt[device.id]) { pendingRevoke = device }
                    }
                }
            }

            // 10 Settings L3: つないだ端末があるときだけ、スマホへ送るかを選べるようにする。
            if !viewModel.devices.isEmpty {
                SettingsGroupBox("プッシュ通知") {
                    SettingsRow {
                        Toggle(isOn: $pushNotificationEnabled) {
                            if viewModel.isPushSendingConfigured {
                                SettingsLabel(title: Text("iPhone に通知を送る"), detail: Text("承認待ち・質問待ち・完了・エラーを iPhone の通知で知らせる"))
                            } else {
                                SettingsLabel(
                                    title: Text("iPhone に通知を送る"),
                                    detail: Text("送信の鍵（APNs）が未設定のため、オンでも送信されません。"),
                                    detailColor: DSColor.attentionInk(.approval)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// ペアリング済み端末一覧の 1 行。名前・「ペアリング日 · 接続中／未接続」（未ペアリングなら「未接続」）・失効ボタン。
    private struct MobileDeviceRow: View {
        let device: PairedDevice
        let lastSeenAt: Date?
        let onRevoke: () -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            SettingsRow {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    SettingsLabel(title: Text(verbatim: device.name), detail: Text(verbatim: detailText(now: context.date)))
                }
                Button("失効", action: onRevoke)
                    .buttonStyle(.ds(.destructive, height: 22, fontSize: 12, padding: 10, fill: DSColor.settingsControlBackground, cornerRadius: 5))
                    .accessibilityLabel(Text(verbatim: String(format: AppLocalizedString.string("「%@」を失効", locale: locale), device.name)))
            }
        }

        private func detailText(now: Date) -> String {
            guard let pairedAt = device.pairedAt else {
                return AppLocalizedString.string("未接続", locale: locale)
            }
            let paired = String(
                format: AppLocalizedString.string("%@にペアリング", locale: locale),
                pairedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
            )
            let presence = MobileDevicePresence.isConnected(lastSeenAt: lastSeenAt, now: now) ? "接続中" : "未接続"
            return paired + " · " + AppLocalizedString.string(presence, locale: locale)
        }
    }

    private func selectAppIcon(_ option: AppIconOption) {
        appIconID = option.id
        if let image = NSImage(named: option.assetName) {
            NSApp.applicationIconImage = image
        }
    }

    /// タイルの並びを 1 つのラジオグループとして読ませ、矢印キーで選択を動かす（C-56、見本の role="radio"）。
    private struct TileRadioGroup: ViewModifier {
        let label: Text
        let options: [(id: String, name: String)]
        let columns: Int
        let selection: String
        let select: (String) -> Void

        func body(content: Content) -> some View {
            content
                .focusable()
                .onKeyPress(.leftArrow) { move(by: -1) }
                .onKeyPress(.rightArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -columns) }
                .onKeyPress(.downArrow) { move(by: columns) }
                .accessibilityRepresentation {
                    Picker(selection: Binding(get: { selection }, set: { select($0) })) {
                        ForEach(options, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                    } label: {
                        label
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityLabel(label)
                }
        }

        private func move(by offset: Int) -> KeyPress.Result {
            guard let index = options.firstIndex(where: { $0.id == selection }) else { return .ignored }
            let next = index + offset
            guard options.indices.contains(next) else { return .handled }
            select(options[next].id)
            return .handled
        }
    }

    /// テーマの見本タイル（10 Settings T2: 5 列。高さ 54・角丸 7、左 28% がサイドバー、右に 2 本の文字と accent の帯）。
    private struct ThemeTile: View {
        let theme: AppTheme
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            let isDarkTheme = theme.preferredColorScheme == .dark
            let ink = isDarkTheme ? Color.white : Color.black
            Button(action: onSelect) {
                VStack(spacing: 5) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(theme.palette.sidebar.color)
                                .frame(width: proxy.size.width * 0.28)
                            VStack(alignment: .leading, spacing: 3) {
                                let body = proxy.size.width * 0.72 - 10
                                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(isDarkTheme ? 0.7 : 0.65)).frame(width: body * 0.7, height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(isDarkTheme ? 0.35 : 0.3)).frame(width: body * 0.5, height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(RGB(0xD9, 0x77, 0x57).color).frame(width: body * 0.34, height: 6)
                                    .padding(.top, 2)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                    .frame(height: 54)
                    .background(theme.background.color)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(DSColor.accent, lineWidth: 2)
                                .padding(-2)
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(DSColor.separator, lineWidth: 1)
                        }
                    }
                    Text(verbatim: theme.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel(Text(verbatim: theme.name))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// アプリアイコンのタイル（48pt・角丸 11、名前は id を等幅で）。選んだ時点で Dock に反映する。
    private struct AppIconTile: View {
        let option: AppIconOption
        let isSelected: Bool
        let onSelect: () -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            Button(action: onSelect) {
                VStack(spacing: 5) {
                    Image(option.assetName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(DSColor.accent, lineWidth: 2)
                                    .padding(-2)
                            } else {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(DSColor.separator, lineWidth: 1)
                            }
                        }
                    Text(verbatim: option.id)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// 10 Settings の部品。標準の Form・TabView では見本の余白・区切り・色を再現できないため自前で描く。

/// 上端のタブ列（アイコン 20・名前 11pt、選択中は accentInk の文字と淡い面）。
struct SettingsTabBar: View {
    let groups: [SettingsGroup]
    @Binding var selection: String
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 2) {
            ForEach(groups) { group in
                let isSelected = group.id == selection
                let title = AppLocalizedString.string(group.title, locale: locale)
                Button {
                    selection = group.id
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: group.systemImage)
                            .font(.system(size: 16))
                            .frame(height: 20)
                        Text(verbatim: title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? DSColor.accentInk : DSColor.textSecondary)
                    .frame(minWidth: 64)
                    .padding(EdgeInsets(top: 4, leading: 8, bottom: 3, trailing: 8))
                    .background(isSelected ? DSColor.settingsTabSelected : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
        .frame(maxWidth: .infinity)
        .background(DSColor.toolbarBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-window")
    }
}

/// タイトルバーをタブ列と同じ面にする（見本はタイトルとタブが続いた 1 枚の面）。
/// 透明にしたタイトルバーには窓の地が見えるので、地をタブ列の色にする。テーマを変えたら塗り直す。
/// タブを切り替えると題名の変更で設定が戻るので、タブが変わるたびに当て直す（`groupID` はそのための入力）。
struct SettingsWindowChrome: NSViewRepresentable {
    let groupID: String

    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ChromeView else { return }
        view.apply()
        DispatchQueue.main.async { view.apply() }
    }

    fileprivate final class ChromeView: NSView {
        private var observations: [NSKeyValueObservation] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // 窓を出す処理（SwiftUI）が後から題名と形を戻すので、戻されたら当て直す。
            observations = [
                window?.observe(\.title) { [weak self] _, _ in DispatchQueue.main.async { self?.apply() } },
                window?.observe(\.styleMask) { [weak self] _, _ in DispatchQueue.main.async { self?.apply() } },
            ].compactMap { $0 }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let window else { return }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(DSColor.toolbarBackground)
        }
    }
}

/// 行のまとまり（見出し 12pt semibold・角丸 10 の面と 1pt の縁・下に 11.5pt の注記）。
struct SettingsGroupBox<Content: View>: View {
    let title: LocalizedStringKey
    let footer: Text?
    let content: Content

    init(_ title: LocalizedStringKey, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content
            }
            .background(DSColor.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DSColor.separator, lineWidth: 1))
            if let footer {
                footer
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 1 行（余白 10/14、左に名前と説明、右に操作）。`error` は行の下に赤い文字で出す。
struct SettingsRow<Content: View>: View {
    let error: Text?
    let content: Content

    init(error: Text? = nil, @ViewBuilder content: () -> Content) {
        self.error = error
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                content
            }
            if let error {
                error
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(DSColor.statusError)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 行の名前（13pt）と説明（11.5pt・fg2）。
struct SettingsLabel: View {
    let title: Text
    var detail: Text? = nil
    var detailColor: Color = DSColor.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textPrimary)
            if let detail {
                detail
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 行の間の 1pt の区切り（まとまりの端から端まで）。
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(DSColor.separator).frame(height: 1)
    }
}

/// 分段（トラック segBg・角丸 6、選択中は操作面と薄い影、高さ 20・12pt）。
struct SettingsSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 20)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(DSColor.controlBackground)
                                    .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        // 標準の分段と同じく、焦点があれば ← → で選びを動かす。
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            guard let index = options.firstIndex(where: { $0.0 == selection }) else { return .ignored }
            let next = index + (press.key == .leftArrow ? -1 : 1)
            guard options.indices.contains(next) else { return .handled }
            selection = options[next].0
            return .handled
        }
        // 読み上げは標準の分段（選択肢の一つとして）と同じにする。
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.1).tag(option.0)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }
}

/// 内容の先頭に出すエラーの帯（L5: 角丸 9・エラーの淡い面と縁・12pt）。
struct SettingsErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.attentionMark(.error))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DSColor.attentionMark(.error), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// 設定の入力欄（高さ 22・角丸 5・入力面と 1pt の縁、12.5pt）。不正な値は赤い縁と 3pt の淡い輪（T6b）。
    func settingsField(width: CGFloat, isInvalid: Bool) -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 7)
            .frame(width: width, height: 22)
            .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isInvalid ? DSColor.attentionMark(.error) : DSColor.fieldBorder, lineWidth: 1)
            )
            .overlay {
                if isInvalid {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DSColor.attentionTint(.error), lineWidth: 3)
                        .padding(-3)
                }
            }
    }
}
