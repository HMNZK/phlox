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
}
