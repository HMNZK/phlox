import CoreGraphics

/// シングルビューでのサブエージェント横並び分割（Bug2/3/4）のレイアウト定数と幅クランプ。
///
/// 右ペイン幅は「比率（`@AppStorage` 永続）× 利用可能幅」を、下限 `minPaneWidth`・
/// 上限 `maxPaneFraction`（利用可能幅比）でクランプして決める。純関数なので単体テスト可能
/// （`SubAgentSplitLayoutAcceptanceTests` が契約を凍結）。レイアウト骨格・ドラッグ・
/// ヘッダー整列・CPU 収束は runtime 検証。
enum SubAgentSplitLayout {
    /// 既定の右ペイン比率。
    static let defaultFraction: Double = 0.42
    /// 右ペインの下限幅（これより狭くしない。ただし上限が下回る狭窓では上限を優先）。
    static let minPaneWidth: CGFloat = 320
    /// 右ペインの上限（利用可能幅に対する比率）。メイン側が消滅しないための上限。
    static let maxPaneFraction: CGFloat = 0.6
    /// メイン／サブのヘッダー共有高さ。両ヘッダーをこの高さに固定して罫線を一直線に揃える（Bug4）。
    static let headerHeight: CGFloat = 32

    /// 右ペイン幅を [下限, 上限] でクランプして返す。
    /// - 上限 = `availableWidth * maxPaneFraction`
    /// - 下限 = `min(minPaneWidth, 上限)`（下限が上限を超える狭窓では上限を優先＝メインを潰さない）
    static func paneWidth(fraction: Double, availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        let upper = availableWidth * maxPaneFraction
        let lower = min(minPaneWidth, upper)
        let raw = CGFloat(fraction) * availableWidth
        return min(max(raw, lower), upper)
    }
}
