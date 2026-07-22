// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — 入力バーの添付サムネイルに番号を持たせ、
// カーソル位置を外部へ公開できるようにする。
//
// swift test は macOS ホストで走るため、SwiftUI の実描画・TextSelection の
// 往復は検査できない。ここでは型の契約面と既存契約の非退行だけを凍結する。
//
// アサーションは変更禁止。ただしテストハーネス自体の欠陥を見つけた場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import DesignSystemIOS

@Suite("task-3: 入力バーの添付番号とカーソル公開")
struct InputBarAttachmentNumberingAcceptanceTests {

    @Test
    func stripItem_carriesItsDisplayNumber() {
        let id = UUID()
        let item = DSAttachmentStripItem(id: id, number: 3, previewData: Data([1, 2]))

        #expect(item.id == id)
        #expect(item.number == 3)
        #expect(item.previewData == Data([1, 2]))
    }

    @Test
    func inputBar_exposesCursorAwareInput() {
        #expect(DSInputBar.providesCursorAwareInput)
    }

    // キャレットが本文末尾にあるのが最も普通の状態。ここを弾くとカーソル位置が
    // 外部へ伝わらず、添付プレースホルダが常に先頭へ入る（実機で観測した回帰）。
    @Test
    func cursorMath_acceptsCaretAtEndOfText() {
        let text = "abc"
        #expect(DSInputCursorMath.utf16Offset(of: text.endIndex, in: text) == 3)
        #expect(DSInputCursorMath.utf16Offset(of: text.startIndex, in: text) == 0)
        #expect(DSInputCursorMath.utf16Offset(of: text.index(after: text.startIndex), in: text) == 1)
    }

    @Test
    func cursorMath_acceptsCaretAtEndOfEmptyAndMultibyteText() {
        let empty = ""
        #expect(DSInputCursorMath.utf16Offset(of: empty.endIndex, in: empty) == 0)

        let japanese = "見て"
        #expect(DSInputCursorMath.utf16Offset(of: japanese.endIndex, in: japanese) == 2)

        let emoji = "🐶"
        #expect(DSInputCursorMath.utf16Offset(of: emoji.endIndex, in: emoji) == 2)
    }

    @Test
    func inputBar_keepsExistingContracts() {
        // 入力欄の作り替えで既存の契約・見た目が変わっていないことの非退行ピン。
        #expect(DSInputBar.usesFocusState)
        #expect(DSInputBar.providesPillChrome)
        #expect(!DSInputBar.providesCardChrome)
        #expect(DSInputBar.providesInlineModelSelectorSlot)
        #expect(!DSInputBar.providesKeyboardDismissToolbar)
        #expect(DSInputBar.usesNeutralFocusBorder)
        #expect(DSInputBar.maximumTextLineCount == 4)
        #expect(DSInputBar.sendAccessibilityLabel == "送信")
        #expect(DSInputBar.stopAccessibilityLabel == "停止")
        #expect(DSInputBar.canSubmit(text: "hello", isLoading: false))
        #expect(!DSInputBar.canSubmit(text: "   \n", isLoading: false))
    }
}
