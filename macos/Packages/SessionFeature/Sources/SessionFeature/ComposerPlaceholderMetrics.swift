import AppKit
import CoreText
import DesignSystem
import SwiftUI

// task-2 契約の PM スタブ。API 表面は受け入れテスト
// ChatFixTask2PlaceholderAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-2.md（NSTextView とプレースホルダの位置・フォントの単一の正）。

/// composer 入力欄（IMESafeTextView）とプレースホルダの位置合わせを一元管理するメトリクス。
/// NSTextView の textContainerInset と SwiftUI プレースホルダの padding は必ずここから引く。
enum ComposerPlaceholderMetrics {
    /// NSTextView の textContainerInset ＝ プレースホルダの padding（水平・垂直）。
    static var textInsets: CGSize { CGSize(width: DSSpacing.s, height: DSSpacing.s) }

    /// NSTextView 本体のフォント。
    static var textNSFont: NSFont { .preferredFont(forTextStyle: .body) }

    /// プレースホルダ Text のフォント。textNSFont と同一メトリクスであること。
    static var placeholderFont: Font { Font(textNSFont as CTFont) }
}
