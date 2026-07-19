---
status: active
last-verified: 2026-07-19
---

# 0100: Thinking 中の作業要約（recap）をヒューリスティック抽出＋ツール活動から導出する

> **このファイルの役割**: 長い Thinking 中に「いま何をしているか」を薄グレーで示す recap 機能の、要約方式（LLM を使わない）・表示ゲート（閾値）・共有コア設計の決定と理由を記録する。
> **書かないもの**: 現行の実装仕様（→ コード `AgentDomain/ThinkingRecap.swift`・`SessionFeature/ChatRecap.swift`・iOS `Features/SessionDetail/ChatRecapIOS.swift`）、run の作業経緯（→ `delivery/0007-thinking-recap-and-markdown-list-fix-worklog.md`）。

## 文脈

Thinking（推論）が長く続くとき、ユーザーには実行中ターンの reasoning テキスト末尾数行がそのまま薄グレーで見えるだけで、「いま何をしているか」の意味が伝わらない。macOS は `runningReasoningPreview`（reasoning 末尾3行）、iOS は `thinkingPreview`（末尾 reasoning 全文）を出していたが、いずれも**生の思考文の切り抜き**であって作業の要約ではなかった。ClaudeCode の recap のように、現在の活動を短く要約して示したい。

要約の情報源は transcript に既に揃っている: reasoning 本文は全文保持され、ツール活動は macOS の `.commandExecution`/`.fileChange`、iOS の `.command`/`.fileChange` から取れる。`currentTool` のような専用フィールドは無く、活動要約は transcript から導出するしかない。

## 決定

1. **要約方式は「ヒューリスティック抽出＋ツール活動ベース」とし、LLM 要約は採らない**。LLM 要約はコスト・遅延・プライバシー・オフライン性の点で常時表示のインジケータに不適格。代わりに (a) 直近のツール活動（コマンド実行／ファイル読み書き）を活動ラベルに写像し、(b) ツール活動が無ければ reasoning 本文から見出し行（先頭 `#` を剥がす）または末尾非空行を短く抜き出す。
2. **表示は「Thinking が長い時だけ」＝閾値ゲート**。実行中（running）かつターン開始からの経過が閾値（既定 `defaultThreshold = 5` 秒）以上のときだけ recap を出す。閾値未満・非 running では `nil`（従来の生プレビューも recap に置き換える）。
3. **要約コアは共有パッケージ `AgentDomain` に純粋関数として1回だけ実装**する（`ThinkingRecap` / `RecapActivity`）。iOS は `AgentDomain` を相対パス参照しているため（ios ADR 0001）、コアを両OSで再利用できる。活動ラベルは日本語固定（`… を実行中`／`… を読み込み中`／`… を編集中`）で最大 60 文字（超過時は `prefix(60)+"…"`）。
4. **ビューモデル配線は各OSで別実装**。transcript モデルとストリーミングは macOS 専用、iOS はサーバ polling の独自 `ChatMessage` のため、`ChatRecap.derive(transcript:status:turnStartedAt:now:threshold:)`（macOS）と `ChatRecapIOS.derive(messages:status:elapsed:threshold:)`（iOS）が各モデルから共有コアへ橋渡しする。導出は「最後の user 発話以降」を対象にし、最新のツール活動を優先、無ければ reasoning ヒューリスティック。時間駆動更新は `TimelineView`（macOS は recap クロージャ、iOS は `.periodic`）で行い、body 評価中の状態変更はしない（ADR 0030 準拠）。

## 棄却案

- **LLM で reasoning を要約**: 常時表示のインジケータに対しコスト・遅延が見合わず、オフライン・プライバシーの制約にも反する。棄却。
- **要約コアを macOS/iOS で二重実装**: 同じヒューリスティックが drift する。`AgentDomain` の共有純粋関数に集約し、受け入れテストを両OSで著せるようにした。
- **専用の `currentTool` フィールドを transcript モデルに足す**: モデル拡張とストリーミング両OS改修が要り、既存の `.commandExecution`/`.fileChange` から導出できるため過剰。棄却。

## 結果

- `AgentDomain.ThinkingRecap`（純関数）＋ macOS `ChatRecap`／iOS `ChatRecapIOS` を新設。凍結受け入れテスト（`ChatRecapAcceptanceTests`・`IOSChatRecapAcceptanceTests`・`ThinkingRecap` 白箱）で、閾値ゲート・活動ラベル・reasoning 見出し抽出・最新活動優先・最後の user 以降スコープを決定論検証。
- `swift test` 全数 green（AgentDomain 167／PhloxKit 413／SessionFeature 209／DashboardFeature 1383、0 failures）。
- Debug ビルドでの目視（長い Thinking での薄グレー要約表示）はユーザーが確認済み（「確認できた」）。
