import SwiftUI

/// 接続待ち用のブランド配色リッチアニメーション（QR ペアリング直後の「接続中…」等）。
/// レーダー状に広がる同心リング＋回転する2本の円弧＋中心の脈動スパークを `Canvas`＋`TimelineView(.animation)`
/// で毎フレーム描画する。Reduce Motion 時は静的な同心円＋中心ドットにフォールバックする。
public struct DSConnectingIndicator: View {
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
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let maxR = min(canvasSize.width, canvasSize.height) / 2
                let accent = DSColor.campAccentBright

                // レーダー状の同心リング（3本・位相差で連続的に外へ広がりながらフェード）。
                for i in 0..<3 {
                    let phase = ((t * 0.55) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let r = maxR * CGFloat(0.15 + 0.85 * phase)
                    let alpha = (1 - phase) * 0.45
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(alpha)), lineWidth: 2)
                }

                // 回転する円弧（メイン＋反対側の淡い1本）。
                let arcR = maxR * 0.5
                let rot = Angle(radians: t * 2.6)
                var arc = Path()
                arc.addArc(center: center, radius: arcR, startAngle: rot, endAngle: rot + .degrees(110), clockwise: false)
                context.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                var arc2 = Path()
                arc2.addArc(center: center, radius: arcR, startAngle: rot + .degrees(180), endAngle: rot + .degrees(250), clockwise: false)
                context.stroke(arc2, with: .color(accent.opacity(0.4)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // 中心の脈動スパーク。
                let pulse = CGFloat(0.5 + 0.5 * sin(t * 2.2))
                let dotR = maxR * (0.09 + 0.035 * pulse)
                let dotRect = CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(accent.opacity(0.9)))
            }
        }
    }

    private var staticIndicator: some View {
        ZStack {
            Circle()
                .stroke(DSColor.campAccentBright.opacity(0.22), lineWidth: 2)
                .frame(width: size * 0.82, height: size * 0.82)
            Circle()
                .stroke(DSColor.campAccentBright.opacity(0.5), lineWidth: 2)
                .frame(width: size * 0.5, height: size * 0.5)
            Circle()
                .fill(DSColor.campAccentBright.opacity(0.9))
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }
}

#if DEBUG
#Preview("DSConnectingIndicator") {
    DSConnectingIndicator(size: 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
}
#endif
