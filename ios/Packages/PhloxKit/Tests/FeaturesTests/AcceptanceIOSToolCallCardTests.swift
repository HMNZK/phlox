import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

// task-3 の受け入れテスト（PM が著す不変の契約）。
// 目的: iOS のツール実行グループを、デスクトップ（ADR 0144/0145/0147）と同じ「情報の出し方」へ揃える。
//   ①見出しは最後のコマンド原文（60 字クランプ）、コマンドが無いときだけ件数へフォールバック
//   ②装飾（terminal アイコン・"実行中"）を出さない
//   ③シェブロンはタイトル直後
//   ④コマンド行は「ツール名ラベル ＋ $ command ＋ 出力」で、コピーは原文

private func command(_ id: String, _ command: String?, _ output: String = "") -> ChatMessage {
    .command(id: id, command: command, output: output)
}

@Suite("iOS ツール実行グループ: 見出し")
struct AcceptanceIOSToolCallGroupHeaderTests {
    @Test("見出しは最後に実行したコマンドの原文（接尾辞を付けない）")
    func headerShowsLastCommandVerbatim() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("1", "ls -la"), command("2", "swift test")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.title == "swift test")
    }

    @Test("見出しは共有実装と同じ結果になる（規則を二重に持たない）")
    func headerMatchesSharedRule() {
        let items = [command("1", "cd macos && swift build \\\n  --configuration release")]
        let header = SessionDetailCommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.title == ChatCommandGroupTitle.derive(commands: ["cd macos && swift build \\\n  --configuration release"], itemCount: 1))
    }

    @Test("60 文字を超える見出しは省略記号付きで切る")
    func headerIsClamped() {
        let long = String(repeating: "a", count: 100)
        let header = SessionDetailCommandGroupHeader(items: [command("1", long)], lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.title == String(repeating: "a", count: 60) + "…")
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

    @Test("ヘッダの並びはタイトル→シェブロン→余白（シェブロンをタイトル直後に置く）")
    func chevronFollowsTitle() {
        let header = SessionDetailCommandGroupHeader(items: [command("1", "ls")], lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.elements == [.title, .chevron, .spacer])
    }

    @Test("実行中でもヘッダに実行中ラベル・件数サブタイトルを出さない")
    func noSubtitleEvenWhileRunning() {
        let header = SessionDetailCommandGroupHeader(
            items: [command("last", "swift test")],
            lastTranscriptID: "last",
            isTurnRunning: true
        )
        #expect(header.isRunning == true)
        #expect(header.subtitle == nil)
        #expect(header.elements.contains(.subtitle) == false)
    }

    @Test("描画するかどうかの規則は変えない（単独・出力あり・実行中は描く）")
    func shouldRenderRuleIsUnchanged() {
        let single = SessionDetailCommandGroupHeader(items: [command("1", "ls")], lastTranscriptID: nil, isTurnRunning: false)
        #expect(single.shouldRender == true)

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
    }
}

@Suite("iOS ツール実行グループ: コマンドカード")
struct AcceptanceIOSCommandCardTests {
    @Test("既知ツール名はラベルへ、残りがコマンド本体になる")
    func toolLabelIsDerived() {
        let data = SessionDetailCommandCardData(command: "Read /tmp/a.txt", output: "")
        #expect(data.toolLabel == "Read")
        #expect(data.commandBody == "/tmp/a.txt")
    }

    @Test("既知ツール名でなければ Bash とコマンド全文になる")
    func unknownToolBecomesBash() {
        let data = SessionDetailCommandCardData(command: "swift test --parallel", output: "")
        #expect(data.toolLabel == "Bash")
        #expect(data.commandBody == "swift test --parallel")
    }

    @Test("ツール名の導出は共有実装と一致する（規則を二重に持たない）")
    func toolLabelMatchesSharedRule() {
        for input in ["Read /tmp/a.txt", "swift test", "Edit foo.swift", "ls -la"] {
            let shared = ChatCommandToolLabel.derive(command: input)
            let data = SessionDetailCommandCardData(command: input, output: "")
            #expect(data.toolLabel == shared.label)
            #expect(data.commandBody == shared.body)
        }
    }

    @Test("コマンドの色付けは文字を増減させない（表示用の整形を混ぜない）")
    func highlightPreservesCommandText() {
        let data = SessionDetailCommandCardData(command: "swift build \\\n  --configuration release", output: "")
        #expect(String(data.highlightedCommand.characters) == data.commandBody)
    }

    @Test("コピーは表示用データからの復元ではなく原文を返す")
    func copyTextIsSource() {
        let output = "line1\nline2"
        let data = SessionDetailCommandCardData(command: "ls -la", output: output)
        #expect(data.copyText.contains("ls -la"))
        #expect(data.copyText.contains(output))
    }

    @Test("コマンドが nil でも落ちない")
    func nilCommandIsSafe() {
        let data = SessionDetailCommandCardData(command: nil, output: "")
        #expect(data.toolLabel == "Bash")
        #expect(data.commandBody.isEmpty)
    }
}
