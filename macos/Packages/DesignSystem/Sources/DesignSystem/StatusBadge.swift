import SwiftUI
import AgentDomain

/// セッション状態の表示語彙（ラベル・色・アイコン・ヘルプ）を一元提供する名前空間。
/// StatusLabel / StatusDot がここから引く。
public enum StatusBadge {
    public static func englishLabel(for status: SessionStatus) -> String {
        switch status {
        case .starting:
            "starting"
        case .idle:
            "idle"
        case .running:
            "running"
        case .awaitingApproval:
            "awaiting"
        case .awaitingUserQuestion:
            "input"
        case .completed(let exitCode) where exitCode == 0:
            "done"
        case .completed:
            "exited"
        case .error:
            "error"
        }
    }

    public static func label(for status: SessionStatus) -> String {
        switch status {
        case .starting:
            "起動中"
        case .idle:
            "待機中"
        case .running:
            "実行中"
        case .awaitingApproval:
            "承認待ち"
        case .awaitingUserQuestion:
            "入力待ち"
        case .completed(let exitCode):
            "完了 (\(exitCode))"
        case .error:
            "エラー"
        }
    }

    public static func localizedLabel(for status: SessionStatus, locale: Locale) -> String {
        let isJapanese = locale.language.languageCode?.identifier == "ja"
        return isJapanese ? label(for: status) : englishLabel(for: status)
    }

    public static func color(for status: SessionStatus) -> Color {
        switch status {
        case .starting:
            DSColor.statusStarting
        case .idle:
            DSColor.statusIdle
        case .running:
            DSColor.statusRunning
        case .awaitingApproval, .awaitingUserQuestion:
            DSColor.statusAwaitingApproval
        case .completed:
            DSColor.statusCompleted
        case .error:
            DSColor.statusError
        }
    }

    /// 色覚多様性ケアのため、色と冗長な形（SF Symbol）で状態を符号化する。
    public static func iconName(for status: SessionStatus) -> String {
        switch status {
        case .starting:
            "circle.dotted"
        case .idle:
            "pause.circle"
        case .running:
            "play.circle.fill"
        case .awaitingApproval:
            "exclamationmark.bubble.fill"
        case .awaitingUserQuestion:
            "questionmark.bubble.fill"
        case .completed(let exitCode) where exitCode == 0:
            "checkmark.circle.fill"
        case .completed:
            "xmark.octagon.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    public static func helpText(for status: SessionStatus) -> String {
        switch status {
        case .starting, .idle, .running, .awaitingApproval, .awaitingUserQuestion, .completed:
            ""
        case .error(let message):
            message
        }
    }
}
