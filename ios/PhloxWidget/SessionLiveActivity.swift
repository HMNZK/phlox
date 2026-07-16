import ActivityKit
import PhloxCore
import SwiftUI
import WidgetKit

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLiveActivityView(state: context.state)
                .activityBackgroundTint(Color(red: 0.08, green: 0.09, blue: 0.13))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(for: context.state.status))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.sessionName).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.summary).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: symbol(for: context.state.status))
            } compactTrailing: {
                Text(shortStatus(context.state.status))
            } minimal: {
                Image(systemName: symbol(for: context.state.status))
            }
        }
    }

    private func symbol(for status: String) -> String {
        switch status {
        case "session_completed": "checkmark.circle.fill"
        case "approval_pending": "exclamationmark.circle.fill"
        default: "circle.dotted.circle.fill"
        }
    }

    private func shortStatus(_ status: String) -> String {
        status == "session_completed" ? "Done" : "Wait"
    }
}

private struct SessionLiveActivityView: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.status == "session_completed" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.sessionName).font(.headline).lineLimit(1)
                Text(state.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.sessionName), \(state.summary)")
    }
}
