import SwiftUI
import DesignSystem

/// 復元中の接続待ちを示すレーダー状インジケーター。
public struct ChatConnectingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat

    public init(size: CGFloat = 128) {
        self.size = size
    }

    public var body: some View {
        Group {
            if reduceMotion {
                staticIndicator
            } else {
                animatedIndicator
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var animatedIndicator: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let maximumRadius = min(canvasSize.width, canvasSize.height) / 2
                let accent = DSColor.chatAccent

                for index in 0..<3 {
                    let phase = ((time * 0.55) + Double(index) / 3)
                        .truncatingRemainder(dividingBy: 1)
                    let radius = maximumRadius * CGFloat(0.15 + 0.85 * phase)
                    let opacity = (1 - phase) * 0.45
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(accent.opacity(opacity)),
                        lineWidth: 2
                    )
                }

                let arcRadius = maximumRadius * 0.5
                let rotation = Angle(radians: time * 2.6)
                var primaryArc = Path()
                primaryArc.addArc(
                    center: center,
                    radius: arcRadius,
                    startAngle: rotation,
                    endAngle: rotation + .degrees(110),
                    clockwise: false
                )
                context.stroke(
                    primaryArc,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )

                var secondaryArc = Path()
                secondaryArc.addArc(
                    center: center,
                    radius: arcRadius,
                    startAngle: rotation + .degrees(180),
                    endAngle: rotation + .degrees(250),
                    clockwise: false
                )
                context.stroke(
                    secondaryArc,
                    with: .color(accent.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                let pulse = CGFloat(0.5 + 0.5 * sin(time * 2.2))
                let dotRadius = maximumRadius * (0.09 + 0.035 * pulse)
                let dotRect = CGRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(accent.opacity(0.9))
                )
            }
        }
    }

    private var staticIndicator: some View {
        ZStack {
            Circle()
                .stroke(DSColor.chatAccent.opacity(0.22), lineWidth: 2)
                .frame(width: size * 0.82, height: size * 0.82)
            Circle()
                .stroke(DSColor.chatAccent.opacity(0.5), lineWidth: 2)
                .frame(width: size * 0.5, height: size * 0.5)
            Circle()
                .fill(DSColor.chatAccent.opacity(0.9))
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }
}
