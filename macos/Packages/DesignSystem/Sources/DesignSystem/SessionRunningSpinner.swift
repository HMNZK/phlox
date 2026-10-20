import SwiftUI

/// セッションの実行中を表す、オレンジ色の半円が等速で回転するスピナー。
public struct SessionRunningSpinner: View {
    public static let diameter: CGFloat = 18
    nonisolated static let period: TimeInterval = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init() {}

    public var body: some View {
        let _ = themeID
        Group {
            if reduceMotion {
                ring(angle: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    ring(angle: Self.angle(at: context.date))
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .fixedSize()
        .help(Text(verbatim: SessionDisplayState.running.localizedLabel(locale: locale)))
        .accessibilityHidden(true)
    }

    nonisolated static func angle(at date: Date) -> Double {
        let remainder = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let elapsed = remainder >= 0 ? remainder : remainder + period
        return elapsed / period * 360
    }

    private func ring(angle: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(DSColor.textSecondary.opacity(0.18), lineWidth: 2.5)
            Circle()
                .inset(by: 1.25)
                .trim(from: 0, to: 0.5)
                .stroke(Color(red: 1, green: 0.53, blue: 0), lineWidth: 2.5)
                .rotationEffect(.degrees(angle - 90))
        }
    }
}
