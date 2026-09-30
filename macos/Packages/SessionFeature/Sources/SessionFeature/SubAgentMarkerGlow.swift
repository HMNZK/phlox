import SwiftUI
import AgentDomain
import DesignSystem

/// 会話内のサブエージェントカードの表示判定（純関数）。
enum SubAgentMarkerPresentation {
    /// 右端の状態の文字を出すか。実行中は回転マークと枠の光で示すので文字は出さない。
    static func showsStatusLabel(for status: SubAgentStatus) -> Bool { status != .running }

    enum Glow: Equatable { case none, staticHighlight, comet }

    /// 実行中だけ枠を光らせる。動きを減らす設定では走らせず静かな強調にとどめる。
    static func glow(for status: SubAgentStatus, reduceMotion: Bool) -> Glow {
        guard status == .running else { return .none }
        return reduceMotion ? .staticHighlight : .comet
    }

    /// 光の点が枠を進む速さ（pt/秒）と、尾の長さ（pt）。
    static let speed: Double = 260
    static let tailLength: Double = 90
    static let tailSegments = 6
    /// にじみを付ける、尾の先頭側の割合。
    static let bloomShare = 0.4

    /// 光を描く最小の周長（pt）。これより小さい枠（幅・高さが 0 に近い）では描かない。
    static let minPerimeter: Double = 16

    /// 幅・高さを 0 以上、角丸半径を 0...短辺の半分に収める。
    static func clamped(size: CGSize, cornerRadius: CGFloat) -> (width: Double, height: Double, radius: Double) {
        let w = size.width.isFinite ? max(0, Double(size.width)) : 0
        let h = size.height.isFinite ? max(0, Double(size.height)) : 0
        let r = cornerRadius.isFinite ? min(max(0, Double(cornerRadius)), w / 2, h / 2) : 0
        return (w, h, r)
    }

    /// 角丸枠の全周（pt）。常に有限で 0 以上。
    static func perimeter(size: CGSize, cornerRadius: CGFloat) -> Double {
        let (w, h, r) = clamped(size: size, cornerRadius: cornerRadius)
        return 2 * (w + h) - (8 - 2 * Double.pi) * r
    }

    /// 光を描いてよい周長か。
    static func canDrawComet(perimeter: Double) -> Bool { perimeter.isFinite && perimeter >= minPerimeter }

    /// 尾の長さ（全周に対する割合）。一周を超えず、周長が不正なら 0。
    static func tailFraction(perimeter: Double) -> Double {
        guard canDrawComet(perimeter: perimeter) else { return 0 }
        return min(tailLength / perimeter, 1)
    }

    /// 光の先頭位置（0..<1、左上が 0）。一定の速さで周回する。周長が不正なら 0。
    static func headPosition(time: TimeInterval, perimeter: Double) -> Double {
        guard time.isFinite, perimeter.isFinite, perimeter > 0 else { return 0 }
        let lap = perimeter / speed
        let remainder = time.truncatingRemainder(dividingBy: lap)
        return min((remainder >= 0 ? remainder : remainder + lap) / lap, 1)
    }

    /// 先頭 `head` から後ろへ `length`（全周に対する割合）の区間 [head-length, head] を、
    /// 0...1 に収まる区間へ分ける（左上をまたぐと 2 つになる）。入力が不正なら空。
    static func trimRanges(head: Double, length: Double) -> [ClosedRange<Double>] {
        guard head.isFinite, length.isFinite, length > 0 else { return [] }
        let head = min(max(head, 0), 1)
        let length = min(length, 1)
        let lower = head - length
        if lower >= 0 { return [lower...head] }
        return [0...head, (lower + 1)...1].filter { $0.lowerBound < $0.upperBound }
    }
}

/// カードの枠（`strokeBorder` した `RoundedRectangle(.continuous)`）と同じ線の上を、左上から時計回りに一周する path。
/// `RoundedRectangle` の path は右辺の中ほどから始まるので、左上の角の終わりで切って繋ぎ直し、起点を左上にする。
struct SubAgentMarkerOutline: Shape {
    let cornerRadius: CGFloat

    func path(in full: CGRect) -> Path {
        // strokeBorder と同じく、線の中心を外形から 0.5pt 内側・角丸半径を 0.5pt 小さくして通す。
        let rect = full.insetBy(dx: 0.5, dy: 0.5)
        let (w, h, r) = SubAgentMarkerPresentation.clamped(size: rect.size, cornerRadius: cornerRadius - 0.5)
        let perimeter = SubAgentMarkerPresentation.perimeter(size: rect.size, cornerRadius: cornerRadius - 0.5)
        guard rect.width > 0, rect.height > 0, SubAgentMarkerPresentation.canDrawComet(perimeter: perimeter) else { return Path() }
        let base = RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
        // 起点（右辺の中ほど）から左上の角の終わりまでの割合。角の弧は円弧で見積もる（連続曲線との差は 1pt 未満）。
        let remaining = (w - 2 * r) + Double.pi * r / 2 + (h / 2 - r)
        let split = min(max(1 - remaining / perimeter, 0), 1)
        var path = base.trimmedPath(from: split, to: 1)
        path.addPath(base.trimmedPath(from: 0, to: split))
        return path
    }
}

/// 枠の上の、先頭 `head` から後ろへ `length`（どちらも全周に対する割合）の区間。
struct SubAgentMarkerTrail: Shape {
    let cornerRadius: CGFloat
    let head: Double
    let length: Double

    func path(in rect: CGRect) -> Path {
        let outline = SubAgentMarkerOutline(cornerRadius: cornerRadius).path(in: rect)
        var path = Path()
        for range in SubAgentMarkerPresentation.trimRanges(head: head, length: length) {
            path.addPath(outline.trimmedPath(from: range.lowerBound, to: range.upperBound))
        }
        return path
    }
}

/// 実行中のカードの枠に重ねる光。色はサイドバーの実行中タイトルの帯と同じ（ダーク＝白、ライト＝黒）。
struct SubAgentMarkerGlow: View {
    let glow: SubAgentMarkerPresentation.Glow
    let cornerRadius: CGFloat
    /// 書き出し用に時刻を固定できる。nil なら実時間で動く。
    var fixedTime: TimeInterval? = nil

    @Environment(\.scenePhase) private var scenePhase
    /// 画面外・非表示・バックグラウンドでは TimelineView を止める（実行中のカードが多い長い会話でも負荷を増やさない）。
    @State private var isInViewHierarchy = false
    @State private var isInViewport = false

    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInViewport,
            scenePhase: scenePhase
        )
    }

    private var peak: Color { DSColor.isDark ? .white : .black }

    var body: some View {
        switch glow {
        case .none:
            EmptyView()
        case .staticHighlight:
            SubAgentMarkerOutline(cornerRadius: cornerRadius)
                .stroke(peak.opacity(0.35), lineWidth: 1)
        case .comet:
            GeometryReader { proxy in
                let perimeter = SubAgentMarkerPresentation.perimeter(size: proxy.size, cornerRadius: cornerRadius)
                if !SubAgentMarkerPresentation.canDrawComet(perimeter: perimeter) {
                    EmptyView()
                } else if let fixedTime {
                    comet(time: fixedTime, perimeter: perimeter)
                } else {
                    TimelineView(ThinkingAnimationModel.timelineSchedule(isVisible: isTimelineVisible)) { context in
                        comet(time: context.date.timeIntervalSinceReferenceDate, perimeter: perimeter)
                    }
                }
            }
            .onAppear { isInViewHierarchy = true }
            .onDisappear { isInViewHierarchy = false }
            .onViewportVisibilityChange { isInViewport = $0 }
        }
    }

    private func trail(head: Double, length: Double) -> SubAgentMarkerTrail {
        SubAgentMarkerTrail(cornerRadius: cornerRadius, head: head < 0 ? head + 1 : head, length: length)
    }

    /// 先頭は不透明度 1（セッション名の光の頂点と同じ）で、後ろへ消える細い線（尾を数区間に分けて段階的に薄くする）と、先頭の柔らかいにじみ。
    private func comet(time: TimeInterval, perimeter: Double) -> some View {
        let head = SubAgentMarkerPresentation.headPosition(time: time, perimeter: perimeter)
        let length = SubAgentMarkerPresentation.tailFraction(perimeter: perimeter)
        let count = SubAgentMarkerPresentation.tailSegments
        let segmentLength = length / Double(count)
        return ZStack {
            // にじみ: 先頭寄りの短い区間を太くしてぼかす（枠の外へ少しにじむ）。
            trail(head: head, length: length * SubAgentMarkerPresentation.bloomShare)
                .stroke(peak.opacity(DSColor.isDark ? 0.5 : 0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .blur(radius: 3)
            ForEach(0..<count, id: \.self) { index in
                let fade = 1 - Double(index) / Double(count)
                trail(head: head - segmentLength * Double(index), length: segmentLength)
                    .stroke(peak.opacity(fade * fade), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
