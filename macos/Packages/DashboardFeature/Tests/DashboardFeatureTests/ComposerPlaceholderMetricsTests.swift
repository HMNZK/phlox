// composer のキャレットとプレースホルダの位置・フォントの単一の正（ずれると入力中にキャレットとプレースホルダが食い違う）。

import AppKit
import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Composer placeholder metrics")
struct ComposerPlaceholderMetricsTests {

    // NSTextView の textContainerInset とプレースホルダ padding の単一の正が
    // 水平・垂直とも DSSpacing.s であること（grid 版の垂直 padding 欠落の再発防止）。
    @Test
    func textInsetsAreDesignTokenOnBothAxes() {
        #expect(ComposerPlaceholderMetrics.textInsets == CGSize(width: DSSpacing.s, height: DSSpacing.s))
    }

    // プレースホルダのフォントが NSTextView 本体のフォントと同一メトリクスであること
    // （AppKit と SwiftUI の別系統フォント解決によるベースラインずれの排除）。
    @Test
    func placeholderFontMatchesTextViewFont() {
        #expect(ComposerPlaceholderMetrics.placeholderFont == Font(ComposerPlaceholderMetrics.textNSFont as CTFont))
    }
}
