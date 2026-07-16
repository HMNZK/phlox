import CoreGraphics

enum ComposerFooterLayout: Equatable {
    case standard
    case compact
    case minimal

    var settingsLayout: ComposerSettingsLayout {
        self == .standard ? .standard : .compact
    }
}

/// composer 幅の単一真実源。レイアウト結果を計測して戻すのではなく、
/// 親から演繹された幅のみを入力とする純関数（駆動源#1 の再発防止）。
enum ComposerLayout {
    // ImageRenderer measured worst-case standard footer at 559pt; +40pt breathing room avoids edge clipping.
    static let compactControlsWidthThreshold: CGFloat = 600
    // ImageRenderer measured compact footer at 479pt; +10pt keeps the minimum layout below overflow.
    static let minimalControlsWidthThreshold: CGFloat = 490

    /// 入力欄の最大幅。メインカラム幅の 60%（上限 800）。60% が 800 未満なら 90%。
    /// 0 以下（未確定）は nil = 制約なし。
    static func maxWidth(mainColumnWidth: CGFloat) -> CGFloat? {
        guard mainColumnWidth > 0 else { return nil }
        let sixtyPercent = mainColumnWidth * 0.6
        return sixtyPercent < 800 ? mainColumnWidth * 0.9 : min(sixtyPercent, 800)
    }

    /// 出力メッセージ列（トランスクリプト）の内容最大幅。要件3: 入力欄幅と常に一致させる。
    static func transcriptContentMaxWidth(mainColumnWidth: CGFloat) -> CGFloat? {
        maxWidth(mainColumnWidth: mainColumnWidth)
    }

    static func proposedWidth(mainColumnWidth: CGFloat) -> CGFloat? {
        guard mainColumnWidth > 0 else { return nil }
        return min(maxWidth(mainColumnWidth: mainColumnWidth) ?? mainColumnWidth, mainColumnWidth)
    }

    static func controlsLayout(proposedWidth: CGFloat) -> ComposerFooterLayout {
        if proposedWidth < minimalControlsWidthThreshold {
            return .minimal
        }
        return proposedWidth < compactControlsWidthThreshold ? .compact : .standard
    }

    /// グリッドタイル composer 用。standard は使わず、広い列でも compact 止まり。
    static func gridControlsLayout(proposedWidth: CGFloat) -> ComposerFooterLayout {
        proposedWidth >= minimalControlsWidthThreshold ? .compact : .minimal
    }

    /// フローティング composer 直下の余白帯マスク（ADR 0065）が右端に残す
    /// スクロールバー通り道の幅。ここをマスクで塗るとオーバーレイスクローラの
    /// 下端が隠れ、「バーが画面右下端まで届く」要件が崩れる。
    /// macOS のオーバーレイスクローラ幅（約10-12pt）＋余裕。
    static let scrollerCorridorWidth: CGFloat = 16
}
