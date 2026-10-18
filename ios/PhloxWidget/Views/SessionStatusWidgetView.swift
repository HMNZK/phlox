import PhloxCore
import SwiftUI

/// WidgetKit のコンテナと分け、同じ View を描画テストでも使う。
struct SessionStatusWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: SharedSessionSummary?
    var rectangular = false

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if let summary {
                if rectangular { rectangularCard(summary) } else { homeCard(summary) }
            } else {
                emptyCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(GlanceStyle.text(dark: dark))
        .accessibilityElement(children: .combine)
    }

    private func status(_ summary: SharedSessionSummary) -> some View {
        HStack(spacing: 4) {
            GlanceStatusSymbol(state: summary.glanceState).frame(width: 14, height: 14)
            Text(summary.glanceState.label).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.footnote.weight(.bold))
    }

    private func updated(_ summary: SharedSessionSummary) -> some View {
        Text(summary.updatedAt, format: .relative(presentation: .named))
            .font(.caption)
            .foregroundStyle(rectangular ? .secondary : GlanceStyle.secondary(dark: dark))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func rectangularCard(_ summary: SharedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                status(summary)
                Spacer(minLength: 2)
                updated(summary)
            }
            Text(summary.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(summary.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityLabel("Phlox、\(summary.glanceState.label)、\(summary.title)、\(summary.detail)")
    }

    private func homeCard(_ summary: SharedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Phlox").font(.caption2.weight(.bold)).frame(height: 22)
                Spacer(minLength: 0)
                updated(summary)
            }
            status(summary)
                .foregroundStyle(GlanceStyle.ink(summary.glanceState, dark: dark))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    if summary.glanceState.hasWidgetFill {
                        Capsule().fill(GlanceStyle.fill(summary.glanceState, dark: dark))
                    }
                }
            Text(summary.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
            Text(summary.detail).font(.caption)
                .foregroundStyle(GlanceStyle.secondary(dark: dark)).lineLimit(1)
        }
        .accessibilityLabel("Phlox、\(summary.glanceState.label)、\(summary.title)、\(summary.detail)")
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phlox").font(.caption2.weight(.bold))
            if !rectangular { Spacer(minLength: 0) }
            Text("セッションはありません")
                .font(rectangular ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
            if !rectangular {
                Text("Phlox を開くと、最新の状態に更新されます")
                    .font(.caption).foregroundStyle(GlanceStyle.secondary(dark: dark))
            }
        }
    }
}
