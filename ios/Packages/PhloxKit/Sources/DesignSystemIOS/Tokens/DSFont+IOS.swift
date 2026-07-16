import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// iOS 向けの Dynamic Type スタイルを共有 `DSFont` に追加する。
/// すべて `Font.TextStyle` ベース（固定サイズ `.system(size:)` を使わない）で、
/// ユーザーの文字サイズ設定に追従する。
public extension DSFont {
    /// 画面タイトル（カンプ各ヘッダ）。
    static let title1 = Font.title.weight(.semibold)
    /// セクション見出し（大）。
    static let title2 = Font.title2.weight(.semibold)
    /// 行タイトル等の強調本文。
    static let headline = Font.headline
    /// 補助情報。
    static let subheadline = Font.subheadline
    /// 最小補助テキスト（タイムスタンプ等）。
    static let footnote = Font.footnote

    /// FAB（＋）内 SF Symbol。カンプ右上 FAB の視認性（`title2` + semibold）。
    static let iconFAB = Font.title2.weight(.semibold)
    /// 送信丸ボタン内矢印（`DSInputBar` / `DSChatInputBar`）。`title3` + semibold。
    static let iconSend = Font.title3.weight(.semibold)

    /// 技術値（IP・ポート・HTTP 等）用モノスペース。JetBrains Mono がバンドルされていれば優先。
    static var campMono: Font { campMonospaced(relativeTo: .body) }
    /// 技術値の補助キャプション用モノスペース。design.md §2.2 の `monoCaption` 相当。
    static var campMonoCaption: Font { campMonospaced(relativeTo: .caption) }

    /// JetBrains Mono が利用可能なら custom、なければシステム monospaced にフォールバックする。
    static func campMonospaced(relativeTo textStyle: Font.TextStyle) -> Font {
        #if canImport(UIKit)
        let candidates = ["JetBrainsMono-Regular", "JetBrains Mono"]
        let baseSize = campMonospacedBaseSize(for: textStyle)
        for name in candidates where UIFont(name: name, size: baseSize) != nil {
            return Font.custom(name, size: baseSize, relativeTo: textStyle)
        }
        #endif
        return Font.system(textStyle, design: .monospaced)
    }

    private static func campMonospacedBaseSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .caption, .caption2, .footnote:
            return 12
        case .subheadline, .callout:
            return 15
        case .title, .title2, .title3, .largeTitle:
            return 20
        default:
            return 17
        }
    }
}
