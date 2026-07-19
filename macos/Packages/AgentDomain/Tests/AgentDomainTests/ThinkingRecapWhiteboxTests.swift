import Foundation
import Testing
import AgentDomain

/// task-2 白箱: 契約境界（空・60文字・見出し複数・read/run 全コマンド・nil/空白）を網羅。
@Suite("ThinkingRecap 白箱")
struct ThinkingRecapWhiteboxTests {
    let threshold: TimeInterval = ThinkingRecap.defaultThreshold

    // MARK: - gate 境界

    @Test("elapsed が threshold ちょうどなら nil ではない（< のみ gate）")
    func atThresholdPassesGate() {
        let r = ThinkingRecap.summary(
            reasoningText: "末尾行",
            recentActivity: [],
            elapsed: threshold,
            threshold: threshold
        )
        #expect(r == "末尾行")
    }

    @Test("defaultThreshold は 5")
    func defaultThresholdIsFive() {
        #expect(ThinkingRecap.defaultThreshold == 5)
    }

    // MARK: - 活動ラベル 60 文字境界

    @Test("活動ラベルがちょうど 60 文字なら省略なし")
    func activityLabelExactly60() {
        // 「 を実行中」は 5 文字 → x は 55 文字で合計 60
        let x = String(repeating: "x", count: 55)
        let label = "\(x) を実行中"
        #expect(label.count == 60)
        let r = ThinkingRecap.summary(
            reasoningText: nil,
            recentActivity: [.running(x)],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == label)
        #expect(r?.count == 60)
    }

    @Test("活動ラベルが 61 文字超なら prefix(60)+…")
    func activityLabelOver60() {
        // 「 を実行中」は 5 文字 → x は 56 文字で合計 61
        let x = String(repeating: "y", count: 56)
        let full = "\(x) を実行中"
        #expect(full.count == 61)
        let r = ThinkingRecap.summary(
            reasoningText: nil,
            recentActivity: [.running(x)],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == String(full.prefix(60)) + "…")
    }

    @Test("空文字の活動ペイロードでも crash せずラベルを返す")
    func emptyActivityPayload() {
        #expect(
            ThinkingRecap.summary(
                reasoningText: nil,
                recentActivity: [.reading("")],
                elapsed: 10,
                threshold: threshold
            ) == " を読み込み中"
        )
        #expect(
            ThinkingRecap.summary(
                reasoningText: nil,
                recentActivity: [.editing("")],
                elapsed: 10,
                threshold: threshold
            ) == " を編集中"
        )
    }

    // MARK: - ヒューリスティック境界

    @Test("reasoning が空文字なら nil")
    func emptyReasoningReturnsNil() {
        #expect(
            ThinkingRecap.summary(
                reasoningText: "",
                recentActivity: [],
                elapsed: 10,
                threshold: threshold
            ) == nil
        )
    }

    @Test("改行のみ・空白行のみは nil")
    func whitespaceOnlyReasoningReturnsNil() {
        #expect(
            ThinkingRecap.summary(
                reasoningText: "\n\n\n",
                recentActivity: [],
                elapsed: 10,
                threshold: threshold
            ) == nil
        )
        #expect(
            ThinkingRecap.summary(
                reasoningText: "  \n\t\n  ",
                recentActivity: [],
                elapsed: 10,
                threshold: threshold
            ) == nil
        )
    }

    @Test("見出しが複数なら末尾側の見出しを優先")
    func lastHeadingWins() {
        let text = "# 最初\n中間本文\n## 中盤見出し\n続き\n### 最終見出し\n後書き"
        let r = ThinkingRecap.summary(
            reasoningText: text,
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == "最終見出し")
    }

    @Test("単一 # 見出しも抽出できる")
    func singleHashHeading() {
        let r = ThinkingRecap.summary(
            reasoningText: "前置き\n# 単一見出し\n後",
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == "単一見出し")
    }

    @Test("#### は見出し扱いにしない（1〜3個のみ）")
    func fourHashesNotHeading() {
        let text = "本文\n#### 四つは見出しでない\n末尾の行"
        let r = ThinkingRecap.summary(
            reasoningText: text,
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == "末尾の行")
    }

    @Test("抽出結果がちょうど 60 文字なら省略なし")
    func extractedLineExactly60() {
        let line = String(repeating: "あ", count: 60)
        let r = ThinkingRecap.summary(
            reasoningText: "前\n\(line)",
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == line)
        #expect(r?.count == 60)
    }

    @Test("前後空白は除去してから返す")
    func trimsExtractedLine() {
        let r = ThinkingRecap.summary(
            reasoningText: "  トリム対象  \n",
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == "トリム対象")
    }

    @Test("巨大入力でも crash せず末尾行を切る")
    func hugeInputDoesNotCrash() {
        let huge = String(repeating: "行\n", count: 5000) + String(repeating: "末", count: 100)
        let r = ThinkingRecap.summary(
            reasoningText: huge,
            recentActivity: [],
            elapsed: 10,
            threshold: threshold
        )
        #expect(r == String(repeating: "末", count: 60) + "…")
    }

    // MARK: - fromCommand 分類網羅

    @Test("read 系全コマンド（basename）が .reading")
    func allReadCommands() {
        let readCmds = [
            "cat", "less", "head", "tail", "grep", "rg", "find", "ls",
            "bat", "fd", "cd", "pwd", "echo", "which", "stat", "wc",
        ]
        for cmd in readCmds {
            #expect(RecapActivity.fromCommand(cmd) == .reading(cmd), "expected reading for \(cmd)")
            #expect(
                RecapActivity.fromCommand("/usr/bin/\(cmd) arg") == .reading("/usr/bin/\(cmd) arg"),
                "expected reading for /usr/bin/\(cmd)"
            )
        }
    }

    @Test("非 read 系は .running（代表例）")
    func nonReadCommandsAreRunning() {
        #expect(RecapActivity.fromCommand("swift test") == .running("swift test"))
        #expect(RecapActivity.fromCommand("python3 script.py") == .running("python3 script.py"))
        #expect(RecapActivity.fromCommand("/usr/bin/make") == .running("/usr/bin/make"))
    }

    @Test("nil・空白のみ・タブのみは .running(\"コマンド\")")
    func nilAndBlankCommands() {
        #expect(RecapActivity.fromCommand(nil) == .running("コマンド"))
        #expect(RecapActivity.fromCommand("") == .running("コマンド"))
        #expect(RecapActivity.fromCommand("   ") == .running("コマンド"))
        #expect(RecapActivity.fromCommand("\t\n") == .running("コマンド"))
    }

    @Test("先頭トークンの basename で判定（引数付きパス）")
    func basenameWithArgs() {
        #expect(RecapActivity.fromCommand("/bin/cat /tmp/a") == .reading("/bin/cat /tmp/a"))
        #expect(RecapActivity.fromCommand("/opt/homebrew/bin/rg -n foo") == .reading("/opt/homebrew/bin/rg -n foo"))
    }
}
