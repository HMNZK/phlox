import SwiftUI

/// 割合を示す短い横棒（使用量の残りなど）。値の文字は持たないので、読み上げは呼び出し側で付ける。
public struct DSMeterBar: View {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = min(1, max(0, fraction))
        self.tint = tint
    }

    public var body: some View {
        Capsule()
            .fill(DSColor.segmentTrack)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(tint).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: DSLayout.progressBarHeight)
            .accessibilityHidden(true)
    }
}
