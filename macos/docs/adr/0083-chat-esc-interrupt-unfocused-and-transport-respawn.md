---
status: active
last-verified: 2026-07-13
---

# ADR 0083: 非フォーカス時 esc の中止到達と、中断後 transport の turnStart 自己修復

## 文脈

チャットモード（Claude 経路）で2つの症状が報告された:

1. **esc で進行中の処理を中止できない**（画面の停止ボタンでは中止できる）。
2. **停止した後にメッセージを送っても処理が開始されない**（無音失敗）。

根本原因は2つで、いずれも「フォーカス状態」と「中断後のプロセス生死」に起因する:

- **Bug1（esc が中止に届かない）**: esc の View 受け口は3層あり、フォーカス状態で発火先が変わる——(1) composer フォーカス時 `SubmitAwareTextView.keyDown`、(2) SwiftUI フォーカスあり `.onKeyPress(.escape)`、(3) フォーカスがどこにも無い時 AppKit `cancelOperation:` → `.onExitCommand`。(1)(2) は `performChatEscape`（→ `turnInterrupt`）へ届くが、**(3) の `.onExitCommand` はサブエージェントドロワーを閉じるだけで中止を呼ばず**、`GridChatColumn` には `.onExitCommand` 自体が無かった。停止ボタンは Button の直接アクションでフォーカス非依存なので常に効く——この非対称が症状を過不足なく説明する。進行中ターンでは composer が first responder を保持しない状況が起きやすく、層(3) へ落ちて中止不能になる。

- **Bug2（停止後の再送が無音失敗）**: `claude -p` は SIGINT で終了する（`interrupt()`→`transport.interrupt()`→`process.interrupt()`。実 CLI へ SIGINT を送る制御実験で終了を確認）。中断でターンが閉じた後にプロセスが死ぬと `handleStreamEnded` は自己修復ブランチ（`currentTurnOpen` が既に false）を素通りして `transport=nil` に落とす。以後の `turnStart` は `notStarted` を throw し、`sendText` が `status=.idle` に戻すだけで**送っても処理が始まらない**。Cursor 経路は interrupt が world 世代を進めるだけで transport を殺さず、Codex 経路は app-server RPC で thread が生きるため、この穴は Claude 経路に固有。

## 決定

1. **esc の3層すべてを `performChatEscape` へ統一する（Bug1）**。
   - `ChatSessionView` の `.onExitCommand` を「ドロワー閉じのみ」から `performChatEscape(viewModel)` へ変更し、`GridChatColumn` にも同じ `.onExitCommand` を付与する。これでフォーカス非依存に「ドロワー閉じ→中止」が等価になる。
   - **二重発火は構造で排他**: `.onKeyPress(.escape)` は `.handled` を返し `cancelOperation` へ伝播しないため、同一 esc が層(2)(3) で二重発火しない（発火は「フォーカス有り＝onKeyPress／フォーカス無し＝onExitCommand」で相互排他）。dedup 用の追加状態は投機的複雑化として入れない。排他前提と失敗モード（破れると単発 esc が「中止＋履歴ピッカー誤発火」になり得る）はコード側コメントに明記し、実機 runtime で「単発 esc＝中止のみ」を確認する。
2. **`turnStart` が死んだ transport を resume 保持で respawn する（Bug2）**。
   - `ClaudeChatClient.turnStart` の入口で `transport==nil` を検出したら、`settingsRespawnSessionArgument()`（会話確立後は `--resume <currentSessionId>`、未確立なら `--session-id`）で respawn してから送信する。respawn 失敗時のみ `.error` を yield して throw する（**握りつぶさない**）。
   - 中断→transport 死→次 turnStart で会話文脈を保ったまま自動復旧する。`handleStreamEnded` 側の後始末（transport=nil 化）は変えず、復旧の責務を turnStart に置く（interrupt の後始末とレースしない）。

## 結果

- Bug1: 白箱 `ChatEscapeHandlingWhiteboxTests`（`performChatEscapeDuringRunningTurnFiresInterrupt`／ドロワー閉じ時は interrupt を呼ばない）。**実機 Debug ビルドで非フォーカス時 esc の中止を確認**（focused 経路は esc 2連打→履歴リバートピッカー出現でルーティングを実機確認）。
- Bug2: 白箱 `InterruptRespawnWhiteboxTests`（interrupt でストリーム終了する fake transport → 次 turnStart が `--resume` 保持で respawn／respawn 失敗時に `.error`＋`notStarted` throw）。修正前 red を使い捨て worktree で再現し非自明性を裏取り。**実機 Debug ビルドで停止後の再送→処理開始を確認**。
- 独立レビュー: Bug1 は persona-reviewer（Claude・別モデル）が pass。Bug2 は実装が Codex のためステージ2（Codex）を省略し、ステージ1（Claude）＋PM の 103 テスト自走＋修正前 red 再現でクロスモデル検証を成立（裁定は delivery/0049）。
- 併せて `sendText` の下書き復元（送信失敗時の投機的ハードニング）は撤回し元の `try?` へ戻した——ユーザー未報告の症状向けで surgical 原則に反し、二重表示・入力窓レースを生むため（delivery/0049）。
- 既知の限界: `.onExitCommand` の発火は SwiftUI/AppKit のフォーカス・responder chain 依存で、自動 GUI 検証では焦点状態の制御が脆い。本 run では最終的に人手の実機確認で裏を取った。
