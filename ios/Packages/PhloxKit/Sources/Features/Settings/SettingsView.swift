import SwiftUI
import DesignSystemIOS

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let connectionViewModel: ConnectionSettingsViewModel
    private let onQRScan: () -> Void

    public init(
        viewModel: SettingsViewModel,
        connectionViewModel: ConnectionSettingsViewModel,
        onQRScan: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.connectionViewModel = connectionViewModel
        self.onQRScan = onQRScan
    }

    public var body: some View {
        @Bindable var settings = viewModel.settings

        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                ConnectionSettingsSection(
                    viewModel: connectionViewModel,
                    onQRScan: onQRScan
                )

                settingsSection("セキュリティ") {
                    DSToggle(
                        isOn: $settings.faceIDEnabled,
                        title: "Face ID / Touch ID でロック",
                        subtitle: "起動時とバックグラウンドからの復帰時に認証します"
                    )
                }

                settingsSection("通知") {
                    DSToggle(
                        isOn: $settings.notificationsEnabled,
                        title: "プッシュ通知を受け取る",
                        subtitle: "セッションの更新を通知します"
                    )
                }

                settingsSection("外観") {
                    Picker("外観", selection: $settings.appearance) {
                        ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("外観")
                }

                settingsSection("About") {
                    VStack(spacing: DSSpacing.s) {
                        aboutRow(label: "アプリ", value: viewModel.appName)
                        Divider().overlay(DSColor.separator)
                        aboutRow(label: "バージョン", value: viewModel.version)
                    }
                }
            }
            .padding(DSSpacing.l)
            .padding(.bottom, DSSpacing.m)
        }
        .background(DSColor.background)
        .navigationTitle("設定")
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSSectionLabel(title)
            content()
                .padding(DSSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    DSColor.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .strokeBorder(DSColor.border, lineWidth: 1)
                )
        }
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
}
