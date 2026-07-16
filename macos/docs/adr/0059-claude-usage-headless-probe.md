---
status: superseded
superseded-by: 0061-claude-usage-get-usage-piggyback.md
last-verified: 2026-07-10
---

# ADR 0059: チャットモードの Claude Usage は `/usage` ヘッドレスプローブで供給する

> **superseded（2026-07-10）**: [ADR 0061](0061-claude-usage-get-usage-piggyback.md) が常駐チャットプロセスへの `get_usage` control_request 相乗りへ一本化し、本プローブは実装ごと削除された。

> **このファイルの役割**: ADR 0039 が「供給なし」と認めたチャットモード運用で、Usage を更新できるようにした供給経路の決定理由。
> **書かないもの**: パーサ・プローブの実装詳細（→ Packages/DashboardFeature/Sources/DashboardFeature/Usage/ClaudeUsageProbe.swift）。

## 文脈

ADR 0039 は「Claude の 5h/7d 残量は statusLine フック（ターミナルセッション実行時）だけが供給源」と認め、チャットモード運用ではキャッシュの stale 化を鮮度注記で可視化する方針を採った。その後もチャットモード中心の運用では Usage が更新されない不満が残った（2026-07-09 ユーザー報告）。

調査スパイク（task-5, Codex）で structured event / CLI サブコマンド / ローカルファイルに供給が無いことを再確認したうえで、PM 追試により **`claude -p '/usage' --output-format json --no-session-persistence` が API 呼び出しゼロ（duration_api_ms=0・total_cost_usd=0）・約1.6秒で 5h/7d 使用率とリセット時刻の人間向けテキストを返す**ことを発見した。

## 決定

- キャッシュ（`claude-usage-rate-limits.json`）の dataAsOf が 30 分より古い（または欠落）とき、上記コマンドをヘッドレス実行してテキストを解析し、**既存スキーマ互換の JSON を原子的に書き込む**（statusLine 経路と後勝ち共存）。
- プローブは actor `ClaudeUsageProbeService` で **fire-and-forget**（fetch をブロックしない）・single-flight・15 分スロットリング（失敗時も）・15 秒タイムアウト・`phlox.usage.claudeScrape == false` の尊重。
- 解析は**失敗時に誤値ではなく nil** に倒す（年なし日付は「now 以降の直近」で推定・分省略/12時間制対応・不正な埋め込みタイムゾーンは reset を nil・「all models」行のみ採用）。
- ADR 0039 の表示仕様（行を消さず鮮度注記）は**変更しない**。キャッシュが新鮮になれば注記は自然に消える。0039 は supersede せず、供給源を1つ追加する拡張として扱う。

## 棄却案

- **不可視 PTY での定期プローブ**（ADR 0039 時点の案）: セッション起動コスト・端末エミュレーション複雑性で棄却済み。`claude -p` は同じ成果をプロセス1発で得られる。
- **statusLine 相当の常駐**: チャットモードでは claude CLI 自体が長寿命プロセスとして動かない（app-server 経由）ため成立しない。

## 結果

- チャットモードのみの運用でも、アプリ起動直後（キャッシュ欠落時）と 30 分ごとに Usage が自動更新される（実機確認済み 2026-07-10）。
- 供給テキストは機械可読契約のない人間向け文字列であり、CLI の出力形式変更で静かに壊れうる。解析失敗は nil（stale 表示維持）に倒れるため誤値は出ないが、**更新が止まったらまず実 CLI の出力形式を疑う**こと。
