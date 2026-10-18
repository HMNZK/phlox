import PhloxCore

public extension SessionGlanceState {
    init(session: Session) {
        switch session.displayState {
        case .starting: self = .starting
        case .idle: self = .idle
        case .running: self = .running
        case .approval: self = .approval
        case .question: self = .question
        case .doneUnread: self = .doneUnread
        case .done: self = .done
        case .error: self = .error
        case .stalled: self = .stalled
        }
    }
}

public extension SharedSessionWriter {
    /// 状態解決はアプリ側だけで行い、拡張へは最小の表示値を渡す。
    func write(sessions: [Session]) throws {
        try write(summaries: sessions.map(Self.summary(for:)))
    }

    static func summary(for session: Session) -> SharedSessionSummary {
        let state = SessionGlanceState(session: session)
        let detail: String
        if case .error(let message) = session.status, !message.isEmpty {
            detail = message
        } else {
            detail = session.projectName ?? session.subtitle
        }
        return SharedSessionSummary(
            id: session.id, statusLabel: state.label,
            title: session.name, detail: detail,
            updatedAt: session.updatedAt, displayState: state.rawValue
        )
    }
}
