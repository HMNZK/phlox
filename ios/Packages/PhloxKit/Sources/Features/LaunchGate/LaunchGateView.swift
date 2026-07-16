import SwiftUI
import DesignSystemIOS
import PhloxCore

/// カンプ⑥の寸法トークン。design.md §⑥ / ios-design.html。
enum LaunchGateMetrics {
    /// ブランドロゴ正方形（84px）。
    static let logoSize: CGFloat = 84
    /// ロゴ内アイコン（42px）。
    static let logoIconSize: CGFloat = 42
    /// ロゴ角丸（22px = `DSRadius.dialog`）。
    static let logoCornerRadius = DSRadius.dialog
    /// Face ID 枠正方形（66px）。
    static let faceIDFrameSize: CGFloat = 66
    /// Face ID アイコン（34px）。
    static let faceIDIconSize: CGFloat = 34
    /// Face ID 枠角丸（16px = `DSRadius.actionSheet`）。
    static let faceIDCornerRadius = DSRadius.actionSheet
    /// Face ID 緑枠の線幅（2px = `DSSpacing.xxs`）。
    static let faceIDBorderWidth = DSSpacing.xxs
    /// タグライン上の Face ID セクション余白（54px）。
    static let faceIDTopSpacing: CGFloat = 54
    /// 下部「パスコードを使用」の下余白（42px）。
    static let passcodeBottomPadding: CGFloat = 42
    /// カンプのロゴ内花弁アイコン（SF Symbol）。
    static let logoSymbolName = "sparkle"
}

/// カンプ⑥の文言（テスト可能なコピー層）。
enum LaunchGateCopy {
    static let brandName = "Phlox"
    static let tagline = "エージェントを止めないリモコン"
    static let authenticating = "Face ID で認証中…"
    static let keychainFooter = "トークンは Keychain に保護されています。認証するまで Mac には接続しません。"
    static let passcodeFallback = "パスコードを使用"
}

/// 起動ゲート画面（カンプ⑥）。認証成功で `onUnlocked` を呼ぶ。
public struct LaunchGateView: View {
    @State private var viewModel: LaunchGateViewModel
    let onUnlocked: () -> Void

    public init(viewModel: LaunchGateViewModel, onUnlocked: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onUnlocked = onUnlocked
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                brandLogo
                    .padding(.bottom, DSSpacing.xl)

                Text(LaunchGateCopy.brandName)
                    .font(DSFont.title1.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)

                Text(LaunchGateCopy.tagline)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSSpacing.xs + DSSpacing.xxs)

                faceIDSection
                    .padding(.top, LaunchGateMetrics.faceIDTopSpacing)

                statusText
                    .padding(.top, DSSpacing.l + DSSpacing.xxs)

                Text(LaunchGateCopy.keychainFooter)
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DSSpacing.s)
                    .padding(.horizontal, DSSpacing.xl)
            }
            .padding(.horizontal, DSSpacing.xl + DSSpacing.m)

            Spacer()

            Button(LaunchGateCopy.passcodeFallback) {
                Task { await authenticate() }
            }
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.campAccentBright)
            .accessibilityIdentifier(AccessibilityID.launchGateUnlock)
            .padding(.bottom, LaunchGateMetrics.passcodeBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
        .task { await authenticate() }
    }

    private var brandLogo: some View {
        RoundedRectangle(cornerRadius: LaunchGateMetrics.logoCornerRadius, style: .continuous)
            .fill(DSGradient.brand)
            .frame(width: LaunchGateMetrics.logoSize, height: LaunchGateMetrics.logoSize)
            .overlay {
                Image(systemName: LaunchGateMetrics.logoSymbolName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: LaunchGateMetrics.logoIconSize, height: LaunchGateMetrics.logoIconSize)
                    .foregroundStyle(DSColor.textOnBrand)
            }
            .dsShadow(DSShadow.ctaGlow)
    }

    private var faceIDSection: some View {
        Button {
            Task { await authenticate() }
        } label: {
            RoundedRectangle(cornerRadius: LaunchGateMetrics.faceIDCornerRadius, style: .continuous)
                .strokeBorder(DSColor.statusRunning, lineWidth: LaunchGateMetrics.faceIDBorderWidth)
                .frame(width: LaunchGateMetrics.faceIDFrameSize, height: LaunchGateMetrics.faceIDFrameSize)
                .overlay {
                    Image(systemName: DSIcon.faceID)
                        .resizable()
                        .scaledToFit()
                        .frame(width: LaunchGateMetrics.faceIDIconSize, height: LaunchGateMetrics.faceIDIconSize)
                        .foregroundStyle(DSColor.statusRunning)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LaunchGateCopy.authenticating))
    }

    @ViewBuilder
    private var statusText: some View {
        if let message = viewModel.errorMessage {
            Text(message)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.statusError)
                .multilineTextAlignment(.center)
        } else {
            Text(LaunchGateCopy.authenticating)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    private func authenticate() async {
        await viewModel.authenticate()
        if viewModel.isUnlocked { onUnlocked() }
    }
}

#if DEBUG
#Preview("Authenticating") {
    LaunchGateView(viewModel: LaunchGateViewModel(authenticator: StubAuthenticator(allows: true)), onUnlocked: {})
}

#Preview("Failed") {
    let vm = LaunchGateViewModel(authenticator: StubAuthenticator(allows: false))
    vm.state = .failed("認証に失敗しました。もう一度お試しください。")
    return LaunchGateView(viewModel: vm, onUnlocked: {})
}
#endif
