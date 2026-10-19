import SwiftUI

/// アプリ標準のモーショントークン。生値の `Animation.spring(...)` 直書きを排除し、
/// 動きの一貫性を保つ。Reduce Motion 配慮は各 View 側で `accessibilityReduceMotion` を参照する。
public enum DSMotion {
    /// 標準スプリング（リスト挿入・選択・展開など）。
    public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// 状態変化の控えめなフェード/スライド。
    public static let easeOut = Animation.easeOut(duration: 0.20)
    /// バナー等の素早い出現。
    public static let quick = Animation.easeInOut(duration: 0.15)
    /// 押している間のボタン反応。
    public static let tapPress = Animation.easeOut(duration: 0.1)
    /// 指を離した後のボタン復帰。
    public static let tapRelease = Animation.easeOut(duration: 0.2)
    public static let disclosure = Animation.easeInOut(duration: 0.25)
    public static let followNewContent = Animation.easeOut(duration: 0.3)
    public static let appearance = Animation.easeInOut(duration: 0.2)
    public static let rowRemoval = Animation.easeInOut(duration: 0.3)

    static func disclosureAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : disclosure
    }

    /// 自前の接続表示用。OS標準ProgressViewの周期は変更しない。
    public static func spinnerRotation(at time: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
    }
}
