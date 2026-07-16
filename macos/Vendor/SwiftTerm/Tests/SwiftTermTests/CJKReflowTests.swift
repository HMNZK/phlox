#if os(macOS)
import Foundation
import Testing

@testable import SwiftTerm

/// AgentDashboard でグリッド（狭い幅のタイル）→シングル（広い幅）へ切り替えた際、
/// 全角(CJK)を含む折り返し行が正しく再フローされず、右側に断片が残る描画崩れ
/// （Image #14 の「ません。投 / 資判断…」が右にずれる症状）の回帰テスト。
///
/// UI レンダリングではなく `Terminal.resize` のバッファ挙動を直接検証するため、
/// 手動操作やセッションのアイドル状態に依存せず決定論的に再現・検証できる。
final class CJKReflowTests {

    /// 全角文字だけで折り返された行を広い幅へリサイズしたとき、1 行に再結合され、
    /// 断片・残留セルが残らないこと。
    @Test func widenReflow_cjkOnlyWrappedLine_recombinesCleanly() {
        // 20 桁 = 全角 10 文字/行（グリッドタイル相当の狭い端末）
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 10, scrollback: 50)

        // 全角 25 文字。20 桁では 10/10/5 の 3 行に自動折り返しされる。
        let cjk = "あいうえおかきくけこさしすせそたちつてとなにぬねの"
        #expect(cjk.count == 25)
        t.feed(text: cjk)
        t.feed(text: "\r\n")  // カーソルを折り返し行群の外へ出して reflow 対象にする

        // 60 桁 = 全角 30 文字/行（シングル表示相当の広い端末）へリサイズ
        t.resize(cols: 60, rows: 10)

        // 期待: 25 文字が 1 行に再結合される（断片・残留セルが無い）
        let row0 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 0) ?? ""
        #expect(row0 == cjk)

        // 2 行目以降に断片が残っていないこと
        let row1 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 1) ?? ""
        #expect(row1 == "")
    }

    /// ASCII と全角が混在した折り返し行でも、広い幅へのリサイズで正しく再結合されること。
    @Test func widenReflow_mixedAsciiCjkWrappedLine_recombinesCleanly() {
        // 16 桁の狭い端末
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 10, scrollback: 50)

        // ASCII(半角) と 全角 の混在。16 桁では複数行に折り返される。
        let mixed = "ABCあいうDEFかきくGHIさしす123"
        t.feed(text: mixed)
        t.feed(text: "\r\n")

        // 80 桁の広い端末へリサイズ（混在文字が 1 行に収まる幅）
        t.resize(cols: 80, rows: 10)

        let row0 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 0) ?? ""
        #expect(row0 == mixed)

        let row1 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 1) ?? ""
        #expect(row1 == "")
    }

    /// アプリの実シナリオ: 単体(広) で生成 → グリッド(狭) → 単体(広) の往復後に、
    /// 全角を含む内容が元通り 1 行に戻り、断片が残らないこと。
    @Test func roundTripReflow_wideNarrowWide_cjkOnly_staysClean() {
        // 60 桁(広) で生成（シングル表示相当）
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 60, rows: 10, scrollback: 50)
        let cjk = "あいうえおかきくけこさしすせそたちつてとなにぬねの"  // 全角 25 文字
        t.feed(text: cjk)
        t.feed(text: "\r\n")

        // 広(60) → 狭(20)（グリッドへ）
        t.resize(cols: 20, rows: 10)
        // 狭(20) → 広(60)（シングルへ戻す）
        t.resize(cols: 60, rows: 10)

        let row0 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 0) ?? ""
        #expect(row0 == cjk)
        let row1 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 1) ?? ""
        #expect(row1 == "")
    }

    /// 往復(広→狭→広)、ASCII と全角の混在版。
    /// 内容は半角12＋全角25文字=62桁のため、広い側は 80 桁（1 行に収まる幅）を使う。
    @Test func roundTripReflow_wideNarrowWide_mixed_staysClean() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 10, scrollback: 50)
        let mixed = "Claude Code に関する今日のニュースを調査します。投資判断の根拠"
        t.feed(text: mixed)
        t.feed(text: "\r\n")

        t.resize(cols: 24, rows: 10)
        t.resize(cols: 80, rows: 10)

        let row0 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 0) ?? ""
        #expect(row0 == mixed)
        let row1 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 1) ?? ""
        #expect(row1 == "")
    }

    /// 折返しグループが複数あり、グループごとに先頭行の実長が異なる場合でも、
    /// 狭→広の再結合が各グループ自身の行長に基づいて行われること。
    /// (reflowWider が結合開始桁をバッファ先頭行の長さから誤計算し、2 つ目以降の
    ///  グループで余分な null セル混入・内容の桁ずれが起きるバグの回帰テスト。
    ///  Claude Code セッションの CJK トランスクリプトがリサイズで崩れた症状に対応)
    @Test func roundTripReflow_multipleWrappedGroups_eachGroupKeepsOwnContent() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 100, rows: 20, scrollback: 200)
        // CJK 全角が行末をまたぐ位置がグループごとに異なる 3 段落。
        // 全角の早折返し(実長 cols-1)が混ざることでグループ間の行長差が生まれる。
        let paragraphs = [
            "[r0] - **影響**: `SKIP_PUSH_CHECK=1` を知らないユーザーが意図的にローカル限定でリリース処理をしたい場合(例: CI外の検証環境)にリリースがブロックされ、回避手段に気付けない。",
            "[r0] - **具体的な修正案**: `docs/release-runbook.md` の環境変数説明セクション(行71付近)または検証用コマンド節(行60-67付近)に以下を追記する:",
            "[r0] リリース後、bump で変わった `project.yml` をコミットすること(版を git 履歴に残す)。",
        ]
        for p in paragraphs { t.feed(text: p + "\r\n") }
        let before = (0..<20).map { TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: $0) ?? "" }

        // 単体(広 100) → グリッド(狭 56) → 単体(広 100) の往復
        t.resize(cols: 56, rows: 20)
        t.resize(cols: 100, rows: 20)

        let after = (0..<20).map { TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: $0) ?? "" }
        #expect(after == before)
    }

    /// 複数回往復しても累積崩れが起きないこと。
    @Test func roundTripReflow_repeated_cjk_staysClean() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 60, rows: 10, scrollback: 50)
        let cjk = "あいうえおかきくけこさしすせそたちつてとなにぬねの"
        t.feed(text: cjk)
        t.feed(text: "\r\n")

        for _ in 0..<3 {
            t.resize(cols: 18, rows: 10)
            t.resize(cols: 60, rows: 10)
        }

        let row0 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 0) ?? ""
        #expect(row0 == cjk)
        let row1 = TerminalTestHarness.lineText(buffer: t.buffer, terminal: t, row: 1) ?? ""
        #expect(row1 == "")
    }
}
#endif
