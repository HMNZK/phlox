import SwiftUI

struct CometLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProgressView("以前のメッセージを読み込み中")
            .progressViewStyle(CometStyle(reduceMotion: reduceMotion))
            .frame(width: 22, height: 22)
            .accessibilityLabel("以前のメッセージを読み込み中")
            .accessibilityIdentifier("ChatTranscript.historyLoading")
    }

    private struct CometStyle: ProgressViewStyle {
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            Ring(reduceMotion: reduceMotion)
        }
    }

    struct Ring: View {
        let reduceMotion: Bool

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [.clear, Color(white: 0.5), Color(white: 0.95)], center: .center),
                        lineWidth: 2
                    )
                    .rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
            }
        }
    }
}
