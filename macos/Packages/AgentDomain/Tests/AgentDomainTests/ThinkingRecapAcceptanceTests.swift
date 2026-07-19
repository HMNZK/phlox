import Foundation
import Testing
import AgentDomain

// task-2 契約の凍結受け入れテスト（PM 著・実装役は編集禁止）。
// 契約の正本: tasks/task-2.md。ハーネス欠陥を見つけたら PM に報告し承認を得てからハーネス部分のみ修理してよい。

@Suite("ThinkingRecap 受け入れ")
struct ThinkingRecapAcceptanceTests {
    let threshold: TimeInterval = 5

    // MARK: - gate（長い時だけ出す）
    @Test("経過が閾値未満なら活動があっても nil")
    func belowThresholdReturnsNil() {
        let r = ThinkingRecap.summary(
            reasoningText: "何か",
            recentActivity: [.reading("cat foo")],
            elapsed: 2,
            threshold: threshold
        )
        #expect(r == nil)
    }

    @Test("活動も reasoning も無ければ経過十分でも nil")
    func emptyInputsReturnNil() {
        #expect(ThinkingRecap.summary(reasoningText: nil, recentActivity: [], elapsed: 100, threshold: threshold) == nil)
        #expect(ThinkingRecap.summary(reasoningText: "   \n  ", recentActivity: [], elapsed: 100, threshold: threshold) == nil)
    }

    // MARK: - 活動ラベル
    @Test("reading 活動は『… を読み込み中』")
    func readingLabel() {
        #expect(ThinkingRecap.summary(reasoningText: nil, recentActivity: [.reading("cat foo.txt")], elapsed: 10, threshold: threshold) == "cat foo.txt を読み込み中")
    }

    @Test("running 活動は『… を実行中』")
    func runningLabel() {
        #expect(ThinkingRecap.summary(reasoningText: nil, recentActivity: [.running("swift build")], elapsed: 10, threshold: threshold) == "swift build を実行中")
    }

    @Test("editing 活動は『… を編集中』")
    func editingLabel() {
        #expect(ThinkingRecap.summary(reasoningText: nil, recentActivity: [.editing("Foo.swift")], elapsed: 10, threshold: threshold) == "Foo.swift を編集中")
    }

    @Test("最新の活動（.last）が優先される")
    func newestActivityWins() {
        let r = ThinkingRecap.summary(reasoningText: "x", recentActivity: [.reading("a"), .editing("B.swift")], elapsed: 10, threshold: threshold)
        #expect(r == "B.swift を編集中")
    }

    @Test("活動があれば reasoning より優先")
    func activityBeatsReasoning() {
        let r = ThinkingRecap.summary(reasoningText: "## 見出し", recentActivity: [.running("go test")], elapsed: 10, threshold: threshold)
        #expect(r == "go test を実行中")
    }

    // MARK: - ヒューリスティック抽出
    @Test("見出しがあれば末尾側の見出しを抽出（先頭 # 除去）")
    func extractsHeading() {
        let text = "本文\n## 認証フローを設計\nさらに考える"
        #expect(ThinkingRecap.summary(reasoningText: text, recentActivity: [], elapsed: 10, threshold: threshold) == "認証フローを設計")
    }

    @Test("見出しが無ければ末尾の非空白行")
    func extractsLastLine() {
        let text = "最初の考え\nもう少し詰める"
        #expect(ThinkingRecap.summary(reasoningText: text, recentActivity: [], elapsed: 10, threshold: threshold) == "もう少し詰める")
    }

    @Test("60 文字超は prefix(60)+…")
    func truncatesLongLine() {
        let long = String(repeating: "あ", count: 80)
        let r = ThinkingRecap.summary(reasoningText: long, recentActivity: [], elapsed: 10, threshold: threshold)
        #expect(r == String(repeating: "あ", count: 60) + "…")
    }

    // MARK: - fromCommand 分類
    @Test("read 系コマンドは .reading（basename 判定・パス付き可）")
    func fromCommandReading() {
        #expect(RecapActivity.fromCommand("cat foo.txt") == .reading("cat foo.txt"))
        #expect(RecapActivity.fromCommand("/bin/grep x") == .reading("/bin/grep x"))
        #expect(RecapActivity.fromCommand("ls") == .reading("ls"))
    }

    @Test("その他コマンドは .running")
    func fromCommandRunning() {
        #expect(RecapActivity.fromCommand("swift build") == .running("swift build"))
        #expect(RecapActivity.fromCommand("npm test") == .running("npm test"))
    }

    @Test("nil/空白コマンドは .running(\"コマンド\")")
    func fromCommandNil() {
        #expect(RecapActivity.fromCommand(nil) == .running("コマンド"))
        #expect(RecapActivity.fromCommand("   ") == .running("コマンド"))
    }
}
