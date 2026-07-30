import AgentDomain
import Foundation

// thinking-orbs (MIT) の profiles.ts / presets.ts の移植。
// 基本プロファイル（fine）へ、プリセットごとの個数・半径の倍率を掛けて解決する。

/// 各モードの描画パラメータ。原実装の可変辞書に対応する（未設定は各モードの既定値を使う）。
public struct OrbOptions: Equatable, Sendable {
    // 個数系
    var latRings: Double?
    var rings: Double?
    var lonDensity: Double?
    var lanes: Double?
    var segs: Double?
    var orbitN: Double?
    var ghostN: Double?
    var iconD: Double?
    // 半径系
    var rBase: Double?
    var rDepth: Double?
    var rActive: Double?
    var rDot: Double?
    var ghostR: Double?
    var partR: Double?
    var partRDepth: Double?
    // その他のつまみ
    var rBoost: Double?
    var inkFar: Double?
    var inkSpan: Double?
    var rsPow: Double?
    var rMin: Double?
    var particles: Double?
    var ghostA: Double?
    var moveCount: Double?
    var scanMul: Double?
    var dimBase: Double?
    var spin: Double?
    var bandMul: Double?
    var wobMul: Double?
    var spread: Double?
}

/// 描画モード（状態ごとに 1 つ）。
public enum OrbMode: String, CaseIterable, Sendable {
    case orbits
    case globe
    case rubik
    case wave
    case ribbon
    case morph
}

/// 調整済みの描画サイズ（CSS px 相当）。原実装と同じく 2 つだけを持つ。
public enum OrbSizePreset: Int, CaseIterable, Sendable {
    case large = 64
    case inline = 20
}

enum OrbProfiles {
    /// 倍率適用前の基本プロファイル。
    static func base(_ mode: OrbMode) -> OrbOptions {
        switch mode {
        case .globe:
            return OrbOptions(
                latRings: 17,
                lonDensity: 44,
                rBase: 0.6,
                rDepth: 1.7,
                rBoost: 1.0,
                inkFar: 0.62,
                inkSpan: 0.54,
                rsPow: 0.6,
                rMin: 0.3
            )
        case .orbits:
            return OrbOptions(
                orbitN: 12,
                ghostN: 40,
                ghostR: 0.9,
                partR: 1.2,
                partRDepth: 1.6,
                rsPow: 0.6,
                rMin: 0.3,
                particles: 3,
                ghostA: 0.5
            )
        case .rubik:
            return OrbOptions(
                latRings: 15,
                lonDensity: 40,
                rBase: 0.6,
                rDepth: 1.7,
                rActive: 0.3,
                inkFar: 0.62,
                inkSpan: 0.54,
                rsPow: 0.6,
                rMin: 0.3,
                moveCount: 14
            )
        case .wave:
            return OrbOptions(
                rings: 15,
                lonDensity: 40,
                rBase: 0.6,
                rDepth: 1.7,
                rsPow: 0.6,
                rMin: 0.3
            )
        case .ribbon:
            return OrbOptions(
                lanes: 5,
                segs: 88,
                ghostN: 150,
                rBase: 1.1,
                rDepth: 1.7,
                rsPow: 0.6,
                rMin: 0.3
            )
        case .morph:
            return OrbOptions(iconD: 1, rDot: 0.021, rMin: 0.25)
        }
    }

    /// 2 次元格子（リング × リング上の点数）は各辺 √scale を掛け、総点数が scale 倍になるようにする。
    /// 平坦なリストは線形に、morph の輪郭密度 `iconD` は線形に掛ける。
    static func scaleCounts(_ options: OrbOptions, by scale: Double) -> OrbOptions {
        var out = options
        var lonDensityDone = false

        if let latRings = out.latRings, let lonDensity = out.lonDensity {
            let rt = scale.squareRoot()
            out.latRings = max(2, (latRings * rt).rounded())
            out.lonDensity = max(2, (lonDensity * rt).rounded())
            lonDensityDone = true
        }
        if let rings = out.rings, let lonDensity = out.lonDensity, !lonDensityDone {
            let rt = scale.squareRoot()
            out.rings = max(2, (rings * rt).rounded())
            out.lonDensity = max(2, (lonDensity * rt).rounded())
        }
        if let lanes = out.lanes, let segs = out.segs {
            let rt = scale.squareRoot()
            out.lanes = max(2, (lanes * rt).rounded())
            out.segs = max(2, (segs * rt).rounded())
        }
        if let orbitN = out.orbitN { out.orbitN = max(1, (orbitN * scale).rounded()) }
        if let ghostN = out.ghostN { out.ghostN = max(1, (ghostN * scale).rounded()) }
        if let iconD = out.iconD { out.iconD = max(0.02, iconD * scale) }
        return out
    }

    /// 点の描画半径を決める全キーを一律に掛ける（近／遠の落差を保ったまま大きさだけ変える）。
    static func scaleRadii(_ options: OrbOptions, by scale: Double) -> OrbOptions {
        var out = options
        if let value = out.rBase { out.rBase = value * scale }
        if let value = out.rDepth { out.rDepth = value * scale }
        if let value = out.rActive { out.rActive = value * scale }
        if let value = out.rDot { out.rDot = value * scale }
        if let value = out.ghostR { out.ghostR = value * scale }
        if let value = out.partR { out.partR = value * scale }
        if let value = out.partRDepth { out.partRDepth = value * scale }
        return out
    }
}

/// (状態, サイズ) を解決した描画設定。
public struct OrbPreset: Equatable, Sendable {
    public let mode: OrbMode
    public let speed: Double
    public let options: OrbOptions
}

public enum OrbPresets {
    private struct Tuning {
        let speed: Double
        let count: Double
        let size: Double
        var extra: (inout OrbOptions) -> Void = { _ in }
    }

    private static func tuning(_ mode: OrbMode, _ size: OrbSizePreset) -> Tuning {
        switch (mode, size) {
        case (.orbits, .large):
            return Tuning(speed: 1.885, count: 1, size: 1)
        case (.orbits, .inline):
            return Tuning(speed: 3.9, count: 0.238, size: 2.4)
        case (.globe, .large):
            return Tuning(speed: 2.015, count: 0.42, size: 1.15) { $0.scanMul = 4.08; $0.dimBase = 0.45 }
        case (.globe, .inline):
            return Tuning(speed: 2.665, count: 0.105, size: 1.75) { $0.scanMul = 4.335; $0.dimBase = 0.45 }
        case (.rubik, .large):
            return Tuning(speed: 1.82, count: 0.35, size: 1.05)
        case (.rubik, .inline):
            return Tuning(speed: 1.95, count: 0.088, size: 1.9)
        case (.wave, .large):
            return Tuning(speed: 4.388, count: 0.341, size: 1)
        case (.wave, .inline):
            return Tuning(speed: 3.998, count: 0.105, size: 1.6)
        case (.ribbon, .large):
            return Tuning(speed: 2.34, count: 0.25, size: 0.85) { $0.spin = 0; $0.bandMul = 3.9; $0.wobMul = 1 }
        case (.ribbon, .inline):
            return Tuning(speed: 3.12, count: 0.051, size: 1.073) { $0.spin = 0; $0.bandMul = 4.94; $0.wobMul = 1 }
        case (.morph, .large):
            return Tuning(speed: 2.405, count: 0.54, size: 0.395) { $0.spread = 1.45 }
        case (.morph, .inline):
            return Tuning(speed: 2.08, count: 0.53, size: 1.011) { $0.spread = 1.45 }
        }
    }

    /// (状態, サイズ) をモードと倍率適用済みの描画設定へ解決する。
    public static func resolve(state: AgentActivityState, size: OrbSizePreset) -> OrbPreset {
        let mode = state.orbMode
        let tuned = tuning(mode, size)
        var options = OrbProfiles.base(mode)
        if tuned.count != 1 { options = OrbProfiles.scaleCounts(options, by: tuned.count) }
        if tuned.size != 1 { options = OrbProfiles.scaleRadii(options, by: tuned.size) }
        tuned.extra(&options)
        return OrbPreset(mode: mode, speed: tuned.speed, options: options)
    }
}
