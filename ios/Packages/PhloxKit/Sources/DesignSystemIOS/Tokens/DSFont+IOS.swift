import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// iOS 向けの Dynamic Type スタイルを共有 `DSFont` に追加する。
/// 入力欄は見本の段階ごとの字面サイズをここで選び、呼び出し側に固定値を散らさない。
public extension DSFont {
    /// 入力欄の見本に合わせた通常／Dynamic Type 最大の字面サイズ。
    enum InputBarRole {
        case textField
        case chip
        case error
        case caption
        case addSymbol
        case sendSymbol
        case chipSymbol
        case chevron
        case moreSymbol
        case stopSymbol
        case removeSymbol
    }

    static func inputBar(_ role: InputBarRole, for dynamicTypeSize: DynamicTypeSize) -> Font {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let size: CGFloat = switch role {
        case .textField: inputBarTextFieldPointSize(for: dynamicTypeSize)
        case .chip: isAccessibilitySize ? 26 : 13
        case .error: isAccessibilitySize ? 30 : 13
        case .caption: isAccessibilitySize ? 20 : 12
        case .addSymbol: isAccessibilitySize ? 26 : 14
        case .sendSymbol: isAccessibilitySize ? 26 : 17
        case .chipSymbol: isAccessibilitySize ? 26 : 14
        case .chevron: isAccessibilitySize ? 20 : 11
        case .moreSymbol: isAccessibilitySize ? 26 : 16
        case .stopSymbol: isAccessibilitySize ? 16 : 10
        case .removeSymbol: 10
        }
        return .system(size: size, design: .default)
    }

    static func inputBarTextFieldPointSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 40 : 17
    }

    #if os(iOS)
    static func inputBarTextFieldUIFont(for dynamicTypeSize: DynamicTypeSize) -> UIFont {
        .systemFont(ofSize: inputBarTextFieldPointSize(for: dynamicTypeSize))
    }
    #endif

    /// 新規チャットの DotGothic16 見出し。仕様の Dynamic Type 段階に合わせて固定サイズを選ぶ。
    static func displayDot(for dynamicTypeSize: DynamicTypeSize) -> Font {
        .custom("DotGothic16-Regular", fixedSize: displayDotSize(for: dynamicTypeSize))
    }

    static func displayDotSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 24
        case .small: 25
        case .medium: 27
        case .large: 28
        case .xLarge: 30
        case .xxLarge: 32
        case .xxxLarge, .accessibility1, .accessibility2, .accessibility3, .accessibility4: 34
        case .accessibility5: 44
        @unknown default: 34
        }
    }

    /// 使用量の枠ラベルは、リングの拡大段階と揃える。
    static func usageRingLabel(for dynamicTypeSize: DynamicTypeSize) -> Font {
        .system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 11)
    }

    /// 一覧最上部の大タイトル。iOS 標準の large title と同じ見た目にする。
    static let largeTitle = Font.largeTitle.weight(.bold)
    /// 起動画面の Phlox ロゴ文字。
    static var appBrandMark: Font { .system(size: 48, weight: .bold, design: .rounded) }
    /// 画面タイトル（カンプ各ヘッダ）。
    static let title1 = Font.title.weight(.semibold)
    /// セクション見出し（大）。
    static let title2 = Font.title2.weight(.semibold)
    /// 行タイトル等の強調本文。
    static let headline = Font.headline
    /// 補助情報。
    static let subheadline = Font.subheadline
    /// 小さな補助情報。
    static let iosCaption = Font.caption
    /// 最小サイズの補助情報（使用量リングの枠ラベル等）。
    static let iosCaption2 = Font.caption2
    /// 最小補助テキスト（タイムスタンプ等）。
    static let footnote = Font.footnote

    /// セッション詳細のナビゲーション見出し（17 / semibold）。
    static var sessionDetailTitle: Font { .headline.weight(.semibold) }
    /// セッション詳細の補助ラベル・小ボタン（13 / regular）。
    static var sessionDetailSubtitle: Font { .footnote }
    /// セッション詳細の技術値（13 / monospaced）。
    static var sessionDetailTechnical: Font { .system(.footnote, design: .monospaced) }
    /// iPhone の思考カード本文（見本の補助本文 15pt、Dynamic Type 対応）。
    static var sessionDetailReasoning: Font { .subheadline }
    /// ターン使用量の末尾行（12 / monospaced）。
    static var sessionDetailUsage: Font { .system(.caption, design: .monospaced) }
    /// 空状態の吹き出し記号（28）。
    static var sessionEmptyIcon: Font { .system(size: 28) }

    /// FAB（＋）内 SF Symbol。カンプ右上 FAB の視認性（`title2` + semibold）。
    static let iconFAB = Font.title2.weight(.semibold)
    /// 入力欄の送信丸ボタン内の矢印。`title3` + semibold。
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
