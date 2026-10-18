import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

// iOS のツール実行グループは Mac と同じラベル、要約、実行状態、開閉構成を使う。

private func command(_ id: String, _ command: String?, _ output: String = "") -> ChatMessage {
    .command(id: id, command: command, output: output)
}

@Suite("iOS ツール実行グループ: 見出し")
struct ToolCallGroupHeaderTests {
    @Test("複数ツールは件数ラベルと先頭ツールの対象要約を出す")
    func headerShowsGroupAndFirstTarget() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("1", "Read macos/Sources/ControlServer.swift"), command("2", "Grep forward")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.title == "ツール実行 ×2")
        #expect(header.subtitle == "Read ControlServer.swift ほか 1 件")
    }

    @Test("見出しは共有実装と同じ結果になる（規則を二重に持たない）")
    func headerMatchesSharedRule() {
        let items = [command("1", "Read /tmp/ControlServer.swift"), command("2", "Grep forward")]
        let header = SessionDetailCommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.title == "ツール実行 ×2")
        #expect(header.subtitle == "Read ControlServer.swift ほか 1 件")
    }

    @Test("パス要約は見出しデータで省略せず保持する")
    func headerPreservesFullPathSummary() {
        let long = String(repeating: "a", count: 100)
        let header = SessionDetailCommandGroupHeader(items: [command("1", "Read /tmp/\(long)"), command("2", "Grep x")], lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.title == "ツール実行 ×2")
        #expect(header.subtitle == "Read \(long) ほか 1 件")
    }

    @Test("コマンドが 1 件も無いグループは件数のフォールバックへ落ちる")
    func headerFallsBackToCount() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("1", nil), command("2", "   ")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.title == "ツール実行 ×2")
    }

    @Test("ヘッダはタイトル・開閉印・要約で構成する")
    func chevronFollowsTitle() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("1", "ls", "ok"), command("2", "pwd", "ok")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.elements == [.title, .chevron, .spacer, .subtitle])
    }

    @Test("実行中は最後のツールを要約し状態ラベルを出す")
    func runningHeaderSummarizesActiveTool() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("first", "Read a.swift"), command("last", "swift test")],
            lastTranscriptID: "last",
            isTurnRunning: true
        )
        #expect(header.isRunning == true)
        #expect(header.subtitle == "Bash swift test")
        #expect(header.elements.contains(.subtitle))
    }

    @Test("既知ツールの要約は共有規則でツール名と本文に分ける")
    func headerUsesSharedToolLabelRule() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("c1", "  Read   /tmp/a.txt  ", "ok"), command("c2", "swift  test", "done")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.subtitle == "Read a.txt ほか 1 件")
    }

    @Test("複数行グループは出力あり・実行中のみ描く")
    func shouldRenderOnlyWhenMultiGroupHasOutputOrIsRunning() {
        let manyBlank = SessionDetailCommandGroupHeader(
            items: [command("1", "ls"), command("2", "pwd")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(manyBlank.shouldRender == false)

        let withOutput = SessionDetailCommandGroupHeader(
            items: [command("1", "ls", "a.txt"), command("2", "pwd")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(withOutput.shouldRender == true)

        let running = SessionDetailCommandGroupHeader(
            items: [command("1", "ls"), command("2", "pwd")],
            lastTranscriptID: "2",
            isTurnRunning: true
        )
        #expect(running.shouldRender == true)
    }
}

@Suite("iOS ツール実行グループ: コマンドカード")
struct ToolCallCommandCardTests {
    @Test("既知ツール名はラベルへ、残りがコマンド本体になる")
    func toolLabelIsDerived() {
        let data = SessionDetailCommandCardData(command: "Read /tmp/a.txt", output: "")
        #expect(data.toolLabel == "Read")
        #expect(data.commandBody == "/tmp/a.txt")
        #expect(data.summary == "/tmp/a.txt")
    }

    @Test("シェルコマンドは見出し「コマンド」と本文の要約になる")
    func unknownToolBecomesBash() {
        let data = SessionDetailCommandCardData(command: "swift test --parallel", output: "")
        #expect(data.toolLabel == "コマンド")
        #expect(data.commandBody == "swift test --parallel")
        #expect(data.summary == "$ swift test --parallel")
    }

    @Test("ツール名の導出は共有実装と一致する（規則を二重に持たない）")
    func toolLabelMatchesSharedRule() {
        for input in ["Read /tmp/a.txt", "swift test", "Edit foo.swift", "ls -la"] {
            let shared = ChatCommandToolLabel.derive(command: input)
            let data = SessionDetailCommandCardData(command: input, output: "")
            #expect(data.toolLabel == (shared.label == "Bash" ? "コマンド" : shared.label))
            #expect(data.commandBody == shared.body)
        }
    }

    @Test("複数行のコマンド本文を要約へそのまま保持する")
    func summaryPreservesMultilineCommandText() {
        let command = "swift build \\\n  --configuration release"
        let data = SessionDetailCommandCardData(command: command, output: "")
        #expect(data.summary == "$ \(command)")
    }

    @Test("コマンドカードの表示要約とコピー原文を分ける")
    func commandCardDataKeepsSourceText() {
        let data = SessionDetailCommandCardData(
            command: "Read /tmp/a.txt",
            output: "line1\nline2"
        )

        #expect(data.summary == "/tmp/a.txt")
        #expect(data.copyText == "$ Read /tmp/a.txt\nline1\nline2")
    }

    @Test("コマンドが nil でもカードデータを安全に作れる")
    func nilCommandIsSafe() {
        let data = SessionDetailCommandCardData(command: nil, output: "")

        #expect(data.toolLabel == "コマンド")
        #expect(data.commandBody.isEmpty)
        #expect(data.summary == "$ ")
        #expect(data.copyText.isEmpty)
    }
}
