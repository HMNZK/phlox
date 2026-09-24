import CoreGraphics
import Foundation

/// チャット本文の文字倍率設定の単一の真実源。
/// UserDefaults に Double で保存し、全チャットセッションで共有する。
public enum ChatFontSettings {
    public static let scaleKey = "phlox.chat.fontScale"

    public static let defaultScale: CGFloat = 1.0
    public static let minScale: CGFloat = 0.8
    public static let maxScale: CGFloat = 2.0
    public static let step: CGFloat = 0.1

    public static func currentScale(defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: scaleKey) != nil else {
            return defaultScale
        }
        return clamped(CGFloat(defaults.double(forKey: scaleKey)))
    }

    public static func save(_ scale: CGFloat, defaults: UserDefaults = .standard) {
        defaults.set(Double(clamped(scale)), forKey: scaleKey)
    }

    /// delta を加算してクランプした新倍率を返す。永続化は呼び出し元の責務。
    public static func adjusted(from current: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(current + delta)
    }

    /// 設定のスライダーの値を刻み（step）に丸める。目盛りを出さないため刻みはスライダーに渡さず、ここで守る。
    /// キーボード・読み上げの 1 回の操作は、丸めで戻らないよう呼び出し側で `adjusted(from:by: ±step)` を使う。
    public static func snapped(_ value: CGFloat) -> CGFloat {
        clamped((value / step).rounded() * step)
    }

    private static func clamped(_ scale: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, scale))
    }
}
