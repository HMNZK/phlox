---
task: task-46
status: completed
---

# tests-task-46-r2

採択項目（MUST1, HIGH2–8, MED9–12）を退避先3ファイルへ反映した。製品コード・契約・台帳は未変更。

## 指摘ごとの反映

### MUST1（同一入力の相反期待）
- `tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift:73-84` — 共通関数は `userOverride ?? defaultExpanded`。回答の `userOverride: false` は閉。
- `.claude/scripts/task46-wiring.rb` `check_answer` — 回答 View が詳細用 Binding / DisclosureCard に依存しないことを検査。

### HIGH2（task-47 `AgentMessageBody` 経路）
- `task46-wiring.rb:668` `reasoning_body_ok?` — `Text(text)` / `RichMarkdownView` / `AgentMessageBody(text:, bodyColor:)` を許容。
- `task46-wiring.rb:1339` — 正常 fixture は `AgentMessageBody(text: text, bodyColor:)`。Basic 側で `RichMarkdownView(..., bodyColor:)` へ転送するまで追跡。

### HIGH3（配線をモデル結果と対応）
- 実カードの `presentation.heading` / `subtitle` / `semanticInk`、Binding getter/setter、`header.shouldRender`、活動 AX（`state.orbLabel` 2箇所）、エラー見出しをモデルから取る検査。負例は各1変更。

### HIGH4（コメント内偽宣言・未使用）
- `task46-wiring.rb:181` `code_only_indexed` — 宣言抽出はコード領域のみ。
- `live_code` / `model_used?` — 未使用 `let`・`_ =` 破棄を接続としない。負例: 偽宣言・未使用変数・戻り値破棄。

### HIGH5（実変更一覧と恒久構造）
- `task46-wiring.rb:864` `extra_changed_product_paths` — 本番は B46 からの `git diff` / untracked を取得（`1656`）。
- `task46-wiring.rb:896` `permanent_structure_errors` — CommandGroupHeader / コピー / visibleSections / タスク glyph·AX / SubAgentMarkerCell 等を恒久比較。

### HIGH6（typography を役割別に）
- `task46-wiring.rb:629-643` — フォント役割・倍率・余白・行間を別エラー。`ChatScaledFont` は `scale` 引数のまま `TranscriptTypography` へ委譲することを確認。負例は各1箇所退行。

### HIGH7（環境変数なしでアサーション回避しない）
- `PMTranscriptVisualTask46Tests.swift:22,88` — 固定シナリオは常時実行。ウィンドウ表示・操作待ちだけ `PHLOX_PM_VISUAL_TASK=46`。

### HIGH8（目視ハーネス再作成）
- `PMTranscriptVisualTask46Tests.swift:213` `@Observable` シナリオ。操作ボタン（同長置換・空白・再表示・実行開始/終了、幅360/720、倍率0.8/1.0/2.0、明暗）。
- 単体経路は `ChatItemView`（`cmd-single`）。1件グループは非コマンドで隔離（`cmd-one-group`）。51件 `c01`–`c51`。501行差分。
- composer / transcript / 計測ホストへ同じ `defaultAppStorage(suite)`（`329,370,443`）。同一ホスト上で更新。

### MED9（実切り出し）
- `AcceptanceTranscriptItemPresentationTests.swift:243-265` — `FileChangeCell.visibleSections` を 500 行表示・残り1・copy 全文へ照合。
- 同 `582-619` — 単体行 ID は `ChatItemView` が保持する item / isRunningCommand 経由。

### MED10（selftest 1変更1期待）
- 補足/実行状態、エラー見出し/色、フォント/余白/行間/倍率、描画窓/20行上限を分割。
- `evaluate_checks`（`990,1574,1596-1612`）で未設定 / `0` / `1` の本番判定を厳密比較。

### MED11（terminate）
- `PMTranscriptVisualTask46Tests.swift:110-144` — 正常・失敗の両経路で `await viewModel.terminate()` とウィンドウ解放。

### MED12（不存在と git 障害）
- `task46-wiring.rb:253` `git_show_result` + `483` `blob_fetch_errors`。tree に無い新規製品ファイルは欠落、存在する blob の取得失敗は stderr 付きエラー（`1574`）。

## selftest 原文

```
$ ruby ".claude/scripts/task46-wiring.rb" --selftest
task46-wiring --selftest: OK
```

exit 0

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift
$ echo parse_acceptance_exit=0
parse_acceptance_exit=0
$ xcrun swiftc -parse tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift
$ echo parse_visual_exit=0
parse_visual_exit=0
```

stdout 空。exit 0。コンパイル RED は未実施（PM 再凍結時）。

## 見送った点と理由

- Swift テストのコンパイル / 実行 RED は指示どおり `swiftc -parse` のみ。未実装シンボルの RED は PM 再凍結時。
- `PHLOX_PM_VISUAL_TASK=46` のウィンドウ操作・撮影は未実行。常時アサーション側でシナリオを固定。
- ChatItemView 行到達は body と同一の表示ガードを View 保持値へ適用（ViewInspector なし）。
- Reduce Motion 実機確認は契約の実装後 PM 目視であり、本ジョブ対象外。
=== REPORT COMPLETE ===
