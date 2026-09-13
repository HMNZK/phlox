---
task: task-51
status: completed
---

# task-51 開示レポート

UX-11a。Claude JSONL / Codex 履歴の同一走査内で、表示用タイトルの材料 `titleUserMessages` / `titleSummary` を entry へ載せる。タイトル選定・UI・loader・既存 preview は変えていない。

## 詰まった点

受け入れ 2 本（Claude 文字列本文、Codex `response_item`）が `entry.fileURL == 書き込み URL` で落ちた。実体は同一ファイルだが、`FileManager` 列挙が `/private/var/folders/...`、harness の `temporaryDirectory` が `/var/folders/...` で `URL ==` が不一致。テストは改変禁止のため、列挙結果を discovery に渡したルート（`projectDir` / `sessionsRoot`）上のパスへ載せ直した。コンストラクタの既存ラベル引数 `fileURL: fileURL` / `fileURL: candidate.url` は維持。ホーム配下の実履歴パスは symlink 経由ではないため、通常の値は変わらない。

## できた風だが実は未完

- 表示モデル・履歴 UI・起動配線は task-49。本タスクの成立を UX-11 全体の完了と扱わない。
- App リンク（契約の `xcodebuild`）と `verify.sh` 全量は、今回の指定検証に含まれておらず未実行。
- `titleUserMessages == nil` は旧 initializer 専用。取得器は空でも `[]` を渡す。表示側が代替 preview を使うのは task-49。

## 置いた前提

- Claude の `isMeta` 除外は新規材料の append だけ。`firstUserLine` の `hasPrefix("<")` と loader には流用しない。
- Codex 既存 preview は従来どおり `messageText(..., role: "user")`（role を見ない）。材料だけ `messageRole == "user"`。
- Codex DB の `titleSummary` は列 2 の加工前。NULL は `nil`、空文字・空白のみはそのまま。ユーザー材料は列 3 が NULL・空・空白のみなら `[]`。
- 共有パーサは `ParsedLine.isMeta` の読み取り追加に限定。`extractUserText` / `extractTextContent` は未変更。
- GUI 起動・課金セッションなし。

## 契約からの逸脱

上記 fileURL のルート揃え。材料契約の範囲外だが、凍結テストの URL 一致を製品側で満たすための最小変更。rb の既存引数比較は通過。SQL・bind・readonly・DB 優先・200 行 / 512 KiB 打ち切りは未変更。

## レビュー重点

- 材料の忠実性: 改行・長さ・出現順。`isMeta == true` と assistant/system/tool を混ぜない。
- `nil` と `[]` の区別。既存 preview / firstUserAt / gitBranch / 候補採否がメタ行でも従来値。
- loader が `/review`・メタ本文・貼り付けを従来どおり返すこと、fixture バイト列が不変なこと。
- Codex で既存 preview 選定と材料収集が分離されていること。
- fileURL ルート揃えがホーム配下の実パスを変えていないこと。

## 検証原文

指定コマンド。成功時 compact-test は 1 行圧縮。`--full` で得た下位コマンドの原文も併記。

```
$ ~/.agents/scripts/compact-test t51-selftest ruby .claude/scripts/task51-wiring.rb --selftest
t51-selftest: OK（要約未対応）
task51-wiring --selftest: OK

$ ~/.agents/scripts/compact-test t51-rb env TASK51_BASELINE=a2c5882 ruby .claude/scripts/task51-wiring.rb
t51-rb: OK（要約未対応）
task51-wiring: OK

$ (cd macos/Packages/DashboardFeature && ~/.agents/scripts/compact-test t51-DashboardFeature swift test)
✔ Test run with 1761 tests in 176 suites passed after 23.716 seconds.

$ git diff --check
(exit 0, 出力なし)
```

変更パス: `ClaudeSessionHistoryEntry.swift`, `ClaudeSessionHistory.swift`, `CodexSessionHistory.swift`, `docs/agent-output/task-51.md`。
=== REPORT COMPLETE ===
