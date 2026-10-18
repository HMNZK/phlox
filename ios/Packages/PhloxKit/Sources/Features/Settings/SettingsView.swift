import SwiftUI
import DesignSystemIOS
import LocalAuthentication
import PhloxCore

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let connectionViewModel: ConnectionSettingsViewModel
    private let onQRScan: () -> Void
    private let biometricTypeOverride: LABiometryType?
    private let reachability: Reachability
    private let lastFetchedAt: Date?

    public init(
        viewModel: SettingsViewModel,
        connectionViewModel: ConnectionSettingsViewModel,
        onQRScan: @escaping () -> Void,
        biometricTypeOverride: LABiometryType? = nil,
        reachability: Reachability = .unknown,
        lastFetchedAt: Date? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.connectionViewModel = connectionViewModel
        self.onQRScan = onQRScan
        self.biometricTypeOverride = biometricTypeOverride
        self.reachability = reachability
        self.lastFetchedAt = lastFetchedAt
    }

    public var body: some View {
        @Bindable var settings = viewModel.settings

        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                Text("設定")
                    .font(DSFont.largeTitle)
                    .foregroundStyle(IOSColor.text.primary)

                settingsConnectionSection
                if !connectionViewModel.hasConnectionConfig {
                    Text("接続先は、Mac の Phlox が表示する QR から設定します。")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DSSpacing.xs)
                }

                settingsSection("通知") {
                    SettingsToggleRow(
                        isOn: $settings.notificationsEnabled,
                        icon: "bell",
                        title: "プッシュ通知を受け取る",
                        subtitle: "セッションの更新を通知します"
                    )
                    Text("オフにすると、この iPhone への通知をすぐに止めます。")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, DSSpacing.xs)
                }

                settingsSection("セキュリティ") {
                    SettingsToggleRow(
                        isOn: $settings.faceIDEnabled,
                        icon: biometricIcon,
                        title: "\(biometricName) でロック",
                        subtitle: nil
                    )
                    Text("起動時とバックグラウンドからの復帰時に認証します。既定はオフで、オフにするとすぐに解除されます。")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DSSpacing.xs)
                }

                settingsSection("外観") {
                    HStack(spacing: DSSpacing.s) {
                        ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                            AppearanceChoice(
                                appearance: appearance,
                                isSelected: settings.appearance == appearance
                            ) {
                                settings.appearance = appearance
                            }
                        }
                    }
                    .padding(DSSpacing.s)
                    .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
                    Text("選ぶとすぐに切り替わります。")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, DSSpacing.xs)
                }

                settingsSection("このアプリについて") {
                    VStack(spacing: DSSpacing.s) {
                        aboutRow(label: "アプリ", value: viewModel.appName)
                        Divider().overlay(DSColor.separator)
                        aboutRow(label: "バージョン", value: viewModel.version)
                        Divider().overlay(DSColor.separator)
                        NavigationLink {
                            DotGothic16LicenseView()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                                Text("DotGothic16")
                                    .font(DSFont.body)
                                    .foregroundStyle(DSColor.textPrimary)
                                Spacer(minLength: DSSpacing.xs)
                                Text("SIL Open Font License 1.1")
                                    .font(DSFont.footnote)
                                    .foregroundStyle(DSColor.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(DSFont.caption.weight(.semibold))
                                    .foregroundStyle(IOSColor.text.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("DotGothic16 のライセンス、SIL Open Font License 1.1")
                    }
                    .padding(DSSpacing.m)
                    .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
                }
            }
            .padding(DSSpacing.l)
            .padding(.bottom, DSSpacing.m)
        }
        .background(IOSColor.bg.base)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(IOSColor.accent)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionLabel(title)
            content()
        }
    }

    private var settingsConnectionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionLabel("接続")
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(connectionTitle)
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(connectionTitleColor)
                    if connectionViewModel.hasConnectionConfig {
                        Text(connectionViewModel.currentConnection)
                            .font(DSFont.campMonoCaption)
                            .foregroundStyle(DSColor.textSecondary)
                            .textSelection(.enabled)
                        Text(lastFetchedDescription)
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.m)

                Divider().overlay(DSColor.separator).padding(.leading, DSSpacing.m)
                settingsConnectionAction("QR で再接続", icon: "qrcode.viewfinder", action: onQRScan)
                Divider().overlay(DSColor.separator).padding(.leading, 58)

                Button {
                    Task { await connectionViewModel.testConnection() }
                } label: {
                    HStack(spacing: DSSpacing.m) {
                        Image(systemName: ConnectionSettingsCopy.testConnectionIcon)
                            .font(DSFont.headline)
                            .frame(width: 30, height: 30)
                            .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: DSRadius.s))
                        Text(ConnectionSettingsCopy.testConnectionButtonTitle)
                            .font(DSFont.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.m)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(connectionViewModel.isTesting || !connectionViewModel.hasConnectionConfig)
                .accessibilityLabel(ConnectionSettingsCopy.testConnectionButtonTitle)

                settingsConnectionTestResult
            }
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))

            if isConnectionUnreachable {
                Text("Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。Mac を起こすと自動でつなぎ直します。")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSSpacing.xs)
            }
        }
        .onAppear { connectionViewModel.refresh() }
    }

    private func settingsConnectionAction(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: icon)
                    .font(DSFont.headline)
                    .frame(width: 30, height: 30)
                    .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: DSRadius.s))
                Text(title)
                    .font(DSFont.body)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(IOSColor.text.tertiary)
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var settingsConnectionTestResult: some View {
        if connectionViewModel.isTesting {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                ProgressView().tint(DSColor.textSecondary)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("確かめています…").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text("GET http://\(connectionViewModel.currentConnection)/sessions")
                        .font(DSFont.campMonoCaption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
            .padding(DSSpacing.m)
        } else {
            switch connectionViewModel.banner {
            case .none:
                EmptyView()
            case .success(let message):
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("接続できました").font(DSFont.headline).foregroundStyle(IOSColor.status.success)
                    Text(message).font(DSFont.campMonoCaption).foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .padding(DSSpacing.m)
            case .failure(let message):
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Mac に届きません").font(DSFont.headline).foregroundStyle(IOSColor.status.error)
                    Text(message).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                    Text("GET /sessions · 無応答").font(DSFont.campMonoCaption).foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .background(IOSColor.status.errorBackground, in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .padding(DSSpacing.m)
            }
        }
    }

    private var connectionTitle: String {
        if isConnectionUnreachable { return "Mac に届きません" }
        if connectionViewModel.lastTestWasReachable == true || reachability == .online { return "Mac と接続中" }
        return connectionViewModel.hasConnectionConfig ? "接続先を保存しました" : ConnectionSettingsCopy.notConnectedValue
    }

    private var connectionTitleColor: Color {
        isConnectionUnreachable ? IOSColor.status.error : IOSColor.status.success
    }

    private var isConnectionUnreachable: Bool {
        connectionViewModel.lastTestWasReachable == false || reachability == .unreachableHost
    }

    private var lastFetchedDescription: String {
        guard let lastFetchedAt else { return "セッション一覧の取得時刻はありません" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastFetchedAt) / 60))
        return minutes == 0 ? "最終取得 たった今" : "最終取得 \(minutes) 分前"
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.m) {
            Text(label)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: DSSpacing.s)
            Text(value)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var biometricName: String {
        if let biometricTypeOverride {
            return biometricTypeOverride == .touchID ? "Touch ID" : "Face ID"
        }
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    private var biometricIcon: String {
        biometricName == "Touch ID" ? "touchid" : DSIcon.faceID
    }
}

private struct SettingsToggleRow: View {
    @Binding var isOn: Bool
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            Image(systemName: icon)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 32, height: 32)
                .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: DSRadius.s))
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer(minLength: DSSpacing.xs)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(IOSColor.toggleOn)
        }
        .padding(DSSpacing.m)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
    }
}

private struct AppearanceChoice: View {
    let appearance: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DSSpacing.xs) {
                HStack(spacing: 0) {
                    Rectangle().fill(appearance == .dark ? Color.black : IOSColor.bg.appearancePreviewLight)
                    Rectangle().fill(appearance == .light ? Color.white : Color.black)
                }
                .frame(width: 54, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.border, lineWidth: 1))
                Text("\(isSelected ? "✓ " : "")\(appearance.label)")
                    .font(DSFont.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(DSSpacing.xs)
            .background(isSelected ? IOSColor.bg.fill : Color.clear, in: RoundedRectangle(cornerRadius: DSRadius.m))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.m).strokeBorder(isSelected ? DSColor.textPrimary : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
