import PhloxCore
import OSLog
import SwiftUI
import WidgetKit

struct SessionStatusEntry: TimelineEntry {
    let date: Date
    let summaries: [SharedSessionSummary]

    var primarySummary: SharedSessionSummary? {
        summaries.max { $0.updatedAt < $1.updatedAt }
    }
}

struct SessionStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionStatusEntry {
        SessionStatusEntry(date: Date(), summaries: [.placeholder])
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionStatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionStatusEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> SessionStatusEntry {
        let summaries: [SharedSessionSummary]
        if let store = SharedSessionStore() {
            do {
                summaries = try store.read()
            } catch {
                Logger(subsystem: "com.phlox.mobile.PhloxMobile.PhloxWidget", category: "Store")
                    .error("Failed to read shared session state: \(String(describing: error), privacy: .public)")
                summaries = []
            }
        } else {
            summaries = []
        }
        return SessionStatusEntry(date: Date(), summaries: summaries)
    }
}

struct SessionStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedSessionStore.widgetKind,
            provider: SessionStatusProvider()
        ) { entry in
            SessionStatusWidgetContainer(entry: entry)
        }
        .configurationDisplayName("セッションの状態")
        .description("直近に更新されたセッションの状態を表示します。")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

private extension SharedSessionSummary {
    static let placeholder = SharedSessionSummary(
        id: "placeholder", statusLabel: "完了", title: "refactor: ControlServer proxy",
        detail: "phlox", updatedAt: Date(), displayState: SessionGlanceState.done.rawValue
    )
}

private struct SessionStatusWidgetContainer: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: SessionStatusEntry

    var body: some View {
        SessionStatusWidgetView(summary: entry.primarySummary, rectangular: family == .accessoryRectangular)
            .widgetURL(entry.primarySummary.flatMap { SessionURL.make(sessionID: $0.id) })
            .containerBackground(for: .widget) {
                GlanceStyle.card(dark: colorScheme == .dark)
            }
    }
}
