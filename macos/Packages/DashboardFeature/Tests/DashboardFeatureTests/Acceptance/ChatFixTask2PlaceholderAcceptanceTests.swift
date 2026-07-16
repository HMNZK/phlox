// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — キャレットとプレースホルダの位置・フォントの単一の正。
// 保留中は LOOPFLOW_PENDING_TASK2=1 で suite ごとスキップできる（PM の検証運用用。実装役は使わない）。

import AppKit
import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite(
    "ChatFix task-2: composer プレースホルダとキャレットの位置整合",
    .enabled(if: ProcessInfo.processInfo.environment["LOOPFLOW_PENDING_TASK2"] != "1")
)
struct ChatFixTask2PlaceholderAcceptanceTests {

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
