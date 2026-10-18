import ActivityKit
import PhloxCore
import SwiftUI
import WidgetKit

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLiveActivityContainer(state: context.state)
                .widgetURL(SessionURL.make(sessionID: context.state.sessionId))
        } dynamicIsland: { context in
            let status = SessionGlanceState(activityStatus: context.state.status)
            let ink = GlanceStyle.ink(status, dark: true, island: true)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        GlanceStatusSymbol(state: status).frame(width: 22, height: 22)
                        Text(status.label).font(.caption.weight(.bold))
                    }
                    .foregroundStyle(ink)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.label)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Phlox").font(.caption).foregroundStyle(GlanceStyle.secondary(dark: true))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.sessionName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .foregroundStyle(GlanceStyle.text(dark: true))
                        Text(context.state.summary).font(.caption).lineLimit(2)
                            .foregroundStyle(GlanceStyle.secondary(dark: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                GlanceStatusSymbol(state: status).frame(width: 20, height: 20).foregroundStyle(ink)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(status.label).font(.caption.weight(.bold)).foregroundStyle(ink)
            } minimal: {
                GlanceStatusSymbol(state: status).frame(width: 20, height: 20).foregroundStyle(ink)
            }
            .widgetURL(SessionURL.make(sessionID: context.state.sessionId))
            .keylineTint(ink)
        }
    }
}

private struct SessionLiveActivityContainer: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        SessionLiveActivityView(state: state)
            .activityBackgroundTint(GlanceStyle.card(dark: colorScheme == .dark).opacity(0.82))
            .activitySystemActionForegroundColor(GlanceStyle.text(dark: colorScheme == .dark))
    }
}
