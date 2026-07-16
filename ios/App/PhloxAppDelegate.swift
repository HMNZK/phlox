import Features
import OSLog
import PhloxCore
import UIKit
import UserNotifications

/// UIApplicationDelegate + UNUserNotificationCenterDelegate。
/// SwiftUI ライフサイクルの橋渡し（@UIApplicationDelegateAdaptor）。
final class PhloxAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// PhloxMobileApp.init が @UIApplicationDelegateAdaptor 経由で注入する。
    var pushRegistrationService: PushRegistrationService?
    var pushCoordinator: PushCoordinator?
    private var liveActivityCoordinator: Any?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        guard !UITestingSupport.isEnabled else { return true }
        if #available(iOS 17.2, *) {
            let coordinator = LiveActivityCoordinator()
            let registrar = LiveActivityPushRegistration()
            liveActivityCoordinator = coordinator
            Task {
                await coordinator.start(
                    registrar: registrar,
                    bundleId: Bundle.main.bundleIdentifier ?? "com.phlox.mobile.PhloxMobile",
                    environment: APNsEnvironment.current.rawValue
                )
            }
        }
        let notificationsEnabled = UserDefaultsAppSettingsStore().notificationsEnabled
        guard NotificationRegistrationPolicy.shouldRegister(
            notificationsEnabled: notificationsEnabled
        ) else { return true }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Logger.push.error("通知権限の要求に失敗: \(error.localizedDescription, privacy: .public)")
            }
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let service = pushRegistrationService else { return }
        Task {
            await service.updateDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.push.error("リモート通知の登録に失敗: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let userInfo = response.notification.request.content.userInfo
        Task { @MainActor [weak self] in
            self?.pushCoordinator?.handleNotificationTap(userInfo: userInfo)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private extension Logger {
    static let push = Logger(subsystem: "com.phlox.mobile.PhloxMobile", category: "Push")
}
