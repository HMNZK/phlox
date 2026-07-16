import Foundation

// task-4 契約の PM スタブ。API 表面は受け入れテスト
// TrailingTopBarLayoutAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-4.md（固定 reservedWidth の逆算をやめ、
// 右上コントロール群の実測幅から Usage チップ行の使用可能幅を導出する）。
public enum TrailingTopBarLayout {
    /// Usage チップ行が使える横幅。ウィンドウ幅から、開いているサイドバー幅・
    /// 実測したコントロール群の幅・チップ行とコントロール間の spacing・
    /// 右端 padding を差し引いた値を 0 でクランプして返す純関数。
    ///
    /// `occupiedSidebarWidth` には左サイドバー（開いているとき）に加え、
    /// 左側トップバーオーバーレイ（三色ボタン右のリーディングコントロール群）の
    /// 占有幅も合算して渡す。シグネチャは凍結のためパラメータ名は据え置き。
    public static func usageAvailableWidth(
        windowWidth: CGFloat,
        occupiedSidebarWidth: CGFloat,
        measuredControlsWidth: CGFloat,
        spacing: CGFloat,
        trailingPadding: CGFloat
    ) -> CGFloat {
        let occupied = occupiedSidebarWidth + measuredControlsWidth + spacing + trailingPadding
        return max(0, windowWidth - occupied)
    }

    /// 実測到着前は過大見積り、到着後は実測値を使う（0 幅チップ全消え防止）。
    public static func effectiveControlsWidth(
        measured: CGFloat,
        hasMeasured: Bool,
        viewMode: ViewMode
    ) -> CGFloat {
        hasMeasured ? measured : conservativeControlsWidthEstimate(for: viewMode)
    }

    /// 初回レイアウトパスで GeometryReader が 0 を返すことがあるため、
    /// 実測前のコントロール幅見積り（過大＝チップ側を控えめに倒す安全側）。
    public static func conservativeControlsWidthEstimate(for mode: ViewMode) -> CGFloat {
        mode == .grid ? 320 : 200
    }

    /// 左側トップバーオーバーレイ（padding 78 + トグル類 + タイトル max 320）の
    /// 実測前見積り。長いセッション名選択時の左衝突を避けるため最大構成で見積る。
    public static func conservativeLeadingOverlayWidthEstimate() -> CGFloat {
        // 78: 三色ボタン右の leading padding
        // 28+8+28+8: サイドバートグル + spacing + 設定 + spacing
        // 320: selectedSessionTitle の frame(maxWidth:)
        78 + 28 + 8 + 28 + 8 + 320
    }

    /// 実測到着前は過大見積り、到着後は実測値を使う。
    public static func effectiveLeadingOverlayWidth(
        measured: CGFloat,
        hasMeasured: Bool
    ) -> CGFloat {
        hasMeasured ? measured : conservativeLeadingOverlayWidthEstimate()
    }

    /// 0 幅のレイアウトパスは無視し、既存の実測状態を維持する。
    public static func applyWidthMeasurement(
        newWidth: CGFloat,
        currentMeasured: CGFloat,
        hasMeasured: Bool
    ) -> (measured: CGFloat, hasMeasured: Bool) {
        guard newWidth > 0 else {
            return (currentMeasured, hasMeasured)
        }
        return (newWidth, true)
    }

    /// サイドバー幅と左オーバーレイ幅を `occupiedSidebarWidth` へ合算する。
    public static func occupiedWidthForUsageLayout(
        sidebarWidth: CGFloat,
        sidebarVisible: Bool,
        leadingOverlayWidth: CGFloat
    ) -> CGFloat {
        (sidebarVisible ? sidebarWidth : 0) + leadingOverlayWidth
    }
}
