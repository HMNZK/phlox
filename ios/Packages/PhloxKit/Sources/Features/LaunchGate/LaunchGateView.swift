import SwiftUI
import DesignSystemIOS
import PhloxCore

/// カンプ⑥の寸法トークン。design.md §⑥ / ios-design.html。
enum LaunchGateMetrics {
    static let logoSize: CGFloat = 84
    static let logoCornerRadius = DSRadius.dialog
    static let unlockButtonHeight: CGFloat = 52
}

/// カンプ⑥の文言（テスト可能なコピー層）。
enum LaunchGateCopy {
    static let brandName = "Phlox"
    static let tagline = "エージェントを止めないリモコン"
    static let locked = "ロックされています"
    static let faceIDUnlock = "Face ID で解除"
    static let faceIDRetry = "もう一度 Face ID"
    static let authenticationFailed = "認証できませんでした"
    static let authenticationFailureBody = "Face ID で本人を確かめられませんでした。もう一度 Face ID を試すか、パスコードで解除してください。"
    static let keychainFooter = "トークンは Keychain に保護されています。認証するまで Mac には接続しません。"
    static let passcodeFallback = "パスコードを使用"

    static func unlockTitle(authenticationFailed: Bool) -> String {
        authenticationFailed ? faceIDRetry : faceIDUnlock
    }
}

/// 起動ゲート画面（カンプ⑥）。認証成功で `onUnlocked` を呼ぶ。
public struct LaunchGateView: View {
    @State private var viewModel: LaunchGateViewModel
    let onUnlocked: () -> Void
    private let automaticallyAuthenticates: Bool

    public init(
        viewModel: LaunchGateViewModel,
        onUnlocked: @escaping () -> Void,
        automaticallyAuthenticates: Bool = true
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onUnlocked = onUnlocked
        self.automaticallyAuthenticates = automaticallyAuthenticates
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                gateContent.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(IOSColor.bg.base)
        .task {
            guard automaticallyAuthenticates else { return }
            await authenticate()
        }
    }

    private var gateContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                brandLogo
                    .padding(.bottom, DSSpacing.l)

                Text(LaunchGateCopy.brandName)
                    .font(DSFont.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(DSColor.textPrimary)

                Text(LaunchGateCopy.tagline)
                    .font(DSFont.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSSpacing.xs + DSSpacing.xxs)

                if viewModel.errorMessage != nil {
                    authenticationFailureCard
                        .padding(.top, 44)
                } else {
                    statusText
                        .padding(.top, 32)
                }

            }
            .padding(.horizontal, DSSpacing.xl)

            Spacer()

            VStack(spacing: DSSpacing.s) {
                Button {
                    Task { await authenticate() }
                } label: {
                    HStack(alignment: .center, spacing: DSSpacing.s) {
                        Image(systemName: DSIcon.faceID)
                            .accessibilityHidden(true)
                        Text(LaunchGateCopy.unlockTitle(authenticationFailed: viewModel.errorMessage != nil))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .font(DSFont.headline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, DSSpacing.s)
                        .frame(maxWidth: .infinity, minHeight: LaunchGateMetrics.unlockButtonHeight)
                        .foregroundStyle(IOSColor.accentOnFill)
                        .background(IOSColor.accent, in: Capsule())
                }
                .buttonStyle(DSPressFeedbackStyle())
                .accessibilityIdentifier(AccessibilityID.launchGateUnlock)

                Button {
                    Task { await authenticate() }
                } label: {
                    Text(LaunchGateCopy.passcodeFallback)
                        .font(DSFont.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(IOSColor.accent)
                        .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
                        .contentShape(Rectangle())
                }

                Text(LaunchGateCopy.keychainFooter)
                    .font(DSFont.iosCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(DSSpacing.xxs)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DSSpacing.xs)
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.bottom, DSSpacing.l)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private var brandLogo: some View {
        RoundedRectangle(cornerRadius: LaunchGateMetrics.logoCornerRadius, style: .continuous)
            .fill(IOSColor.accent)
            .frame(width: LaunchGateMetrics.logoSize, height: LaunchGateMetrics.logoSize)
            .overlay {
                Text("P")
                    .font(DSFont.appBrandMark)
                    .foregroundStyle(IOSColor.accentOnFill)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock")
                    .font(DSFont.footnote.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(IOSColor.bg.card, in: Circle())
                    .overlay(Circle().strokeBorder(IOSColor.bg.base, lineWidth: 3))
                    .offset(x: 8, y: 8)
            }
    }

    @ViewBuilder
    private var statusText: some View {
        Text(viewModel.state == .authenticating ? "認証しています" : LaunchGateCopy.locked)
            .font(DSFont.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(DSColor.textPrimary)
    }

    private var authenticationFailureCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(LaunchGateCopy.authenticationFailed)
                .font(DSFont.subheadline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(IOSColor.status.error)
            Text(LaunchGateCopy.authenticationFailureBody)
                .font(DSFont.footnote)
                .lineSpacing(DSSpacing.xxs)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(IOSColor.status.errorBackground, in: RoundedRectangle(cornerRadius: 16))
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
