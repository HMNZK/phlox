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
            "入力待ち"
        case .running:
            "実行中"
        case .awaitingApproval:
            "承認待ち"
        case .awaitingUserQuestion:
            "回答待ち"
        case .completed:
            "停止"
        case .error:
            "エラー"
        }
    }

    /// 次に取れる操作の一言。対応が必要な状態にだけ存在する。
    public static func nextActionHint(for status: SessionStatus) -> String? {
        switch status {
        case .starting, .idle, .running:
            nil
        case .awaitingApproval:
            "選択して承認内容を確認する"
        case .awaitingUserQuestion:
            "選択して質問に回答する"
        case .completed(let exitCode):
            "終了コード \(exitCode)。再開または削除する"
        case .error:
            "選択して原因を確認し、再開または削除する"
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
        var text = label(for: status)
        if let hint = nextActionHint(for: status) {
            text += " — " + hint
        }
        if case .error(let message) = status {
            text += "\n" + message
        }
        return text
    }
}
