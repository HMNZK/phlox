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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.l) {
                    header
                    if !viewModel.hasConnectionConfig {
                        PairingPreparationCard()
                    }
                    ConnectionSettingsSection(
                        viewModel: viewModel,
                        onQRScan: onQRScan,
                        showsQRButton: viewModel.hasConnectionConfig
                    )
                    if !viewModel.hasConnectionConfig {
                        Text("疎通テストは、QR コードを読み取って接続先を保存すると押せます。")
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, DSSpacing.xs)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, geometry.size.height < 700 ? DSSpacing.m : 20)
                .padding(.bottom, DSSpacing.xl)
            }
        }
        .background(IOSColor.bg.base)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.hasConnectionConfig {
                setupActions
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(ConnectionSettingsCopy.title)
                .font(DSFont.largeTitle)
                .foregroundStyle(DSColor.textPrimary)
            Text(ConnectionSettingsCopy.subtitle)
                .font(DSFont.subheadline)
                .lineSpacing(DSSpacing.xs)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupActions: some View {
        VStack(spacing: DSSpacing.chip) {
            Button(action: onQRScan) {
                Label("QR を読み取る", systemImage: "qrcode.viewfinder")
                    .font(DSFont.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(IOSColor.accentOnFill)
                    .background(IOSColor.accent, in: Capsule())
            }
            .buttonStyle(DSPressFeedbackStyle())

            Button(action: onQRScan) {
                Label("写真から読み取る", systemImage: "photo.on.rectangle")
                    .font(DSFont.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(IOSColor.accent)
            }
            .buttonStyle(DSPressFeedbackStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, DSSpacing.m)
        .padding(.bottom, DSSpacing.l)
        .background(IOSColor.bg.base.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [IOSColor.bg.base.opacity(0), IOSColor.bg.base],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
    }

}

/// 設定画面にも埋め込める、QR 接続の単一セクション。
public struct ConnectionSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: ConnectionSettingsViewModel
    @State private var rotatesTestIndicator = false
    private let onQRScan: () -> Void
    private let showsQRButton: Bool

    public init(
        viewModel: ConnectionSettingsViewModel,
        onQRScan: @escaping () -> Void,
        showsQRButton: Bool = true
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onQRScan = onQRScan
        self.showsQRButton = showsQRButton
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if showsQRButton {
                DSSectionLabel(ConnectionSettingsCopy.connectionSection)
            }
            VStack(spacing: 0) {
                currentConnection
                if showsQRButton {
                    Divider().overlay(DSColor.separator).padding(.horizontal, DSSpacing.l)
                    qrScanButton
                }
                Divider().overlay(DSColor.separator).padding(.horizontal, DSSpacing.l)
                connectionTestButton
                bannerView
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.bottom, DSSpacing.m)
            }
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.actionSheet, style: .continuous))
        }
        .onAppear { viewModel.refresh() }
    }

    private var currentConnection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.s) {
                if viewModel.hasConnectionConfig {
                    Text("接続先")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(viewModel.currentConnection)
                            .font(DSFont.campMonoCaption)
                            .foregroundStyle(DSColor.textSecondary)
                            .textSelection(.enabled)
                        if viewModel.lastTestWasReachable != nil {
                            Text(viewModel.connectionStatus)
                                .font(DSFont.footnote.weight(.semibold))
                                .foregroundStyle(connectionStatusColor)
                        }
                    }
                } else {
                    Text(ConnectionSettingsCopy.currentConnectionLabel)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: 0)
                    Text(ConnectionSettingsCopy.notConnectedValue)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.horizontal, DSSpacing.l)
            .padding(.vertical, DSSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ConnectionSettingsCopy.currentConnectionLabel)
            .accessibilityValue(viewModel.currentConnection)
        }
    }

    private var qrScanButton: some View {
        Button(action: onQRScan) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "qrcode.viewfinder")
                    .font(DSFont.headline)
                Text(viewModel.qrButtonTitle)
                    .font(DSFont.body)
                Spacer(minLength: 0)
                if viewModel.hasConnectionConfig {
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundStyle(IOSColor.text.tertiary)
                }
            }
            .foregroundStyle(viewModel.hasConnectionConfig ? DSColor.textPrimary : IOSColor.accentOnFill)
            .padding(.horizontal, DSSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityLabel(Text(viewModel.qrButtonTitle))
        .accessibilityAddTraits(.isButton)
    }

    private var connectionTestButton: some View {
        Button {
            Task { await viewModel.testConnection() }
        } label: {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: ConnectionSettingsCopy.testConnectionIcon)
                    .font(DSFont.headline)
                Text(ConnectionSettingsCopy.testConnectionButtonTitle)
                    .font(DSFont.body)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.l)
        }
        .buttonStyle(DSPressFeedbackStyle())
        .disabled(viewModel.isTesting || !viewModel.hasConnectionConfig)
        .accessibilityLabel(Text(ConnectionSettingsCopy.testConnectionButtonTitle))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var bannerView: some View {
        if viewModel.isTesting {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DSColor.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(!reduceMotion && rotatesTestIndicator ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: rotatesTestIndicator)
                    .onAppear { rotatesTestIndicator = !reduceMotion }
                    .onChange(of: reduceMotion) { _, reduced in rotatesTestIndicator = !reduced }
                    .onDisappear { rotatesTestIndicator = false }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("確かめています…")
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text("GET http://\(viewModel.currentConnection)/sessions")
                        .font(DSFont.campMonospaced(relativeTo: .footnote))
                        .foregroundStyle(DSColor.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        } else {
            switch viewModel.banner {
            case .none:
                EmptyView()
            case .success(let message):
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("接続できました")
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(IOSColor.status.success)
                    Text(message)
                        .font(DSFont.campMonospaced(relativeTo: .footnote))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .background(IOSColor.status.successBackground, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
            case .failure(let message):
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Mac に届きません")
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(IOSColor.status.error)
                    Text(message)
                        .font(DSFont.footnote)
                        .lineSpacing(DSSpacing.xxs)
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("GET /sessions · 無応答")
                        .font(DSFont.campMonospaced(relativeTo: .footnote))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .background(IOSColor.status.errorBackground, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
            }
        }
    }

    private var connectionStatusColor: Color {
        switch viewModel.lastTestWasReachable {
        case .none: DSColor.textSecondary
        case .some(true): IOSColor.status.success
        case .some(false): IOSColor.status.error
        }
    }
}

private struct PairingPreparationCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let steps = [
        ("Mac で Phlox を起動する", "メニューバーに Phlox のアイコンが出ていれば起動しています。"),
        ("Mac と iPhone を同じ Tailscale につなぐ", "両方で同じアカウントにログインし、オンにします。"),
        ("Mac で QR を表示する", "メニューバーの Phlox から「iPhone を接続…」を選びます。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text("先に Mac で準備すること")
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: DSSpacing.m) {
                        Text("\(index + 1)")
                            .font(DSFont.subheadline.weight(.bold))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(DSColor.fillSubtle, in: Circle())
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(step.0)
                                .font(DSFont.headline)
                                .foregroundStyle(DSColor.textPrimary)
                            Text(step.1)
                                .font(DSFont.subheadline)
                                .lineSpacing(DSSpacing.xs)
                                .foregroundStyle(DSColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.vertical, DSSpacing.m)
                    if index < steps.count - 1 {
                        Divider().overlay(DSColor.separator)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    macMenuExample
                        .padding(.leading, 56)
                        .padding(.trailing, DSSpacing.l)
                        .padding(.bottom, DSSpacing.m)
                }
            }
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var macMenuExample: some View {
        VStack(alignment: .trailing, spacing: DSSpacing.xs) {
            HStack(spacing: 10) {
                Spacer()
                Text("Wi‑Fi")
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(DSColor.textSecondary)
                Text("Phlox")
                    .font(DSFont.iosCaption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(IOSColor.accentOnFill)
                    .background(IOSColor.accent, in: RoundedRectangle(cornerRadius: DSRadius.s))
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(DSFont.iosCaption2)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(DSColor.fillSubtle)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Phlox · 稼働中")
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.s)
                Text("iPhone を接続…")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.accentOnFill)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(IOSColor.accent, in: RoundedRectangle(cornerRadius: DSRadius.s))
                Text("設定…")
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.s)
            }
            .padding(DSSpacing.xs)
            .frame(width: 178, alignment: .leading)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.border, lineWidth: 1))
            .shadow(color: DSColor.textPrimary.opacity(0.18), radius: 9, y: 6)
            .padding(.trailing, 22)
            .padding(.bottom, 10)
        }
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.m))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.m).strokeBorder(DSColor.border, lineWidth: 1))
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
