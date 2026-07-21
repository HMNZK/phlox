import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum SharedSessionWriterError: Error, Equatable {
    case appGroupUnavailable
}

public struct SharedSessionWriter {
    private let store: SharedSessionStore?

    public init(store: SharedSessionStore? = SharedSessionStore()) {
        self.store = store
    }

    public func write(sessions: [Session]) throws {
        guard let store else { throw SharedSessionWriterError.appGroupUnavailable }
        let summaries = sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(Self.summary(for:))
        try store.write(summaries)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedSessionStore.widgetKind)
        #endif
    }

    public static func summary(for session: Session) -> SharedSessionSummary {
        let presentation = presentation(for: session.status)
        return SharedSessionSummary(
            id: session.id,
            statusLabel: presentation.statusLabel,
            title: session.name,
            detail: session.subtitle.isEmpty ? presentation.fallbackDetail : session.subtitle,
            updatedAt: session.updatedAt
        )
    }

    private static func presentation(for status: SessionStatus) -> (
        statusLabel: String,
        fallbackDetail: String
    ) {
        switch status {
        case .starting:
            ("Starting", "Preparing session")
        case .idle:
            ("Waiting", "Ready")
        case .running:
            ("Running", "In progress")
        case .awaitingApproval:
            ("Waiting", "Approval required")
        case .awaitingUserQuestion:
            ("Waiting", "Input required")
        case .completed(let exitCode):
            exitCode == 0 ? ("Finished", "No Changes") : ("Finished", "Exit \(exitCode)")
        case .error(let message):
            ("Error", message.isEmpty ? "Session failed" : message)
        }
    }
}
