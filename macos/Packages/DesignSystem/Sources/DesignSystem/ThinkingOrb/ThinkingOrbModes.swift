import Foundation

// thinking-orbs (MIT) の engine/{orbits,lattice,ribbon,morph}.ts の移植。
// 各モードは 1 フレーム分の点群を返す純関数。描画は OrbPainter が担う。

public enum OrbModeRenderer {
    /// モードと時刻から 1 フレームの点群を作る（決定論・副作用なし）。
    public static func dots(mode: OrbMode, size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        switch mode {
        case .orbits: return orbits(size: size, time: t, options: o)
        case .globe: return globe(size: size, time: t, options: o)
        case .rubik: return rubik(size: size, time: t, options: o)
        case .wave: return wave(size: size, time: t, options: o)
        case .ribbon: return ribbon(size: size, time: t, options: o)
        case .morph: return morph(size: size, time: t, options: o)
        }
    }

    // MARK: - orbits（working）: 傾いた軌道上を粒子が走る

    static func orbits(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let cx = size / 2
        let cy = size / 2
        let radius = (size / 2) * 0.82
        let project = OrbMath.projector(yaw: t * 0.12, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = OrbMath.radiusScale(size: size, pow: o.rsPow ?? 0.6)

        var dots: [OrbDot] = []
        let orbitN = Int(o.orbitN ?? 12)
        let ghostN = Int(o.ghostN ?? 40)
        let particles = Int(o.particles ?? 3)

        for orb in 0..<max(0, orbitN) {
            let h1 = OrbMath.hash(Double(orb), 1.7)
            let h2 = OrbMath.hash(Double(orb), 5.2)
            let h3 = OrbMath.hash(Double(orb), 8.9)
            let ro = radius * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi
            let phi = acos(2 * h2 - 1)
            // 軌道面の基底 (u, v ⟂ 法線 n)
            let nx = sin(phi) * cos(th)
            let ny = cos(phi)
            let nz = sin(phi) * sin(th)
            var ux = -ny
            var uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul
            uy /= ul
            let vx = ny * uz - nz * uy
            let vy = nz * ux - nx * uz
            let vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

            for k in 0..<max(0, ghostN) {
                let a = (Double(k) / Double(ghostN)) * 2 * .pi
                let (px, py, z) = project(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: z,
                        r: (o.ghostR ?? 0.9) * rs,
                        white: 0.72,
                        alpha: (o.ghostA ?? 0.5) * (0.4 + 0.6 * depth)
                    )
                )
            }
            for m in 0..<max(0, particles) {
                let a = t * speed + (Double(m) / Double(particles)) * 2 * .pi + h2 * 6
                let (px, py, z) = project(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: z,
                        r: ((o.partR ?? 1.2) + (o.partRDepth ?? 1.6) * depth) * rs,
                        white: 0.3 - 0.22 * depth
                    )
                )
            }
        }
        return dots
    }

    // MARK: - globe（searching）: 走査する子午線が球面を掃く

    static func globe(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let spin = 0.5
        let cx = size / 2
        let cy = size / 2
        let radius = (size / 2) * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let project = OrbMath.projector(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius)
        // 走査は自転に対する相対速度。scanMul がその相対レートを掛ける。
        let scan = t * (spin + (1.7 - spin) * (o.scanMul ?? 1))
        let rs = OrbMath.radiusScale(size: size, pow: o.rsPow ?? 0.6)
        let dimBase = o.dimBase ?? 1

        var dots: [OrbDot] = []
        let latRings = max(1, Int(o.latRings ?? 17))
        let lonDensity = o.lonDensity ?? 44
        for li in 0...latRings {
            let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (px, py, z) = project(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                // 走査線は「光沢」ではなく点サイズの波として読ませる
                let d = OrbMath.angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: z,
                        r: ((o.rBase ?? 0.6) + (o.rDepth ?? 1.7) * depth + (o.rBoost ?? 1) * boost) * rs,
                        white: (o.inkFar ?? 0.62) - (o.inkSpan ?? 0.54) * depth,
                        alpha: dimBase + (1 - dimBase) * min(1, boost)
                    )
                )
            }
        }
        return dots
    }

    // MARK: - rubik（solving）: 帯が 1/4 回転で崩れ、逆再生で揃う

    private struct OrbMove {
        let axis: Int
        let lo: Double
        let hi: Double
        let angle: Double
    }

    private static func makeMoves(count: Int) -> [OrbMove] {
        (0..<max(0, count)).map { i in
            let axis = min(2, Int(OrbMath.hash(Double(i), 2.3) * 3))
            let lo = -1.0 + 0.5 * Double(min(3, Int(OrbMath.hash(Double(i), 5.9) * 4)))
            let dir: Double = OrbMath.hash(Double(i), 7.7) < 0.5 ? 1 : -1
            return OrbMove(axis: axis, lo: lo, hi: lo + 0.5, angle: dir * .pi / 2)
        }
    }

    private static func solveCycle(
        time: Double,
        count: Int,
        slotDuration: Double,
        rest: Double
    ) -> (amount: [Double], active: Int) {
        let cyc = 2 * Double(count) * slotDuration + rest
        let tc = time.truncatingRemainder(dividingBy: cyc)
        var amount = [Double](repeating: 0, count: max(0, count))
        var active = -1
        if tc < 2 * Double(count) * slotDuration {
            let slot = Int(tc / slotDuration)
            let p = (tc - Double(slot) * slotDuration) / slotDuration
            let cl = min(1, p / 0.7)
            let ep = 1 - pow(1 - cl, 3) // 機械的な ease-out
            if slot < count {
                for i in 0..<slot { amount[i] = 1 }
                amount[slot] = ep
                active = slot
            } else {
                let u = 2 * count - 1 - slot
                for i in 0..<u { amount[i] = 1 }
                amount[u] = 1 - ep
                active = u
            }
        }
        return (amount, active)
    }

    private static func applyMoves(
        _ point: (Double, Double, Double),
        moves: [OrbMove],
        cycle: (amount: [Double], active: Int)
    ) -> (Double, Double, Double, Bool) {
        var (x, y, z) = point
        var inActive = false
        for i in moves.indices {
            if cycle.amount[i] <= 0 { continue }
            let mv = moves[i]
            let coord = mv.axis == 0 ? x : (mv.axis == 1 ? y : z)
            if coord < mv.lo || coord >= mv.hi { continue }
            if i == cycle.active { inActive = true }
            let a = mv.angle * cycle.amount[i]
            let ca = cos(a)
            let sa = sin(a)
            if mv.axis == 0 {
                let y2 = y * ca - z * sa
                z = y * sa + z * ca
                y = y2
            } else if mv.axis == 1 {
                let x2 = x * ca + z * sa
                z = -x * sa + z * ca
                x = x2
            } else {
                let x2 = x * ca - y * sa
                y = x * sa + y * ca
                x = x2
            }
        }
        return (x, y, z, inActive)
    }

    static func rubik(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let cx = size / 2
        let cy = size / 2
        let radius = (size / 2) * 0.82
        let project = OrbMath.projector(
            yaw: t * 0.55,
            tilt: 0.35 + 0.1 * sin(t * 0.9),
            cx: cx,
            cy: cy,
            scale: radius
        )
        let rs = OrbMath.radiusScale(size: size, pow: o.rsPow ?? 0.6)
        let moveCount = Int(o.moveCount ?? 14)
        let moves = makeMoves(count: moveCount)
        let cycle = solveCycle(time: t, count: moveCount, slotDuration: 0.42, rest: 1.2)

        var dots: [OrbDot] = []
        let latRings = max(1, Int(o.latRings ?? 15))
        let lonDensity = o.lonDensity ?? 40
        for li in 0...latRings {
            let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (x, y, z, inActive) = applyMoves(
                    (cosLat * cos(lon), sinLat, cosLat * sin(lon)),
                    moves: moves,
                    cycle: cycle
                )
                let (px, py, zr) = project(x, y, z)
                let depth = (zr + 1) / 2
                // 回している帯だけインクが濃くなる ＝「手」の表現
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: zr,
                        r: ((o.rBase ?? 0.6) + (o.rDepth ?? 1.7) * depth + (inActive ? (o.rActive ?? 0.3) : 0)) * rs,
                        white: (o.inkFar ?? 0.62) - (o.inkSpan ?? 0.54) * depth - (inActive ? 0.14 : 0)
                    )
                )
            }
        }
        return dots
    }

    // MARK: - wave（listening）: 波形が緯度リングを転がる

    static func wave(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let cx = size / 2
        let cy = size / 2
        // 0.76 × 1.15。波が球を内側へ引くぶん他モードより約 15% 小さく見えるため補正する。
        let radius = (size / 2) * 0.874
        let project = OrbMath.projector(yaw: t * 0.18, tilt: 0.38, cx: cx, cy: cy, scale: 1)
        let rs = OrbMath.radiusScale(size: size, pow: o.rsPow ?? 0.6)

        var dots: [OrbDot] = []
        let rings = max(1, Int(o.rings ?? 15))
        let lonDensity = o.lonDensity ?? 40
        for ri in 0...rings {
            let lat = -Double.pi / 2 + (Double(ri) / Double(rings)) * .pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            // テンポの違う 2 波。有機的で完全には繰り返さない。
            let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
            let rr = radius * (0.88 + 0.105 * w)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (px, py, z) = project(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / radius + 1) / 2
                let crest = max(0, w)
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: z,
                        r: ((o.rBase ?? 0.6) + (o.rDepth ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                        white: 0.66 - 0.56 * depth - 0.1 * crest
                    )
                )
            }
        }
        return dots
    }

    // MARK: - ribbon（composing）: うねる帯が大円を走る

    static func ribbon(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let cx = size / 2
        let cy = size / 2
        let radius = (size / 2) * 0.78
        // spin=0 で 3D の回転が止まり、帯の進行するうねりだけが残る
        let spin = o.spin ?? 1
        let project = OrbMath.projector(yaw: t * 0.1 * spin, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = OrbMath.radiusScale(size: size, pow: o.rsPow ?? 0.6)

        var dots: [OrbDot] = []
        let ghostN = Int(o.ghostN ?? 150)
        for i in 0..<max(0, ghostN) {
            let d = OrbMath.fibDirection(i, ghostN)
            let (px, py, z) = project(d.0 * radius, d.1 * radius, d.2 * radius)
            let depth = (z / radius + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, alpha: 0.1 + 0.22 * depth))
        }

        // 帯の平面（spin=0 なら静止）
        let ya = t * 0.24 * spin
        let ta = 0.55 + 0.3 * sin(t * 0.18) * spin
        let ux = cos(ya)
        let uy = 0.0
        let uz = sin(ya)
        let vx = -uz * sin(ta)
        let vy = cos(ta)
        let vz = ux * sin(ta)
        let nx = uy * vz - uz * vy
        let ny = uz * vx - ux * vz
        let nz = ux * vy - uy * vx

        let baseLanes = o.lanes ?? 5
        let segs = Int(o.segs ?? 88)
        let lanes = max(1, Int((baseLanes * (o.bandMul ?? 1)).rounded()))
        for w in 0..<lanes {
            let laneOff = (Double(w) - Double(lanes - 1) / 2) * 0.075
            let edge = abs(Double(w) - Double(lanes - 1) / 2) / max(1, Double(lanes - 1) / 2)
            for k in 0..<max(0, segs) {
                let a = (Double(k) / Double(segs)) * 2 * .pi
                // うねり: 帯に沿って進む 2 つの波。wobMul が変形量を掛ける（0 なら平坦な帯）。
                let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1))
                    * (o.wobMul ?? 1)
                let off = laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let (px, py, zr) = project((x / l) * radius, (y / l) * radius, (z / l) * radius)
                let depth = (zr / radius + 1) / 2
                dots.append(
                    OrbDot(
                        x: px,
                        y: py,
                        z: zr,
                        r: ((o.rBase ?? 1.1) + (o.rDepth ?? 1.7) * depth) * (1 - 0.25 * edge) * rs,
                        white: 0.52 - 0.44 * depth + 0.18 * edge,
                        alpha: 0.4 + 0.6 * depth
                    )
                )
            }
        }
        return dots
    }

    // MARK: - morph（shaping）: 円 → 三角 → 四角と輪郭が移り変わる

    private typealias OrbPath = @Sendable (Double) -> (Double, Double)

    private static func smoothStep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private static func polygonPath(_ verts: [(Double, Double)]) -> OrbPath {
        let count = verts.count
        var lengths: [Double] = []
        var total = 0.0
        for i in 0..<count {
            let a = verts[i]
            let b = verts[(i + 1) % count]
            let l = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            lengths.append(l)
            total += l
        }
        let segmentLengths = lengths
        let perimeter = total
        return { f in
            var target = f * perimeter
            var i = 0
            while target > segmentLengths[i] && i < count - 1 {
                target -= segmentLengths[i]
                i += 1
            }
            let a = verts[i]
            let b = verts[(i + 1) % count]
            let ff = segmentLengths[i] != 0 ? min(1, target / segmentLengths[i]) : 0
            return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
        }
    }

    private static let circlePath: OrbPath = { f in
        let a = -Double.pi / 2 + f * 2 * .pi
        return (cos(a) * 0.24, sin(a) * 0.24)
    }

    private static let cyclePaths: [OrbPath] = [
        circlePath,
        polygonPath([(0.0, -0.26), (0.24, 0.16), (-0.24, 0.16)]),
        // 5 頂点で歩き、他の形と同じく上端中央から始める
        polygonPath([(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)]),
    ]

    private static let morphHold = 1.4
    private static let morphTransition = 0.9
    private static var morphSegment: Double { morphHold + morphTransition }

    static func morph(size: Double, time t: Double, options o: OrbOptions) -> [OrbDot] {
        let shapeCount = cyclePaths.count
        let tc = t.truncatingRemainder(dividingBy: morphSegment * Double(shapeCount))
        let k = Int(tc / morphSegment)
        let local = tc - Double(k) * morphSegment
        let m = local > morphHold ? smoothStep((local - morphHold) / morphTransition) : 0
        let spread = o.spread ?? 1

        // 2 つの形の「経路」を m で混ぜ、その輪郭の弧長を測る
        let pathA = cyclePaths[k]
        let pathB = cyclePaths[(k + 1) % shapeCount]
        let sampleCount = 160
        var points: [(Double, Double)] = []
        points.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let f = Double(i) / Double(sampleCount)
            let a = pathA(f)
            let b = pathB(f)
            points.append(((a.0 + (b.0 - a.0) * m) * spread, (a.1 + (b.1 - a.1) * m) * spread))
        }
        var lengths: [Double] = []
        var total = 0.0
        for i in 0..<sampleCount {
            let a = points[i]
            let b = points[(i + 1) % sampleCount]
            let l = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            lengths.append(l)
            total += l
        }

        // 点の半径は rDot だけで決まり、個数が間隔を決める。形が定まっている間は微かに脈動する。
        let n = max(6, Int((34 * (o.iconD ?? 1)).rounded()))
        let re = (o.rDot ?? 0.021) * 1.35 * spread
        let pulse = 1 + 0.02 * sin(local * 3.1)

        var dots: [OrbDot] = []
        let c2 = size / 2
        var seg = 0
        var acc = 0.0
        for index in 0..<n {
            let target = (Double(index) / Double(n)) * total
            while acc + lengths[seg] < target && seg < sampleCount - 1 {
                acc += lengths[seg]
                seg += 1
            }
            let a = points[seg]
            let b = points[(seg + 1) % sampleCount]
            let f = lengths[seg] != 0 ? min(1, (target - acc) / lengths[seg]) : 0
            let x = (a.0 + (b.0 - a.0) * f) * pulse
            let y = (a.1 + (b.1 - a.1) * f) * pulse
            dots.append(
                OrbDot(
                    x: c2 + x * size,
                    y: c2 + y * size,
                    z: 0,
                    r: max(0.35, re * size),
                    white: 0.1
                )
            )
        }
        return dots
    }
}
