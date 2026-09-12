// task-30（UX-02）の受け入れテスト。
//
// ベースラインでの red 理由: `StatusBadge.nextActionHint(for:)` は本タスクが新設を要求する API で存在しない
// （参照未解決でコンパイル不能）。加えて語彙の期待値（idle=入力待ち／completed=停止）が現行（待機中／完了 (N)）と異なる。
//
// 契約: 一覧（サイドバー行・グリッドカード見出し）で色だけに頼らず状態を短い言葉で伝える。語彙は仕様 UX-02 の
// 「実行中」「入力待ち」「承認待ち」「停止」「エラー」に、実在する状態を対応させる（起動中・回答待ちは区別のため残す）。
// 承認待ち・回答待ち・エラー・異常終了には次に取れる操作の一言（nextActionHint）があり、ヘルプ／アクセシビリティに出る。
// 経過時間から完了を推定しない（状態は SessionStatus のみから決まる）。

import AgentDomain
import Testing
@testable import DesignSystem

@Suite("task-30: session status words")
struct AcceptanceSessionStatusWordsTests {
    @Test("日本語の状態語彙は仕様 UX-02 の言葉に対応する")
    func japaneseVocabulary() {
        #expect(StatusBadge.label(for: .starting) == "起動中")
        #expect(StatusBadge.label(for: .running) == "実行中")
        #expect(StatusBadge.label(for: .idle) == "入力待ち")
        #expect(StatusBadge.label(for: .awaitingUserQuestion) == "回答待ち")
        #expect(StatusBadge.label(for: .awaitingApproval(prompt: "x")) == "承認待ち")
        #expect(StatusBadge.label(for: .completed(exitCode: 0)) == "停止")
        #expect(StatusBadge.label(for: .completed(exitCode: 137)) == "停止")
        #expect(StatusBadge.label(for: .error(message: "boom")) == "エラー")
    }

    @Test("英語の語彙は従来どおり（回帰ガード）")
    func englishVocabularyUnchanged() {
        #expect(StatusBadge.englishLabel(for: .idle) == "idle")
        #expect(StatusBadge.englishLabel(for: .completed(exitCode: 0)) == "done")
        #expect(StatusBadge.englishLabel(for: .completed(exitCode: 1)) == "exited")
        #expect(StatusBadge.englishLabel(for: .awaitingUserQuestion) == "input")
    }

    @Test("次に取れる操作は対応待ちの状態にだけある")
    func nextActionHints() {
        #expect(StatusBadge.nextActionHint(for: .awaitingApproval(prompt: "x")) == "選択して承認内容を確認する")
        #expect(StatusBadge.nextActionHint(for: .awaitingUserQuestion) == "選択して質問に回答する")
        #expect(StatusBadge.nextActionHint(for: .error(message: "boom")) == "選択して原因を確認し、再開または削除する")
        #expect(StatusBadge.nextActionHint(for: .completed(exitCode: 130)) == "終了コード 130。再開または削除する")
        #expect(StatusBadge.nextActionHint(for: .completed(exitCode: 0)) == "終了コード 0。再開または削除する")
        #expect(StatusBadge.nextActionHint(for: .idle) == nil)
        #expect(StatusBadge.nextActionHint(for: .running) == nil)
        #expect(StatusBadge.nextActionHint(for: .starting) == nil)
    }

    @Test("ヘルプは語彙＋次の操作（＋エラー本文）で組み立てる")
    func helpTextComposition() {
        #expect(StatusBadge.helpText(for: .running) == "実行中")
        #expect(StatusBadge.helpText(for: .idle) == "入力待ち")
        #expect(StatusBadge.helpText(for: .awaitingApproval(prompt: "x")) == "承認待ち — 選択して承認内容を確認する")
        #expect(StatusBadge.helpText(for: .completed(exitCode: 130)) == "停止 — 終了コード 130。再開または削除する")
        #expect(StatusBadge.helpText(for: .error(message: "out of memory")) == "エラー — 選択して原因を確認し、再開または削除する\nout of memory")
    }

    @Test("表示状態は経過時間に依存せず SessionStatus と処理中フラグだけで決まる（既存規則の回帰ガード）")
    func displayStatusDoesNotUseElapsedTime() {
        // 語彙側の関数は SessionStatus 以外の入力を取らないことを型で保証する。
        let f: (SessionStatus) -> String = StatusBadge.label(for:)
        #expect(f(.idle) == "入力待ち")
    }
}
