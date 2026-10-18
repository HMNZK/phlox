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

    public func write(summaries: [SharedSessionSummary]) throws {
        guard let store else { throw SharedSessionWriterError.appGroupUnavailable }
        try store.write(summaries)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedSessionStore.widgetKind)
        #endif
    }
}
