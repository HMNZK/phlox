import SwiftUI

/// 円を0.5秒で描き、0.1秒待ってからチェックを0.3秒で描く。
struct SessionSuccessProgress: Equatable {
    let ring: CGFloat
    let tick: CGFloat
    var isComplete: Bool { tick >= 1 }

    static let complete = Self(ring: 1, tick: 1)

    static func at(elapsed: TimeInterval) -> Self {
        Self(
            ring: min(1, max(0, elapsed / 0.5)),
            tick: min(1, max(0, (elapsed - 0.6) / 0.3))
        )
    }
}

/// 未確認の完了へ切り替わったときに一度だけ描画する。
struct SessionSuccessIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var isFinished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isFinished)) { context in
            let progress = reduceMotion || isFinished
                ? SessionSuccessProgress.complete
                : .at(elapsed: context.date.timeIntervalSince(startedAt))
            SessionSuccessDrawing(progress: progress)
                .onChange(of: progress.isComplete, initial: true) { _, complete in
                    if complete { isFinished = true }
                }
        }
    }
}

struct SessionSuccessDrawing: View {
    let progress: SessionSuccessProgress
    private var green: Color {
        DSColor.isDark ? Color(red: 0.29, green: 0.82, blue: 0.58)
            : Color(red: 0.05, green: 0.58, blue: 0.34)
    }
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        ZStack {
            Circle()
                .fill(green.opacity(0.10))
                .overlay { Circle().strokeBorder(green.opacity(0.42), lineWidth: 0.7) }
            ring.stroke(DSColor.textSecondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ring.stroke(green.opacity(progress.ring), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            SuccessTick()
                .trim(from: 0, to: progress.tick)
                .stroke(green, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
        .frame(width: SessionRunningSpinner.diameter, height: SessionRunningSpinner.diameter)
    }

    private var ring: some Shape {
        Circle().inset(by: 2.9).trim(from: 0, to: progress.ring)
            .rotation(.degrees(-90))
    }
}

private struct SuccessTick: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.37))
        return path
    }
}
