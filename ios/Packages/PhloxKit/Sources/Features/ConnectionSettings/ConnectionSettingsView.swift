import SwiftUI
import DesignSystemIOS
import PhloxCore

/// QR コードだけで接続を確立・再設定する接続設定画面。
public struct ConnectionSettingsView: View {
    private let viewModel: ConnectionSettingsViewModel
    private let onQRScan: () -> Void

    public init(
        viewModel: ConnectionSettingsViewModel,
        onQRScan: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onQRScan = onQRScan
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                header
                ConnectionSettingsSection(viewModel: viewModel, onQRScan: onQRScan)
            }
            .padding(DSSpacing.l)
            .padding(.bottom, DSSpacing.m)
        }
        .background(DSColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(ConnectionSettingsCopy.title)
                .font(DSFont.title1)
                .foregroundStyle(DSColor.textPrimary)
            Text(ConnectionSettingsCopy.subtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

}

/// 設定画面にも埋め込める、QR 接続の単一セクション。
public struct ConnectionSettingsSection: View {
    @State private var viewModel: ConnectionSettingsViewModel
    private let onQRScan: () -> Void

    public init(
        viewModel: ConnectionSettingsViewModel,
        onQRScan: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onQRScan = onQRScan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionLabel(ConnectionSettingsCopy.connectionSection)
            currentConnection
            qrScanButton
            connectionTestButton
            bannerView
        }
        .onAppear { viewModel.refresh() }
    }

    private var currentConnection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(ConnectionSettingsCopy.currentConnectionLabel)
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)

            HStack(spacing: DSSpacing.s) {
                Image(systemName: "network")
                    .foregroundStyle(DSColor.accent)
                Text(viewModel.currentConnection)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
            .background(
                DSColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ConnectionSettingsCopy.currentConnectionLabel)
            .accessibilityValue(viewModel.currentConnection)
        }
    }

    private var qrScanButton: some View {
        Button(action: onQRScan) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "qrcode.viewfinder")
                Text(viewModel.qrButtonTitle)
                    .font(DSFont.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
            .foregroundStyle(DSColor.accent)
            .background(
                DSColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(viewModel.qrButtonTitle))
        .accessibilityAddTraits(.isButton)
    }

    private var connectionTestButton: some View {
        Button {
            Task { await viewModel.testConnection() }
        } label: {
            HStack(spacing: DSSpacing.s) {
                if viewModel.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: ConnectionSettingsCopy.testConnectionIcon)
                }
                Text(ConnectionSettingsCopy.testConnectionButtonTitle)
                    .font(DSFont.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
            .foregroundStyle(DSColor.accent)
            .background(
                DSColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTesting || !viewModel.hasConnectionConfig)
        .accessibilityLabel(Text(ConnectionSettingsCopy.testConnectionButtonTitle))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var bannerView: some View {
        switch viewModel.banner {
        case .none:
            EmptyView()
        case .success(let message):
            DSResultBanner(message: message, isError: false)
        case .failure(let message):
            DSResultBanner(message: message, isError: true)
        }
    }
}

#if DEBUG
#Preview("Initial") {
    ConnectionSettingsView(
        viewModel: ConnectionSettingsViewModel(
            tokenStore: InMemoryTokenStore(),
            configStore: InMemoryConnectionConfigStore(),
            probe: { _, _ in true }
        ),
        onQRScan: {}
    )
}
#endif
