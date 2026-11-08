import Testing
@testable import SessionFeature

// 05 R2: ↑ で古い入力へ、↓ で新しい入力へ。最新より先で呼び戻す前の下書きに戻る。
@Suite("Input history cursor")
struct InputHistoryCursorTests {
    let entries = ["一つ目", "二つ目", "三つ目"]

    @Test
    func upWalksBackAndDownReturnsToTheDraft() {
        var cursor = InputHistoryCursor()
        #expect(cursor.recall(.older, entries: entries, currentText: "書きかけ") == "三つ目")
        #expect(cursor.recall(.older, entries: entries, currentText: "三つ目") == "二つ目")
        #expect(cursor.recall(.older, entries: entries, currentText: "二つ目") == "一つ目")
        #expect(cursor.recall(.older, entries: entries, currentText: "一つ目") == nil)
        #expect(cursor.recall(.newer, entries: entries, currentText: "一つ目") == "二つ目")
        #expect(cursor.recall(.newer, entries: entries, currentText: "二つ目") == "三つ目")
        #expect(cursor.recall(.newer, entries: entries, currentText: "三つ目") == "書きかけ")
        #expect(cursor.recall(.newer, entries: entries, currentText: "書きかけ") == nil)
    }

    @Test
    func editingARecalledEntryStartsOver() {
        var cursor = InputHistoryCursor()
        _ = cursor.recall(.older, entries: entries, currentText: "")
        _ = cursor.recall(.older, entries: entries, currentText: "三つ目")
        // 呼び戻した文を書き換えたら、↓ は動かず、↑ は最新からやり直す。
        #expect(cursor.recall(.newer, entries: entries, currentText: "二つ目を直した") == nil)
        #expect(cursor.recall(.older, entries: entries, currentText: "二つ目を直した") == "三つ目")
        #expect(cursor.recall(.newer, entries: entries, currentText: "三つ目") == "二つ目を直した")
    }

    @Test
    func nothingToRecallWithoutHistory() {
        var cursor = InputHistoryCursor()
        #expect(cursor.recall(.older, entries: [], currentText: "") == nil)
        #expect(cursor.recall(.newer, entries: entries, currentText: "") == nil)
    }

    @Test
    func prependingOlderHistoryKeepsTheCurrentSelection() {
        var cursor = InputHistoryCursor()
        #expect(cursor.recall(.older, entries: ["二つ目", "三つ目"], currentText: "下書き") == "三つ目")
        #expect(cursor.recall(.older, entries: ["二つ目", "三つ目"], currentText: "三つ目") == "二つ目")
        cursor.didPrependEntries(1)
        #expect(cursor.recall(.older, entries: entries, currentText: "二つ目") == "一つ目")
        #expect(cursor.recall(.newer, entries: entries, currentText: "一つ目") == "二つ目")
    }

    @Test
    func replacingLoadedHistoryResetsTheCursorBeforeReadingAnIndex() {
        var cursor = InputHistoryCursor()
        #expect(cursor.recall(.older, entries: entries, currentText: "下書き") == "三つ目")
        #expect(cursor.recall(.older, entries: entries, currentText: "三つ目") == "二つ目")
        #expect(cursor.recall(.older, entries: ["新しい履歴"], currentText: "二つ目") == "下書き")
        #expect(cursor.recall(.older, entries: ["新しい履歴"], currentText: "下書き") == "新しい履歴")
        #expect(cursor.recall(.older, entries: ["別の履歴"], currentText: "新しい履歴") == "下書き")
    }
}
