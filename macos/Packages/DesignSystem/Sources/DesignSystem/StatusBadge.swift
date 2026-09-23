import SwiftUI
import AgentDomain

/// セッション状態の表示語彙（ラベル・色・アイコン・ヘルプ）を一元提供する名前空間。
/// StatusLabel / StatusCapsuleBadge がここから引く。
///
/// 再設計（12 Design System）の語彙: 起動中・待機・実行中・承認待ち・質問待ち・完了・エラー・無応答。
/// 「入力待ち」「承認」「却下」「停止」は使わない。色が付くのは対応待ちの 4 状態だけ。
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
            "question"
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
            "待機"
        case .running:
            "実行中"
        case .awaitingApproval:
            "承認待ち"
        case .awaitingUserQuestion:
            "質問待ち"
        case .completed:
            "完了"
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
            "選択して許可するか決める"
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

    /// 状態の文言の色（`SessionDisplayState.color`）。
    public static func color(for status: SessionStatus) -> Color {
        SessionDisplayState.resolve(status).color
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

/// 対応待ち（承認待ち・質問待ち・エラー・無応答）の種別。完了の未読は含めない。
public enum AttentionKind: String, CaseIterable, Sendable, Equatable {
    case approval
    case question
    case error
    case stalled
}

/// 一覧（サイドバー・タイル・ヘッダ）に出す状態。`SessionStatus` に未読と無応答を重ねて決める。
public enum SessionDisplayState: Sendable, Equatable {
    case starting
    case idle
    case running
    case approval
    case question
    case doneUnread
    case done
    case error
    case stalled

    /// - Parameters:
    ///   - hasUnseenCompletion: ターン完了をまだ見ていない（完了の未読）。
    ///   - isStalled: 実行中のまま 120 秒反応がない（チャット型のみ。判定は呼び出し側）。
    public static func resolve(
        _ status: SessionStatus,
        hasUnseenCompletion: Bool = false,
        isStalled: Bool = false
    ) -> SessionDisplayState {
        switch status {
        case .starting: .starting
        case .idle: hasUnseenCompletion ? .doneUnread : .idle
        case .running: isStalled ? .stalled : .running
        case .awaitingApproval: .approval
        case .awaitingUserQuestion: .question
        case .completed: hasUnseenCompletion ? .doneUnread : .done
        case .error: .error
        }
    }

    /// 状態の文言の色。対応待ちの 4 状態だけ状態色、実行中は補助、ほかは弱い文字（無彩色）。
    public var color: Color {
        if let kind = attentionKind { return DSColor.attentionInk(kind) }
        return self == .running ? DSColor.textSecondary : DSColor.textTertiary
    }

    public var label: String {
        switch self {
        case .starting: "起動中"
        case .idle: "待機"
        case .running: "実行中"
        case .approval: "承認待ち"
        case .question: "質問待ち"
        case .doneUnread, .done: "完了"
        case .error: "エラー"
        case .stalled: "無応答"
        }
    }

    public var englishLabel: String {
        switch self {
        case .starting: "starting"
        case .idle: "idle"
        case .running: "running"
        case .approval: "awaiting"
        case .question: "question"
        case .doneUnread, .done: "done"
        case .error: "error"
        case .stalled: "unresponsive"
        }
    }

    public func localizedLabel(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ja" ? label : englishLabel
    }

    public var attentionKind: AttentionKind? {
        switch self {
        case .approval: .approval
        case .question: .question
        case .error: .error
        case .stalled: .stalled
        case .starting, .idle, .running, .doneUnread, .done: nil
        }
    }
}
