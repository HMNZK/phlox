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
            SessionStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.08, green: 0.09, blue: 0.13)
                }
        }
        .configurationDisplayName("Session Status")
        .description("Shows the latest Phlox session state.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

private struct SessionStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SessionStatusEntry

    var body: some View {
        if let summary = entry.primarySummary {
            switch family {
            case .accessoryRectangular:
                rectangularCard(summary)
            default:
                homeCard(summary)
            }
        } else {
            emptyCard
        }
    }

    private func rectangularCard(_ summary: SharedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.statusLabel.uppercased())
                .font(.caption2.weight(.bold))
            Text(summary.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(summary.detail)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("View ›")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.statusLabel), \(summary.title), \(summary.detail)")
    }

    private func homeCard(_ summary: SharedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: statusSymbol(for: summary.statusLabel))
                Text(summary.statusLabel.uppercased())
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor(for: summary.statusLabel))

            Text(summary.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer(minLength: 0)

            Text(summary.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            HStack {
                Spacer()
                Text("View ›")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.statusLabel), \(summary.title), \(summary.detail)")
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("NO SESSIONS", systemImage: "rectangle.stack")
                .font(.caption2.weight(.bold))
            Text("Open PhloxMobile")
                .font(.headline)
            Text("Session status will appear here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statusSymbol(for status: String) -> String {
        switch status {
        case "Finished": "checkmark.circle.fill"
        case "Error": "exclamationmark.triangle.fill"
        case "Waiting": "hourglass"
        default: "circle.dotted.circle.fill"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Finished": .green
        case "Error": .red
        case "Waiting": .orange
        default: .cyan
        }
    }
}

private extension SharedSessionSummary {
    static let placeholder = SharedSessionSummary(
        id: "placeholder",
        statusLabel: "Finished",
        title: "Add mobile widget",
        detail: "No Changes",
        updatedAt: Date()
    )
}
