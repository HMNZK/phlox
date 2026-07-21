---
status: active
last-verified: 2026-07-04
---

# ADR 0025: サブエージェント別チャットの隔離・表示・transcript 組立

## 文脈

Claude Code セッションが `Task`/`Agent` ツールで起動するサブエージェント（Explore・general-purpose 等）の出力を、メインチャットに垂れ流さず「別チャット」として扱う要求から一連の設計判断が生じた。実データ（Claude Code の stdout `--output-format stream-json` と、子の永続 transcript `~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl`）を突き合わせて判明した非自明な事実が多く、素朴な実装が軒並み外れたため決定を記録する。

観測した実データの事実（いずれも本 run で実測）:

1. **非同期 `Agent` ツールは `run_in_background` フラグを持たない**（親 JSONL 全体で 0 回・`name:"Agent"`）。起動直後の launcher `tool_result` は「Async agent launched successfully. (This tool result is internal metadata — never quote …)」という**起動確認メタデータ**で、出力ではない。
2. **子の `thinking`（推論）テキストの有無はエージェント依存**。Explore 系は 249〜547 字の読める thinking を持つが、レビュアー系・多くの個体は `thinking:""`（署名のみ＝暗号化）で**推論本文が存在しない**。これは stdout 側・output_file 側の両方で空になる。
3. **子の最終レポートは複数チャネルで親に届く**。完了 `tool_result`（`.subAgentOutput`）と、stdout の inline 最終テキスト（`parent_tool_use_id` 付き `.subAgentActivity(.message)`）と、完了 recap（`.subAgentCompleted` summary）が**同一本文**を運ぶことがあり、素朴に積むと二重表示になる。
4. **子 output_file の `tool_use` とその `tool_result` は同一 `tool_use_id`**。これを別 ChatItem 2 個として生成すると `ForEach`/`LazyVStack` が duplicate id で配置ループに入り**スクロールで CPU 固着**（ADR 0010 クラス）、一部項目（reasoning）の描画脱落、呼び出しと結果が別セルで隙間、を招く。
5. **stdout stream と永続 JSONL は内容が異なる**（永続側は inline 子ターンや task_notification を落とすことがある）。永続ファイルの archaeology だけで Phlox の挙動を推定すると誤る。

## 決定

### 1. メイン／サブの隔離
`parent_tool_use_id` がサブエージェント（`subAgentToolUseIds`）のインライン子ターン（assistant thinking/text/tool_use、user tool_result）は、メイン向けイベント（`agentMessageDelta`/`reasoningDelta`/`commandExecution`/`fileChange`）に落とさず `subAgentActivity` として早期 return で隔離する。launcher `tool_result` は `tool_use_id` 一致で `subAgentOutput` に振る。

### 2. 起動確認メタデータの抑制は「署名」で判定（フラグではない）
`run_in_background` は非同期 `Agent` に付かないため信号にできない。**本文が "Async agent launched successfully" で始まり（hasPrefix）かつ "This tool result is internal metadata" を含む**固定署名で判定して `subAgentOutput` 化を抑制する。`hasPrefix` にするのは、正当な出力が本文の途中で 2 フレーズを引用しただけのケースを silent に落とさないため。フォアグラウンドの正当出力は署名を含まず維持される。

### 3. プロンプトは表示する
`Agent`/`Task` の `tool_use` input の `prompt` を `.subAgentActivity(.prompt)` として放出し、別チャット先頭に表示する（既存 inline エコーと同一 id で dedup）。

### 4. 表示形態: シングル＝横並び分割、グリッド＝タイル内置換
シングルビューは overlay ドロワー（本文を覆う）をやめ、**HStack 水平分割**（メインが縮んで両ペイン可視）にする。メイン｜サブの境界は既存 `ResizeGripView`（グローバル座標ドラッグ＋発光バー）で**リサイズ可能**、幅比率は `@AppStorage` 永続（既定 0.42・下限 320pt・上限 60%、クランプは純関数 `SubAgentSplitLayout.paneWidth`）。両ヘッダーを共有固定高 `SubAgentSplitLayout.headerHeight` に揃えて罫線を一直線にする。グリッドは「タイル内でメイン⇔サブを置換」を維持（side-by-side にしない）。

### 5. transcript の 2 ソースと選択
サブエージェント transcript は **ライブ（stdout 由来の `subAgentTranscripts`）** と **parsed（output_file を `SubAgentTranscriptLoader.parse`）** の 2 ソースを持つ。選択規則:
- **片方だけが reasoning を持つなら、reasoning を失わない側を優先**（output_file 側で thinking が空になり reasoning が落ちる個体を救う）。
- どちらも持つ／持たないときは「豊富な方」（`parsed.count >= live.count ? parsed : live`。完了時に出力が縮む＝消える現象の防止）。**〔ADR 0106 で精緻化〕完了済み（`status == .completed`）はこの件数タイブレークより前に parsed を優先する**（ライブのツール2重化で件数が水増しされ、richer な parsed が不当に負けて中間ナレーションが欠落する問題の対策）。件数タイブレークは実行中のフォールバックに限定。
- **暗号化 thinking の個体は推論本文がどのソースにも存在せず表示不能**（Phlox のバグではない）。

### 6. parse は tool_use と tool_result を 1 セルにマージ
`SubAgentTranscriptLoader.parse` は `tool_use_id` で `commandExecution` を引き、`tool_result` を**同一 id の別項目にせず既存項目へ output マージ**する（メイン transcript と同じ「1 ツールコール＝1 セル」）。text/thinking の id には行 index を混ぜ、複数行が同一 `message.id` を共有する実データでの id 衝突も防ぐ。順序（tool_use と tool_result の逆転）にも非依存化する。→ duplicate id を根絶し ADR 0010 クラスの CPU 固着・描画脱落・隙間を同時に解消。

### 7. 完了レポートの重複は「レポート系チャネル」を含む同一本文で dedup
`appendSubAgentTranscriptItem` で、**新規 or 既存の一方が完了レポート系（`-output`/`-summary`）なら、同一本文の agentMessage を追加しない**。inline 最終テキスト（`-message-N`）＋ `-output`、`-output`＋`-summary` の二重を 1 回にする。完了レポート系が絡まない inline 同士の同一本文は、サブが正当に同じ文を複数回出すケースとして両方残す。

### 8. ストリップは実行中のみ
処理が**完了したサブエージェントはストリップ（単一・グリッド両方）から外す**（`stripSubAgents = subAgents.filter { status != .completed }`）。完了後も本文のインラインマーカー（`subAgents` 本体に残る）から閲覧できるので、`subAgents` からは消さない。失敗は気付けるよう残す。

## 棄却案

- **メタデータ抑制を `run_in_background` フラグで判定**: 非同期 `Agent` はフラグを持たず永久に空振り（実データで確認）。署名判定に切替。
- **署名を AND-contains（先頭一致なし）で判定**: 正当な出力が 2 フレーズを引用しただけで silent 抑制される。`hasPrefix` 化で回避。
- **暗号化 thinking にプレースホルダ「推論（非公開）」を出す**: 推論の中身が無い個体で行だけ増えるノイズ。既定は「何も出さない」。将来必要なら別途。
- **parsed を常に優先（Option B）／ライブを常に優先**: 前者は暗号化で reasoning を失い、後者は純非同期で薄い。reasoning 有無で条件分岐する現行案に落ち着いた。
- **完了レポートの重複を全 agentMessage の content 一致で dedup**（初版）: サブが正当に同一本文を複数回出す inline を巻き添えで落とす。レポート系チャネルを含む対に限定して解決。
- **永続 JSONL の archaeology だけで原因特定**: stdout と内容が異なり誤誘導される。表示層（ViewModel の transcript 組立）を冪等化する方針に切替え、受け入れテストで固定した。

## 結果

- サブエージェント出力はメインに漏れず、別チャットとして表示。プロンプトが先頭に出る。
- シングルは横並び＋リサイズ＋罫線一直線、グリッドはタイル内置換。CPU 収束を実機確認済み。
- 完了後スクロールの CPU 固着・reasoning 脱落・ツールコールの隙間・出力の二重表示を解消。
- 暗号化 thinking の個体は reasoning 表示不能（データ制約。ドキュメント化して既知とする）。
- 受け入れテスト（`SubAgentPromptDisplayAcceptanceTests` / `SubAgentSplitLayoutAcceptanceTests` / `SubAgentTranscriptMergeAcceptanceTests` / `SubAgentReasoningPreferenceAcceptanceTests` / `SubAgentOutputDedupAcceptanceTests` / `SubAgentStripFilterAcceptanceTests` 等）で各契約を凍結。DashboardFeature 564 green・ClaudeAgentKit 70 green・ヘッドレス E2E 17 green。

現行の構成・データフローは architecture/chat-subagent-display.md を参照。
