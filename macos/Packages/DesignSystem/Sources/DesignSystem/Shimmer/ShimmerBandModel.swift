import Foundation

/// 明度帯が左→右へ流れるシマーの位相計算（純関数・macOS / iOS 共有）。
/// ADR 0067 が凍結した仕様をそのまま持ち、駆動方式（Core Animation / TimelineView）に依存しない。
/// 以前は macOS `ThinkingAnimationModel` と iOS `DSThinkingAnimationModel` に同じ式が二重にあった。
public enum ShimmerBandModel {
    /// シマー1周期（秒）。ADR 0067 の 1.6 は実チャットでの目視で速すぎたため 2.0 へ緩めた（ADR 0143）。
    public static let period: TimeInterval = 2.0

    /// 明度の下限（帯から最も遠い位置の明度倍率）。
    /// ADR 0067 の 0.45 はライトモードで薄すぎた（下限側の文字が背景に溶ける）ため 0.55 へ上げた（ADR 0143）。
    public static let minBrightness: Double = 0.55

    /// 帯を画面外まで逃がすための左右余白（正規化幅）。折返し（phase: 1→0）を帯が画面外に
    /// ある瞬間に起こし、右端→左端の瞬間移動（かくつき）を不可視化する。
    public static let margin: Double = 0.6

    /// 明度帯の幅（正規化幅・falloff の標準偏差）。
    public static let bandWidth: Double = 0.22

    /// 明度帯の中心位置（0=左端, 1=右端）。時間とともに前進し、周期 `period` で反復。戻り値 [0,1)。
    /// TimelineView の date のみを入力に取る純関数（Timer / repeatForever / @State 不使用）。
    public static func phase(date: Date) -> Double {
        phase(at: date.timeIntervalSinceReferenceDate)
    }

    /// 時刻（秒）を `period` で割った余りを [0,1) へ正規化（負値も [0,1) へ）。
    public static func phase(at time: TimeInterval) -> Double {
        let remainder = time.truncatingRemainder(dividingBy: period)
        let normalizedRemainder = remainder >= 0 ? remainder : remainder + period
        return normalizedRemainder / period
    }

    /// phase(0..1) を、画面外余白を含む帯中心 [−margin, 1+margin] へ線形写像する。
    /// phase=0 で帯は左端の外、phase→1 で右端の外に位置し、折返しは両端とも画面外で起きるため
    /// 継ぎ目が見えない。ビューはこの戻り値を `brightness(position:phase:)` の phase に渡す。
    public static func bandCenter(phase: Double) -> Double {
        let clampedPhase = min(max(phase, 0), 1)
        return clampedPhase * (1 + 2 * margin) - margin
    }

    /// 正規化位置 position(0=左,1=右) の明度倍率。position==phase で最大 1.0、離れるほど `minBrightness` へ減衰。
    /// 戻り値 [minBrightness, 1.0]。決定論。
    /// phase（＝帯の中心）は [0,1] 外も受け付ける（`bandCenter` が返す −margin..1+margin を
    /// そのまま渡せるように position のみ [0,1] へ丸める）。帯が画面外にあるときは全 position が下限へ収束する。
    public static func brightness(position: Double, phase: Double) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        let distance = abs(clampedPosition - phase)
        let normalizedDistance = distance / bandWidth
        let falloff = exp(-0.5 * normalizedDistance * normalizedDistance)
        return minBrightness + (1 - minBrightness) * falloff
    }
}
