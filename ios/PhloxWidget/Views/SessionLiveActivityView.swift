import PhloxCore
import SwiftUI

struct SessionLiveActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: SessionActivityAttributes.ContentState
    private var dark: Bool { colorScheme == .dark }
    private var status: SessionGlanceState { SessionGlanceState(activityStatus: state.status) }

    var body: some View {
        HStack(spacing: 12) {
            GlanceStatusSymbol(state: status)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .background(GlanceStyle.fill(status, dark: dark), in: Circle())
                .foregroundStyle(GlanceStyle.ink(status, dark: dark))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(status.label).font(.callout.weight(.bold))
                        .foregroundStyle(GlanceStyle.ink(status, dark: dark))
                    Text("· Phlox").font(.caption)
                        .foregroundStyle(GlanceStyle.secondary(dark: dark))
                }
                Text(state.sessionName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(state.summary).font(.footnote)
                    .foregroundStyle(GlanceStyle.secondary(dark: dark)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(GlanceStyle.text(dark: dark))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phlox、\(status.label)、\(state.sessionName)、\(state.summary)")
    }
}
