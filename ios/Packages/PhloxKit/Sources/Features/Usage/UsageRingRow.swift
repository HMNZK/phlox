import SwiftUI
import DesignSystemIOS
import PhloxCore

/// 入力欄の下に置く、使用量の 1 行ボタン。
public struct UsageRingRow: View {
    let viewModel: UsageViewModel

    @ScaledMetric(relativeTo: .caption) private var scaledRingDiameter: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var scaledRingStroke: CGFloat = 2.6
    @State private var isPopoverPresented: Bool

    public init(viewModel: UsageViewModel, isPopoverPresented: Bool = false) {
        self.viewModel = viewModel
        _isPopoverPresented = State(initialValue: isPopoverPresented)
    }

    public var body: some View {
        if viewModel.shouldShowRow {
            let agents = UsageRingPresentation.agents(from: viewModel.agents)
            Button {
                isPopoverPresented = true
            } label: {
                HStack(spacing: 8) {
                    agentLayout(agents)
                    Spacer(minLength: 0)
                    if let status = UsageRingPresentation.statusText(
                        isRefreshing: viewModel.isRefreshing,
                        isStale: viewModel.isStale,
                        asOf: viewModel.asOfDate
                    ) {
                        Text(verbatim: status)
                            .font(DSFont.iosCaption2)
                            .foregroundStyle(IOSColor.text.secondary)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: UsageRingPresentation.accessibilityLabel(
                agents: agents,
                isRefreshing: viewModel.isRefreshing,
                isStale: viewModel.isStale,
                asOf: viewModel.asOfDate
            )))
            .accessibilityHint(UsageRingPresentation.rowAccessibilityHint)
            .accessibilityIdentifier("UsageRingRow.button")
            .popover(
                isPresented: $isPopoverPresented,
                attachmentAnchor: .point(UnitPoint(x: 0.06, y: 0)),
                arrowEdge: .bottom
            ) {
                UsageRingPopover(
                    agents: agents,
                    isStale: viewModel.isStale,
                    asOf: viewModel.asOfDate,
                    now: viewModel.currentDate
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var ringDiameter: CGFloat { min(30, scaledRingDiameter) }
    private var ringStroke: CGFloat { min(4.3, scaledRingStroke) }

    @ViewBuilder
    private func agentLayout(_ agents: [UsageRingAgent]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                ForEach(agents) { agent in agentGroup(agent) }
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    if agents.indices.contains(0) { agentGroup(agents[0]) }
                    if agents.indices.contains(1) { agentGroup(agents[1]) }
                }
                if agents.indices.contains(2) {
                    HStack { agentGroup(agents[2]) }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func agentGroup(_ agent: UsageRingAgent) -> some View {
        HStack(spacing: 8) {
            DSAgentBrandIcon(kind: agent.kind, size: min(30, ringDiameter))
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                ForEach(agent.buckets) { bucket in
                    HStack(spacing: 3) {
                        UsageRing(
                            bucket: bucket,
                            isUnavailable: agent.isUnavailable,
                            diameter: ringDiameter,
                            lineWidth: ringStroke
                        )
                        if let ringLabel = bucket.ringLabel {
                            Text(verbatim: ringLabel)
                                .font(DSFont.iosCaption2.weight(
                                    bucket.isLow && !agent.isUnavailable ? .bold : .regular
                                ))
                                .foregroundStyle(
                                    bucket.isLow && !agent.isUnavailable
                                        ? IOSColor.status.caution
                                        : IOSColor.text.secondary
                                )
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct UsageRing: View {
    let bucket: UsageRingBucket
    let isUnavailable: Bool
    let diameter: CGFloat
    let lineWidth: CGFloat

    private var isLow: Bool { bucket.isLow && !isUnavailable }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            if !isUnavailable, let fraction = bucket.remainingFraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        isLow ? IOSColor.status.caution : IOSColor.text.secondary
    }

    private var trackColor: Color {
        isLow
            ? IOSColor.status.caution.opacity(0.24)
            : IOSColor.text.tertiary.opacity(0.32)
    }
}

private struct UsageRingPopover: View {
    let agents: [UsageRingAgent]
    let isStale: Bool
    let asOf: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isStale, let asOf {
                Text(verbatim: UsageRingPresentation.staleNotice(asOf: asOf))
                    .font(DSFont.iosCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(verbatim: UsageRingPresentation.popoverColumnHeaders[0]).frame(width: 82, alignment: .leading)
                Text(verbatim: UsageRingPresentation.popoverColumnHeaders[1]).frame(width: 84, alignment: .leading)
                Text(verbatim: UsageRingPresentation.popoverColumnHeaders[2]).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(DSFont.footnote.weight(.semibold))
            .foregroundStyle(IOSColor.text.secondary)

            ForEach(agents) { agent in
                agentSection(agent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .presentationBackground(IOSColor.bg.menu)
        .presentationCornerRadius(18)
    }

    private func agentSection(_ agent: UsageRingAgent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                DSAgentBrandIcon(kind: agent.kind, size: 16)
                    .accessibilityHidden(true)
                Text(verbatim: agent.kind.displayName)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(IOSColor.text.primary)
            }

            if agent.isUnavailable {
                Text(verbatim: UsageRingPresentation.unavailableText)
                    .font(DSFont.footnote)
                    .foregroundStyle(IOSColor.text.secondary)
            } else {
                ForEach(agent.buckets) { bucket in
                    bucketRow(bucket, agent: agent.kind)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(IOSColor.bg.separator)
                .frame(height: 1)
        }
    }

    private func bucketRow(_ bucket: UsageRingBucket, agent: AgentKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: bucket.label)
                .foregroundStyle(IOSColor.text.secondary)
                .frame(width: 82, alignment: .leading)
            Text(verbatim: UsageRingPresentation.valueText(for: bucket))
                .fontWeight(bucket.isLow ? .bold : .regular)
                .foregroundStyle(bucket.isLow ? IOSColor.status.caution : IOSColor.text.primary)
                .frame(width: 84, alignment: .leading)
            Text(verbatim: UsageRingPresentation.resetText(for: bucket, agent: agent, now: now) ?? "")
                .foregroundStyle(IOSColor.text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DSFont.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }
}
