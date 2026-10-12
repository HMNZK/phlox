import SwiftUI

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
