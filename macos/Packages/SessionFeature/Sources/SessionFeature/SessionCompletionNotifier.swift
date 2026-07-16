import Foundation
import UserNotifications
import AppKit
import AgentDomain

public enum SessionCompletionNotifier {
    public static func requestAuthorization() {
        guard canUseUserNotifications else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    public static func notifyCompleted(sessionName: String) {
        guard canUseUserNotifications else { return }

        // 完了音: 短時間に連続する複数通知では macOS が通知の content.sound を抑制する
        // （単発は鳴るが連続は鳴らない）。確実に・全CLI同じ音で鳴らすため NSSound で直接再生する。
        if NotificationSettings.isSoundEnabled() {
            Task { @MainActor in
                NSSound(named: "Glass")?.play()
            }
        }

        // バナー通知が無効なら UNUserNotification は出さない（音設定とは独立）。
        guard NotificationSettings.isBannerEnabled() else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = String(localized: "作業完了")
            content.body = String(localized: "\(sessionName) が待機中になりました")
            // 音は NSSound 側で鳴らすため、通知側のサウンドは付けない（二重再生の回避）。
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: "Phlox.sessionCompletion.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    /// Codex が対話プロンプト(質問/承認)で入力待ちになったときの通知。
    /// 完了(running→idle)とは別系統で、ターン途中の質問でも鳴らすために使う。
    public static func notifyAwaitingInput(sessionName: String) {
        guard canUseUserNotifications else { return }

        // 完了通知と同様、確実に鳴らすため NSSound で直接再生する。
        if NotificationSettings.isSoundEnabled() {
            Task { @MainActor in
                NSSound(named: "Glass")?.play()
            }
        }

        guard NotificationSettings.isBannerEnabled() else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = String(localized: "入力待ち")
            content.body = String(localized: "\(sessionName) が承認待ちです")
            // 音は NSSound 側で鳴らすため、通知側のサウンドは付けない（二重再生の回避）。
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: "Phlox.sessionAwaiting.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
