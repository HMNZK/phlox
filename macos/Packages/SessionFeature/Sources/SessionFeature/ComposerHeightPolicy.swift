import CoreGraphics

struct ComposerHeightBounds {
    let min: CGFloat
    let max: CGFloat

    // 入力欄パネル全体（フッター・余白込み）で「約80px」が要件（ADR 0046）。
    // 内訳: 縦余白8×2 + エディタ36（1行ぶん） + 間隔4 + フッター28 = 84。
    // エディタ単体 min=80 の実装はパネル約140pxとなりデグレだった（2026-07-07 実機確認・
    // ADR 0044 の該当決定を supersede）。
    static let single = ComposerHeightBounds(min: 36, max: 160)
    static let grid = ComposerHeightBounds(min: 36, max: 160)
}

/// IMESafeTextView の高さ決定の単一真実源（純関数・テスト可能）。
enum ComposerHeightPolicy {
    /// 使用テキスト高＋インセットから、[min, max] にクランプした表示高を返す（ceil 適用）。
    static func resolvedHeight(
        usedTextHeight: CGFloat,
        insetHeight: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        min(maxHeight, max(minHeight, ceil(usedTextHeight + insetHeight)))
    }

    /// 現在値との差分が 0.5pt を超えるときだけ書込する（固定点収束の保証）。
    static func shouldWrite(current: CGFloat, next: CGFloat) -> Bool {
        abs(current - next) > 0.5
    }
}
