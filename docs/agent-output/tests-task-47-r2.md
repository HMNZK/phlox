---
task: task-47
status: completed
---

採択項目を退避先3ファイルへ反映した。製品コード・契約・台帳は未変更。コミットしていない。

## 指摘ごとの反映

### MUST1（基準に task-46 実装が無い）
工程担当（PM）。本修正では `baseline_commit` / `TASK47_BASELINE` を書き換えていない。

### MUST2（`AgentMessageBody` 内の `ChatFontSettings.adjusted`）
- `.claude/scripts/task47-wiring.rb:927` `check_answer` — 余白のみ。倍率は要求しない。
- 同 `659` `scale_applied_in_markdown?`、`669` `scale_applied_in_code_block?`、`1059-1060` — `RichMarkdownView` / `CodeBlockView` の実適用。
- 同 `1280` 正例 `AgentMessageBody` から未使用の倍率計算を削除。

### HIGH3（secondary 転送とキャッシュ実使用）
- `task47-wiring.rb:733` `agent_forwards_body_color?`、`922` 思考側 secondary。
- 同 `881` `theme_cache_used_for_read_write?`、`1050-1052` 見出し色・キャッシュ読書き。
- 同 `1281` 正例 `theme` が `themes[cacheKey]` を読む/書く。負例は各1変更。

### HIGH4（`prepare`／`summary` の入口対応）
- `task47-wiring.rb:758` `init_prepare_binds_source?` — `prepare(markdown)` 以外（空文字含む）は未接続。
- 同 `819` 通常／streaming／色引数／補正消費を独立検査。
- 同 `728` `summary_wired?` は `summary:TranscriptMarkdownPresentation.summary(text)` のみ。負例: 空文字・`if false`・未使用関数・`summary: nil`。

### HIGH5（着手時範囲）
- `task47-wiring.rb:1125` `product_tree_path?` — `macos/`・Package 定義（Tests/docs/tasks 以外）。
- 同 `1087` `residual_agent_message_body_errors`、`1103` `residual_reasoning_errors`。
- 同 `1167` `RunningTurnStatusView`、`1413` 正例に同宣言。

### HIGH6（折り返し・リンク・コピー・禁止先）
- `task47-wiring.rb:1025` `wrap_errors` が `wrap_ok?` を呼ぶ。
- 同 `1002` `copy_ok?` — 関数不在は失敗。`994` `link_ok?`。`976` `code_summary_leak?`。
- 同 `1138` 恒久構造比較は nil を成功扱いにしない。

### HIGH7（必須ファイル欠落と git 障害）
- `task47-wiring.rb:287` `git show` と `cat-file` が共に失敗し rev も解決できないときは git 障害。
- 同 `1071` `protected_symbol_errors` は current/previous nil をエラーにする。

### HIGH8（実カードの表示状態）
- `PMTranscriptVisualTask47Tests.swift:73,156` — 既定閉→展開→同一 ID 更新→空白→再表示を AX（折りたたみ中／展開中）で照合。

### HIGH9（目視シナリオ）
- 同 `80,213` 全文へ戻す。`151,613` 真正の同長 `"**確認"` / `"**更新"`。
- 同 `74,192` 実イベント `agentMessageDelta` 追記。`451,345` コード境界と最新／過去コマンド。

### HIGH10（`UserDefaults.standard`）
- ハーネスから standard の読み書きを削除。テーマ切替ボタンなし。倍率は suite のみ。

### MED11（未被覆リテラル）
- `AcceptanceTranscriptMarkdownPresentationTests.swift:225-227,240-244,441-460` — ATX 空白／タブ、継続行、水平線、情報文字列バッククォート、終了フェンス後の保護解除。

### MED12（UTF-8）
- 同 `32-46` `expectPrepared` / `expectSummary`。`189-196` 冪等は UTF-8。`285-296` 結合文字は NFC とバイト不一致。`342-344` 分割結果の UTF-8。

### MED13（selftest 1違反1集合・本番区切り）
- `task47-wiring.rb:1492` 本番区切りは独立行。`690,1659-1731` フォント／余白／行間／倍率を分割。`if false`・未使用関数・空文字・色未保存・見出し固定・キャッシュ未使用・`summary: nil`・コピー関数不在。

### MED14（overlay と高さ追随）
- `PMTranscriptVisualTask47Tests.swift:400` 製品と同じ下端 overlay と `onGeometryChange`。

### MED15（アクセス範囲）
- 同 `244,475` `Task47VisualScenario` と `Task47VisualClient` をともに `private`。

## selftest 原文

```
$ ruby .claude/scripts/task47-wiring.rb --selftest
task47-wiring --selftest: OK
```

exit 0

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift
$ echo parse_acceptance_exit=0
parse_acceptance_exit=0
$ xcrun swiftc -parse tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift
$ echo parse_visual_exit=0
parse_visual_exit=0
```

stdout 空。exit 0。コンパイル RED は未実施（PM 再凍結時）。

## 見送った点と理由

- MUST1 の基準 SHA 再凍結は PM 工程。
- HIGH10 のテーマ差はハーネスでは扱わない（PM 目視の `-phlox.theme`）。
- ATX 1〜6 と複数行インラインの一部は `String ==` が残る。Unicode 境界と MED11 追加例は UTF-8。
- 子View上書きの負例は `reasoning_body_ok?` が転送欠落と本文未到達のどちらを返すかを `include?` で許容（1変更は維持）。
- Swift のコンパイル／実行 RED は指示どおり `swiftc -parse` のみ。
=== REPORT COMPLETE ===
