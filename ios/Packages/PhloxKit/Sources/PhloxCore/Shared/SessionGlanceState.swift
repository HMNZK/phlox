import Foundation

/// アプリ外に渡す最小の表示状態。共有 SessionDisplayState の解決結果を保存する。
public enum SessionGlanceState: String, CaseIterable, Sendable {
    case starting, idle, running, approval, question, doneUnread, done, error, stalled, unknown

    public var label: String {
        switch self {
        case .starting: "起動中"
        case .idle: "待機"
        case .running: "実行中"
        case .approval: "承認待ち"
        case .question: "質問あり"
        case .doneUnread, .done: "完了"
        case .error: "エラー"
        case .stalled: "無応答"
        case .unknown: "状態不明"
        }
    }

    /// 実行中だけは SF Symbol ではなく円弧を描く。
    public var symbolName: String? {
        switch self {
        case .starting: "circle.dashed"
        case .idle: "pause.circle"
        case .running: nil
        case .approval: "exclamationmark.shield"
        case .question: "questionmark.bubble"
        case .doneUnread, .done: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        case .stalled: "hourglass"
        case .unknown: "questionmark.circle"
        }
    }

    public var hasWidgetFill: Bool { self == .approval || self == .question || self == .error }

    /// foreground は IOSColor と共通。idle / unknown は GlanceCatalog の dim。
    public func foregroundHex(dark: Bool, dynamicIsland: Bool = false) -> UInt32 {
        let dark = dark || dynamicIsland
        switch self {
        case .approval: return dark ? 0xFFB46E : 0xA8430A
        case .question: return dark ? 0x8DB9FF : 0x1555C0
        case .error: return dark ? 0xFF8C82 : 0xB8241C
        case .stalled: return dark ? 0xC9B6FF : 0x5B3FA8
        case .doneUnread, .done: return dark ? 0x6FD08C : 0x1F7A3A
        case .starting, .running: return dark ? 0xD4D4DA : 0x3A3A42
        case .idle, .unknown: return dark ? 0xAFAFB6 : 0x56565E
        }
    }

    public func background(dark: Bool) -> (hex: UInt32, opacity: Double) {
        switch self {
        case .approval: dark ? (0xFF9F0A, 0.22) : (0xFFEBD6, 1)
        case .question: dark ? (0x0A84FF, 0.24) : (0xE3EEFF, 1)
        case .error: dark ? (0xFF453A, 0.22) : (0xFDE7E5, 1)
        case .stalled: dark ? (0x9678E6, 0.24) : (0xF1ECFB, 1)
        case .doneUnread, .done: dark ? (0x34C759, 0.20) : (0xE3F4E8, 1)
        case .starting, .running: (0x767680, dark ? 0.30 : 0.14)
        case .idle, .unknown: (0x767680, dark ? 0.24 : 0.12)
        }
    }

    /// APNs の既存コードは維持。「exited」は非0終了の通知であり、別の「終了」は作らない。
    public init(activityStatus: String) {
        self = switch activityStatus {
        case "session_completed": .done
        case "approval_pending": .approval
        case "question_pending": .question
        case "session_error", "session_exited": .error
        case "session_stalled": .stalled
        default: .unknown
        }
    }
}
