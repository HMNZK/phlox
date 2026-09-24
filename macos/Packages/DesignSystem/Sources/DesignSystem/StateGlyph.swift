import SwiftUI
import AgentDomain

/// 状態の記号（PhloxWindow.dc.html の `glyph`）。対応待ち 4 状態だけ状態色、ほかは無彩色の輪。
/// 承認待ち＝ひし形、質問待ち＝角丸の「?」、エラー＝三角の「!」、無応答＝六角形。
public struct StateGlyph: View {
    let state: SessionDisplayState
    let size: CGFloat

    public init(state: SessionDisplayState, size: CGFloat = 12) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        shape
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var shape: some View {
        switch state {
        case .starting:
            Circle().strokeBorder(DSColor.neutralGlyph, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.5]))
        case .idle:
            Circle().strokeBorder(DSColor.neutralGlyph, lineWidth: 1.5)
        case .running:
            Circle().trim(from: 0, to: 0.75)
                .stroke(DSColor.neutralGlyph, lineWidth: 2)
                .padding(1)
        case .approval:
            RoundedRectangle(cornerRadius: 2)
                .fill(DSColor.attentionMark(.approval))
                .scaleEffect(0.76)
                .rotationEffect(.degrees(45))
        case .question:
            RoundedRectangle(cornerRadius: 3)
                .fill(DSColor.attentionMark(.question))
                .overlay { mark("?", scale: 0.7) }
        case .doneUnread, .done:
            Circle().fill(DSColor.neutralGlyph)
                .overlay { mark("✓", scale: 0.62, color: DSColor.background) }
        case .error:
            Triangle().fill(DSColor.attentionMark(.error))
                .overlay(alignment: .bottom) { mark("!", scale: 0.62) }
        case .stalled:
            Hexagon().fill(DSColor.attentionMark(.stalled))
        }
    }

    private func mark(_ text: String, scale: CGFloat, color: Color = .white) -> some View {
        Text(verbatim: text)
            .font(.system(size: (size * scale).rounded(), weight: .heavy))
            .foregroundStyle(color)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let points: [(CGFloat, CGFloat)] = [(0.25, 0.04), (0.75, 0.04), (1, 0.5), (0.75, 0.96), (0.25, 0.96), (0, 0.5)]
        return Path { p in
            p.addLines(points.map { CGPoint(x: rect.minX + $0.0 * w, y: rect.minY + $0.1 * h) })
            p.closeSubpath()
        }
    }
}

/// エージェントの頭文字のタイル（PhloxWindow.dc.html の `mono`）。淡いエージェント色の面に本文色の頭文字。
public struct AgentInitialTile: View {
    let descriptor: AgentDescriptor
    let size: CGFloat

    public init(descriptor: AgentDescriptor, size: CGFloat = 16) {
        self.descriptor = descriptor
        self.size = size
    }

    public var body: some View {
        Text(verbatim: descriptor.tabInitials)
            .font(.system(size: max(8, (size * 0.5).rounded()), weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(DSColor.textPrimary)
            .frame(width: size, height: size)
            .background(DSColor.agentInitialFill(for: descriptor), in: RoundedRectangle(cornerRadius: (size * 0.28).rounded()))
            .accessibilityHidden(true)
    }
}

/// フォルダの線画（PhloxSidebar.dc.html の SVG。viewBox 16×13）。線の太さは呼び出し側で `stroke` に渡す。
public struct FolderShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 16, sy = rect.height / 13
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(1, 2.4))
        path.addLine(to: p(1, 11.2))
        path.addQuadCurve(to: p(1.8, 12), control: p(1, 12))
        path.addLine(to: p(14.2, 12))
        path.addQuadCurve(to: p(15, 11.2), control: p(15, 12))
        path.addLine(to: p(15, 4.3))
        path.addQuadCurve(to: p(14.2, 3.5), control: p(15, 3.5))
        path.addLine(to: p(7.4, 3.5))
        path.addLine(to: p(6, 1.6))
        path.addLine(to: p(1.8, 1.6))
        path.addQuadCurve(to: p(1, 2.4), control: p(1, 1.6))
        path.closeSubpath()
        return path
    }
}

/// グリッドの表示範囲の印（4 マス。viewBox 14×12）。
public struct GridScopeShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 14, sy = rect.height / 12
        var path = Path()
        for (x, y) in [(0.6, 0.6), (7.8, 0.6), (0.6, 6.8), (7.8, 6.8)] {
            path.addRoundedRect(
                in: CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: 5.6 * sx, height: 4.6 * sy),
                cornerSize: CGSize(width: sx, height: sy)
            )
        }
        return path
    }
}
