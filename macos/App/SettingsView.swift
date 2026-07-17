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
    /// モバイル専用トークンの再発行・QR ペアリング VM。初期化前（composition 未完了）は nil。
    let mobileToken: MobileTokenViewModel?

    @AppStorage(NotificationSettings.bannerKey) private var bannerNotificationEnabled = true
    @AppStorage(NotificationSettings.soundKey) private var completionSoundEnabled = true

    @AppStorage(UsageSettings.autoRefreshKey) private var usageAutoRefresh = true
    @AppStorage(UsageSettings.claudeScrapeKey) private var claudeScrape = true
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailableUsage = false

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

            Form {
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
                    ForEach(agentCatalog.allDescriptors, id: \.ref) { descriptor in
                        BypassToggleRow(descriptor: descriptor)
                    }
                } header: {
                    Text("権限")
                } footer: {
                    Text("変更は次回セッション開始から反映されます。OFF の場合、コマンド承認プロンプトが出るため自律実行が止まり得ます。ON（フルアクセス／bypass）は承認なしでコマンドを実行します。信頼できるプロジェクトでのみ有効にしてください。")
                }

                if let mobileToken, MobileConnectionGuidePolicy.showsSettingsConnectionSection {
                    MobileTokenSection(viewModel: mobileToken)
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
                    .buttonStyle(RichButtonStyle())
                    .focusEffectDisabled()
                } header: {
                    Text("通知")
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
                    Toggle(isOn: Binding(
                        get: { appUpdater.automaticallyChecksForUpdates },
                        set: { appUpdater.automaticallyChecksForUpdates = $0 }
                    )) {
                        Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath")
                    }
                    Button("今すぐ確認") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(RichButtonStyle())
                    .disabled(!appUpdater.canCheckForUpdates)
                    .focusEffectDisabled()
                } header: {
                    Text("アップデート")
                }

                Section {
                    LabeledContent("アプリ", value: AppFlavor.current.displayName)
                    LabeledContent("バージョン", value: appVersion)
                    LabeledContent("ビルド", value: buildNumber)
                } header: {
                    Text("このアプリについて")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .tint(DSColor.accent)
            .toggleStyle(AccentSwitchToggleStyle())
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

    // MARK: - テーマ選択行（ホバー対応）

    private struct BypassToggleRow: View {
        let descriptor: AgentDescriptor
        @AppStorage private var isEnabled: Bool

        init(descriptor: AgentDescriptor) {
            self.descriptor = descriptor
            _isEnabled = AppStorage(wrappedValue: true, descriptor.bypassKey)
        }

        var body: some View {
            Toggle(isOn: $isEnabled) {
                Label("\(descriptor.displayName): フルアクセス（bypass）", systemImage: descriptor.symbolName)
            }
        }
    }

    /// モバイル専用トークンの再発行・QR ペアリング UI。
    /// `@ObservedObject` を非 optional で受けるため、optional な VM は親で `if let` してから渡す。
    private struct MobileTokenSection: View {
        @ObservedObject var viewModel: MobileTokenViewModel
        @State private var confirmRegenerate = false

        var body: some View {
            Section {
                Button("再発行", role: .destructive) {
                    confirmRegenerate = true
                }
                if let disabledReason = viewModel.pairingQRDisabledReason {
                    Text(disabledReason)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Button {
                    viewModel.showPairingQR()
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
                Text("iPhone アプリで QR コードを読み取ると、同一 Tailscale ネットワーク経由で接続できます。再発行すると古いトークンは無効になり、接続済みの端末は再度 QR コードの読み取りが必要になります。")
            }
            .confirmationDialog(
                "トークンを再発行しますか？",
                isPresented: $confirmRegenerate,
                titleVisibility: .visible
            ) {
                Button("再発行", role: .destructive) {
                    Task { await viewModel.regenerate() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("古いトークンは即座に無効になります。接続済みの iPhone では再度 QR コードの読み取りが必要です。")
            }
        }
    }

    /// テーマ選択行。ホバーで背景ハイライト＋手のカーソルを出し、クリック可能と分かるようにする。
    private struct ThemeRowView: View {
        let theme: AppTheme
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: DSSpacing.m) {
                    ThemeSwatchStrip(theme: theme)
                    Text(theme.name)
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

    /// テーマの代表色（背景 + ANSI 6色 + 前景）を帯で見せるプレビュー。
    private struct ThemeSwatchStrip: View {
        let theme: AppTheme

        var body: some View {
            let colors: [Color] = [
                theme.terminalBackground.color,
                theme.ansi[1].color, theme.ansi[2].color, theme.ansi[3].color,
                theme.ansi[4].color, theme.ansi[5].color, theme.ansi[6].color,
                theme.terminalForeground.color,
            ]
            return HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Rectangle()
                        .fill(color)
                        .frame(width: 9, height: 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    /// リッチなボタンスタイル。半透明ダークのピルに、上方向のハイライトグラデ・
    /// ヘアライン枠・ドロップシャドウを重ねて立体感を出す。hover で枠をアクセント色に光らせる。
    /// 寸法・角丸・フォントはデザイントークンで統一。状態（hover）を持つため内部 View に委譲する。
    private struct RichButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            StyledBody(configuration: configuration)
        }

        private struct StyledBody: View {
            let configuration: Configuration
            @Environment(\.isEnabled) private var isEnabled
            @State private var isHovering = false

            private var shape: RoundedRectangle {
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
            }

            var body: some View {
                configuration.label
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.vertical, DSSpacing.s)
                    .padding(.horizontal, DSSpacing.l)
                    .background {
                        ZStack {
                            // 半透明ダークのベース（背景が透ける）
                            shape.fill(.black.opacity(fillOpacity))
                            // アプリのカラースキーマのグラデ（accent→ gradient 色）を薄く重ねる
                            shape.fill(DSColor.newSessionGradient)
                                .opacity(gradientOpacity)
                            // 上から下へ淡いハイライト：光が上から当たったような艶
                            shape.fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            // テーマグラデのヘアライン枠（hover で発光）
                            shape.strokeBorder(DSColor.newSessionGradient, lineWidth: 1)
                                .opacity(borderOpacity)
                        }
                    }
                    .clipShape(shape)
                    .dsShadow(.card)
                    .opacity(isEnabled ? 1 : 0.45)
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .contentShape(shape)
                    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
                    .onHover { hovering in
                        isHovering = hovering && isEnabled
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .onDisappear {
                        if isHovering { NSCursor.pop() }
                    }
            }

            /// 押下で最も濃く、hover でやや濃く。半透明ダークの濃度を状態で変える。
            private var fillOpacity: Double {
                guard isEnabled else { return 0.32 }
                if configuration.isPressed { return 0.5 }
                return isHovering ? 0.42 : 0.32
            }

            /// ダーク上に重ねるテーマグラデの濃度。hover／押下で強める。
            private var gradientOpacity: Double {
                guard isEnabled else { return 0.18 }
                if configuration.isPressed { return 0.40 }
                return isHovering ? 0.34 : 0.22
            }

            /// グラデ枠の濃度。通常は控えめ、hover で発光させる。
            private var borderOpacity: Double {
                guard isEnabled else { return 0.40 }
                return isHovering ? 0.95 : 0.60
            }
        }
    }

    /// 画像準拠のピル型スイッチ。ON=アクセント色トラック＋白ノブ右、OFF=灰トラック＋白ノブ左。
    /// ON 色はテーマの accent を使うためカラースキーマ／テーマ切替に追従する。
    /// クリック／キーボード操作を保つため Button をラベルに使う。
    private struct AccentSwitchToggleStyle: ToggleStyle {
        private let trackWidth: CGFloat = 34
        private let trackHeight: CGFloat = 20
        private let knobInset: CGFloat = 2
        private let offColor = DSColor.border

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: DSSpacing.m) {
                configuration.label
                Spacer(minLength: DSSpacing.m)
                Button {
                    configuration.isOn.toggle()
                } label: {
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(configuration.isOn ? DSColor.accent : offColor)
                            .frame(width: trackWidth, height: trackHeight)
                        Circle()
                            .fill(.white)
                            .frame(width: trackHeight - knobInset * 2, height: trackHeight - knobInset * 2)
                            .padding(knobInset)
                            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isOn)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
