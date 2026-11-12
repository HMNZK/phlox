import CoreGraphics
import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum ThinkingOrbColorStyle: Sendable {
    case monochrome
    case rainbow
}

// thinking-orbs (MIT, Copyright (c) 2026 Jakub Antalik) の描画エンジンを Swift へ移植したもの。
// 原実装は Canvas 2D。ここでは同じ数式のまま CoreGraphics へ描く（THIRD_PARTY_NOTICES.md 参照）。

/// 1 個の点。`white` はインク値（0 = 最も濃い）。暗い下地では 1 - white に反転する。
public struct OrbDot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var r: Double
    public var white: Double
    public var alpha: Double

    public init(x: Double, y: Double, z: Double, r: Double, white: Double, alpha: Double = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.r = r
        self.white = white
        self.alpha = alpha
    }
}

/// 3D 座標を「画面座標 + 深度」へ写す射影。
typealias OrbProjector = (Double, Double, Double) -> (Double, Double, Double)

enum OrbMath {
    /// 決定論ハッシュ [0, 1)。
    static func hash(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }

    /// 単位球上の安定した方向（フィボナッチ格子）。
    static func fibDirection(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
        let rad = (1 - y * y).squareRoot()
        let a = Double(i) * golden
        return (rad * cos(a), y, rad * sin(a))
    }

    /// 最短の符号付き角度差（(-π, π] へ畳む）。
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }

    /// 共通の spin + tilt + 正射影。
    static func projector(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) -> OrbProjector {
        let st = sin(tilt)
        let ct = cos(tilt)
        let sy = sin(yaw)
        let cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    /// 点の半径は 300pt 枠向けに調整されているため、劣線形スケールで小さい orb の可読性を保つ。
    static func radiusScale(size: Double, pow exponent: Double) -> Double {
        Foundation.pow(size / 300, exponent)
    }
}

enum OrbPainter {
    /// 奥→手前に z ソートして塗る。暗い下地ではインク値を反転し、手前の点が明るく読めるようにする。
    static func paint(
        _ dots: [OrbDot], into context: CGContext, dark: Bool, minRadius: Double,
        colorStyle: ThinkingOrbColorStyle, size: Double, time: Double
    ) {
        for dot in dots.sorted(by: { $0.z < $1.z }) {
            let alpha = dot.alpha
            if alpha < 0.02 { continue }
            let w = min(1, max(0, dot.white))
            let g = (dark ? 1 - w : w)
            let radius = max(minRadius, dot.r)
            switch colorStyle {
            case .monochrome:
                context.setFillColor(red: g, green: g, blue: g, alpha: alpha)
            case .rainbow:
                // 同じ色の帯が画面左上から右下へ進む。点の位置と深度は既存描画のまま保つ。
                let phase = ((dot.x + dot.y) / (2 * size) - time * 0.1).truncatingRemainder(dividingBy: 1)
                let hue = phase < 0 ? phase + 1 : phase
                let brightness = dark ? 0.45 + 0.55 * g : 0.35 + 0.5 * g
                #if canImport(AppKit)
                let color = NSColor(calibratedHue: hue, saturation: 0.75, brightness: brightness, alpha: alpha)
                #elseif canImport(UIKit)
                let color = UIColor(hue: hue, saturation: 0.75, brightness: brightness, alpha: alpha)
                #endif
                context.setFillColor(color.cgColor)
            }
            context.fillEllipse(
                in: CGRect(
                    x: dot.x - radius,
                    y: dot.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }
}
