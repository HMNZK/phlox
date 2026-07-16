import SwiftUI
import DesignSystemIOS
import Features
import PhloxCore

// アプリエントリポイント（極薄シェル）。
// Composition Root（AppEnvironment.live）を SwiftUI 環境に注入し、ルート分岐は AppRoot（E4-10）に委譲する。
@main
struct PhloxMobileApp: App {
    @UIApplicationDelegateAdaptor(PhloxAppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    @State private var pushCoordinator: PushCoordinator
    @State private var pushRegistrationService: PushRegistrationService?
    @State private var pendingPairingURLString: String?

    init() {
        DSNavigationChrome.installUIKitAppearanceIfNeeded()
        let pushCoordinator = PushCoordinator()
        _pushCoordinator = State(initialValue: pushCoordinator)

        let service: PushRegistrationService?
        if UITestingSupport.isEnabled {
            _environment = State(initialValue: AppEnvironment.uiTesting())
            service = nil
        } else {
            _environment = State(initialValue: AppEnvironment.live)
            service = PushRegistrationService(
                registrar: AppEnvironment.liveDeviceTokenRegistrar,
                bundleId: Bundle.main.bundleIdentifier ?? "com.phlox.mobile.PhloxMobile",
                environment: APNsEnvironment.current
            )
        }
        _pushRegistrationService = State(initialValue: service)

        appDelegate.pushCoordinator = pushCoordinator
        appDelegate.pushRegistrationService = service
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(
                pushCoordinator: pushCoordinator,
                pushRegistrationService: pushRegistrationService,
                pendingPairingURLString: $pendingPairingURLString
            )
            .environment(environment)
            .tint(DSColor.campAccentBright)
            .onOpenURL { url in
                pendingPairingURLString = PairingURLNormalizer.normalizedString(from: url)
            }
        }
    }
}
