---
status: active
last-verified: 2026-07-21
---

# ADR 0113: ライブのサブエージェント transcript も「1 ツールコール = 1 セル」で組み、ソース選択を2通りに畳む（0106 を supersede）

## 文脈

サブエージェント別ペインの transcript には 2 ソースがある（architecture/chat-subagent-display.md）:

- **ライブ**: stdout stream 由来。永続化されない。
- **parsed**: 子 JSONL（`SubAgentRef.outputFile`）を `SubAgentTranscriptLoader.parse` したもの。

`SubAgentTranscriptLoader.parse` は当初から `tool_use` と `tool_result` を `tool_use_id` で 1 セルへマージしていた（ADR 0025 決定6）。
一方 **ライブ側は同じ統合をしていなかった**:

- `ClaudeChatClient+SubAgentContent.swift` は子の `tool_use` の `id` と、子の `tool_result` の `tool_use_id` を**どちらも捨てて**
  `.subAgentActivity(kind: .tool, itemId: nil, …)` を送っていた。
- 受け側 `ChatSubAgentModel.appendSubAgentActivity` は itemId nil の `.tool` を毎回連番 id の新規 `commandExecution` として append していた。

結果、ライブでは **1 ツールコールが 2 セル**になり、さらに `commandExecution.command` が常に nil でコマンド説明が
`output` 欄に入る（呼び出しと結果の区別が表示に無い）状態だった。

ADR 0106 はこの 2重化を前提に、選択規則へ「完了済みなら parsed を優先する」という特例を足して**表示上の症状だけ**を塞いだ。
実データ検証で、その特例では塞ぎ切れていない範囲が残ることを確認した:

- `outputFile` は `.subAgentCompleted`（`task_notification`）でしか渡らないため、**実行中は必ず `parsed == nil`**。
  よって `transcript(for:)` は live をそのまま返し、**実行中のドロワーではツールが実数の2倍に見え続ける**
  （完了した瞬間に半減する）。
- 件数タイブレーク（`parsed.count >= live.count`）は 2重化で膨れたライブと比較していたため信用できず、
  ADR 0106 の特例と合わせて選択規則が 4 分岐に膨らんでいた。

## 決定

### 1. ライブ側もツールの呼び出しと結果を 1 セルへマージする（根本原因の除去）

- `SubAgentActivityKind` に **`.toolResult` を追加**し、`.tool`（呼び出し）と区別する。
  同じ `.tool` のままフラグを増やす案より、消費点（`ChatSessionViewModel` の 1 箇所）で意図が読めるため enum を選ぶ。
- 送出側は**子の tool_use_id を `itemId` に載せる**: 子 `tool_use` → `(.tool, itemId: item["id"])`、
  子 `tool_result` → `(.toolResult, itemId: item["tool_use_id"])`。
- 受け側 `ChatSubAgentModel` は `itemId` 非 nil の `.tool`/`.toolResult` を stableId `"\(toolUseId)-tool-\(childToolUseId)"` の
  1 つの `commandExecution` へマージする（**呼び出し → `command` 欄 / 結果 → `output` 欄**）。
  `parse` と同じく**順序逆転に非依存**（結果が先着したら command nil のセルを作り、後から来た呼び出しが command を補う）。
- `itemId` が nil の活動は従来どおり独立 item（後方互換。`subAgentNilItemIdActivitiesRemainIndividualItems` が凍結）。

### 2. transcript のソース選択を 2 通りに畳む（ADR 0106 の特例を撤去）

```
1. 永続ファイル（parsed）が読めれば parsed。
2. 読めなければライブ。
例外: 片方だけが reasoning を持つならそれを失わない側（ADR 0025。不変）。
```

- ADR 0106 の `status == .completed` 特例と、件数タイブレーク（`parsed.count >= live.count`）を**両方とも削除**する。
  ライブが parsed と同じ形になった以上、件数で権威を決める理由が無い。
- `.failed` も parsed を採る（ADR 0106 では保守的に件数タイブレークへ据え置いていた）。

**受け入れたトレードオフ（`.failed` × 末尾が切れた JSONL）**: 書き込み途中でプロセスが落ちると、子 JSONL の
最終行が JSON として壊れうる。`SubAgentTranscriptLoader.parse` は解析できない行を読み飛ばすため、この個体では
parsed が末尾の項目を 1 件前後失う。件数タイブレークがあればこのとき live が勝っていた。それでも 2 通りへ畳むのは:

- 失われるのは**末尾の 1 項目前後**であって transcript 全体ではない（行単位の追記なので、壊れるのは書きかけの最終行だけ）。
- 一方で件数比較は実データで **live と parsed の項目数がほぼ拮抗する**（実測の1個体で live 46 / parsed 46 前後）ため
  勝敗が偶然で決まり、live が 1 件でも勝った瞬間に ADR 0106 の欠陥（中間ナレーション全欠落）が再発する。
  失う量が桁違いに大きい方の再発を避ける。
- `.completed`（＝ほぼ全ケース）では ADR 0106 の時点で既に parsed 無条件採用であり、この risk は本 ADR で
  新たに生じたものではなく `.failed` へ範囲が広がるだけ。
- reasoning 優先だけは例外として残す。暗号化されず**ライブにだけ**推論本文が残る個体（ADR 0025 で実測）で
  reasoning を失わないため。`SubAgentReasoningPreferenceAcceptanceTests` が凍結している。

## 棄却案

- **`.tool` のまま itemId だけ載せる**: 受け側が「これは呼び出しか結果か」をイベントから判別できず、到着順の
  first-wins に頼ることになる。`parse` が明示的に扱っている順序逆転・孤児 tool_result と同じ堅牢性を持てない。
- **`.subAgentActivity` に `isResult: Bool` を足す**: 互換性は高いが、種別が 2 箇所（kind とフラグ）に散る。
  消費点が 1 箇所しかないため enum 拡張のコストは小さい。
- **実行中も永続ファイルを読む（ライブ経路の廃止）**: 入力を 1 本に絞れて最も単純だが、`output_file` は完了時にしか
  届かず、開始時点でファイルパスを知る手段（`task_started.task_id` から導出できるか等）が未確認。別途調査とする。
- **ADR 0106 の特例を残したまま 1. だけ入れる**: 冗長な防御が 2 段重なり、「なぜ 2 つあるか」が読めなくなる。
- **件数タイブレークを「ライブが直ったので今度こそ信用できる指標」として残す**: 実データで両者の項目数が拮抗し
  （live 46 / parsed 46 前後）勝敗が偶然で決まる。live が 1 件勝つだけで ADR 0106 の欠陥が再発するため、
  末尾 1 項目の欠落リスクと引き換えに捨てる（上記トレードオフ）。

## 結果

- 実行中・完了後を通じて、サブエージェントのツールが**実数どおり 1 行**で表示される。コマンドは `command` 欄、
  出力は `output` 欄に入り、メイン transcript と同じ形になる。
- 選択規則は 4 分岐 → 2 分岐＋例外 1 に縮む。ADR 0106 は本 ADR で superseded。
- 受け入れテスト:
  - `AcceptanceSubAgentToolIdentityTests`（ClaudeAgentKit）— 送出側が呼び出し/結果を区別し同じ tool_use_id を運ぶ
  - `AcceptanceSubAgentLiveToolMergeTests`（SessionFeature）— 1 ツール = 1 セル・command/output 分離・順序逆転・nil 互換
  - `SubAgentTranscriptSourceRuleAcceptanceTests`（DashboardFeature）— failed でも parsed / 実行中は live へフォールバック
- 既存の凍結テスト `SubAgentIsolationAcceptanceTests.backgroundSubAgentInlineTurnsAreIsolatedFromMain` は
  「子の tool_use / tool_result がどちらも `.tool`」を固定していたため、**種別まで固定する形へ更新**した
  （どのニードルがどの kind で届くかを個別に検証するので、検証は弱まらず強まる）。

現行の構成・データフローは architecture/chat-subagent-display.md を参照。
