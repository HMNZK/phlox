import Foundation
import UserNotifications
import AppKit
import AgentDomain
import DesignSystem

/// 11 通知: 通知の種類ごとの文言。「待ち」は承認待ち・質問待ちにだけ使う（完了は「作業が完了しました」）。
public enum SessionNotificationText {
    public enum Kind: Equatable, Sendable {
        case completed
        /// 承認を求めている対象（Chat の承認プロンプト）。分からないときは nil。
        case awaitingApproval(prompt: String?)
        /// 質問文。秘密の入力を求める質問は本文に中身を出さない。
        case awaitingQuestion(question: String?, isSecret: Bool)
        case error(message: String)
        /// 設定の「通知テスト」。
        case test
    }

    public static func title(_ kind: Kind, sessionName: String, locale: Locale) -> String {
        let key: String
        switch kind {
        case .completed: key = "作業が完了しました: %@"
        case .awaitingApproval: key = "承認待ち: %@"
        case .awaitingQuestion: key = "質問があります: %@"
        case .error: key = "エラーで止まりました: %@"
        case .test: return AppLocalizedString.string("Phlox の通知テスト", locale: locale)
        }
        return String(format: AppLocalizedString.string(key, locale: locale), sessionName)
    }

    public static func subtitle(_ kind: Kind, locale: Locale) -> String {
        kind == .test ? AppLocalizedString.string("設定 > 通知", locale: locale) : ""
    }

    public static func body(_ kind: Kind, locale: Locale) -> String {
        switch kind {
        case .completed: AppLocalizedString.string("次の指示を待っています。", locale: locale)
        case .awaitingApproval(let prompt): prompt ?? ""
        case .awaitingQuestion(let question, let isSecret):
            isSecret ? AppLocalizedString.string("入力を求めています", locale: locale) : question ?? ""
        case .error(let message): firstLine(message)
        case .test: AppLocalizedString.string("このように通知されます。", locale: locale)
        }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

public enum SessionCompletionNotifier {
    /// 通知の文言を引く表示言語。App が起動時にアプリ内の表示言語の設定を渡す。
    public nonisolated(unsafe) static var locale: () -> Locale = { .autoupdatingCurrent }

    public static func requestAuthorization() {
        guard canUseUserNotifications else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// ターンの完了（またはエラーでの停止）の通知。`status` が `.error` ならエラーの文言にする。
    public static func notifyCompleted(sessionName: String, status: SessionStatus? = nil) {
        if case .error(let message) = status {
            post(.error(message: message), sessionName: sessionName, identifierPrefix: "Phlox.sessionCompletion")
        } else {
            post(.completed, sessionName: sessionName, identifierPrefix: "Phlox.sessionCompletion")
        }
    }

    /// Codex が対話プロンプト(質問/承認)で入力待ちになったときの通知。
    /// 完了(running→idle)とは別系統で、ターン途中の質問でも鳴らすために使う。
    public static func notifyAwaitingInput(sessionName: String, kind: SessionNotificationText.Kind = .awaitingApproval(prompt: nil)) {
        post(kind, sessionName: sessionName, identifierPrefix: "Phlox.sessionAwaiting")
    }

    /// 設定の「通知テスト」。完了と同じ音・バナーの設定に従う。
    public static func notifyTest() {
        post(.test, sessionName: "", identifierPrefix: "Phlox.notificationTest")
    }

    private static func post(_ kind: SessionNotificationText.Kind, sessionName: String, identifierPrefix: String) {
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

        let locale = locale()
        let title = SessionNotificationText.title(kind, sessionName: sessionName, locale: locale)
        let subtitle = SessionNotificationText.subtitle(kind, locale: locale)
        let body = SessionNotificationText.body(kind, locale: locale)
        Task {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            // 音は NSSound 側で鳴らすため、通知側のサウンドは付けない（二重再生の回避）。
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
