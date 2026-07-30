import Testing
import PhloxCore
@testable import Features

@Suite("iOS ツール実行カード 白箱")
struct IOSToolCallCardWhiteboxTests {
    @Test("ヘッダは共有導出結果と件数フォールバックをそのまま使う")
    func headerDelegatesTitleDerivation() {
        let items = [
            ChatMessage.command(id: "c1", command: "  Read   /tmp/a.txt  ", output: "ok"),
            ChatMessage.command(id: "c2", command: "swift  test", output: "done"),
        ]

        let header = SessionDetailCommandGroupHeader(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false
        )

        #expect(header.title == "swift test")
        #expect(header.subtitle == nil)
        #expect(header.elements == [.title, .chevron, .spacer])
    }

    @Test("コマンドカードの表示データはツール名・本文・ハイライト・コピー原文を分離する")
    func commandCardDataKeepsSourceText() {
        let data = SessionDetailCommandCardData(
            command: "Read /tmp/a.txt",
            output: "line1\nline2"
        )

        #expect(data.toolLabel == "Read")
        #expect(data.commandBody == "/tmp/a.txt")
        #expect(String(data.highlightedCommand.characters) == "/tmp/a.txt")
        #expect(data.copyText == "$ Read /tmp/a.txt\nline1\nline2")
    }

    @Test("コマンドが空でもカードデータを安全に作れる")
    func commandCardDataHandlesNil() {
        let data = SessionDetailCommandCardData(command: nil, output: "")

        #expect(data.toolLabel == "Bash")
        #expect(data.commandBody.isEmpty)
        #expect(String(data.highlightedCommand.characters).isEmpty)
        #expect(data.copyText.isEmpty)
    }
}
