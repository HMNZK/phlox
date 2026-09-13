---
task: task-45
status: completed
---

# task-45 受け入れ検査

作成物は次の3つ。製品コード・契約・台帳は変更していない。

- `tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift`（実パス: `macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitlePresentationTests.swift`）
- `.claude/scripts/task45-wiring.rb`
- 本レポート

## 期待値の出所

すべて `tasks/task-45.md` 成功基準 1 のリテラル。`SessionTitlePresentation` や `SessionTitleDeriver` の戻り値からは生成していない。状態の組み立てだけ task-44 契約の公開 API（`generated` / `legacy` / `init`）を使う。

| ケース | primary / secondary / fullTitle / AX |
|---|---|
| generated `Rose` | `Rose` / nil / `Rose` / `Rose` |
| derived `ログイン画面を修正` + 花名 `Rose` | 同名 / `Rose` / 同名 / 同名 |
| manual `通知を修正` + 花名 `Rose` | 同名 / `Rose` / 同名 / 同名 |
| manual `Rose` + 花名 `Rose` | `Rose` / nil / `Rose` / `Rose` |
| 空 manual + 花名 `Rose` | `abc123` / `Rose` / `abc123` / `abc123` |
| legacy `Rose` | `Rose` / nil / `Rose` / `Rose` |
| legacy 空名 | `abc123` / nil / `abc123` / `abc123` |
| 33 Character manual + 花名 `Rose` | 同じ33文字 / `Rose` / 同じ33文字 / 同じ33文字 |
| 33 Character derived + 花名 `Rose` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ12345…` / `Rose` / 33文字全文 / 33文字全文 |
| derived 全文 nil（name=`修正`） | `修正` / `Rose` / `修正` / `修正` |
| flower 不一致 name=`Lily` | `Lily` / `Rose` / `Lily` / `Lily` |
| 花名が `" \n"` の manual `修正` | `修正` / nil / `修正` / `修正` |

help の固定リテラル:

- 花名あり derived: `ログイン画面を修正\n花名: Rose\n作業場所: /tmp/project`
- 花名なし legacy `Rose`: `Rose\n作業場所: /tmp/project`
- 空 workspace: `Rose\n作業場所: `
- 花名 = primary: `Rose\n花名: Rose\n作業場所: /tmp/project`

fallback は `abc123`、workspacePath は `/tmp/project`（空 workspace ケースのみ `""`）。

## parse 原文

コマンド: `xcrun swiftc -parse tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift`

標準出力は空。終了コード 0。構文のみ。型解決・テスト実行はしていない（`SessionTitlePresentation` / `SessionTitleState` 未実装のコンパイル RED が正常）。

## selftest 原文

コマンド: `ruby .claude/scripts/task45-wiring.rb --selftest`

```
task45-wiring --selftest: OK
```

終了コード 0。実ファイルは変更していない（メモリ fixture）。

## 契約の曖昧点（テストが採った解釈）

1. 33 Character manual の「元花名に従う」は、隣接行に合わせて `flowerName: "Rose"` を渡し、primary と異なるので secondary は `Rose` とした。
2. 33 Character derived の name は、task-41 の 31 Character + `…` を独立リテラルで initializer に渡す。表示側で deriver を呼ばない。
3. derived 全文 nil と flower 不一致は、task-44 initializer の正規化後（manual 退避）を表示する。fullTitle は primary。
4. 「花名が空白だけ」は task-44 と同じ `" \n"`（`.whitespacesAndNewlines`）。空なら secondary なし、help の花名行もなし。
5. 手動名の「保持」は内部改行・内部空白。`effectiveName` による前後 trim は task-44 のまま。
6. 空 workspace の末尾は `作業場所: `（コロンの後は空文字）。パスを補わない。
7. トップバーは `DashboardLeadingTopBarControls` が `router.selectedSession` と `sessionNode(id:)` から titleState を読む。PTY/チャットは同一コントロール。本文へヘッダーを足さない。
8. チームは ID で現在ノードを引き、不在時だけ `.legacy(name:)` と `workspacePath: ""`。子 View は表示モデルを引数で受け取る。
9. 花名条件の再実装禁止は、View が `titleState.flowerName` を比較せず `presentation.secondary` を使うこと。
10. `TASK45_BASELINE` は 40 桁 hex。短い SHA・HEAD・ブランチ名は拒否。契約 `baseline_commit` は解決後 SHA で一致判定。
11. SessionView の既存「開始」行は名前ヘッダーではない。新規ヘッダーは `SessionTitlePresentation` または `Text(viewModel.displayName)` の追加。
12. グリッド本文は `GridChatColumn`。名前は `PaneTileView.header`。`.truncationMode(.tail)` を要求する。
13. 許可パスに `TranscriptTypography` が無いファイルへダミー参照は要求しない。既存の `ChatTypography.bodyFontSize` 委譲は恒久保護。
14. scope 専用は許可パス外の製品差分。単体本文への新規ヘッダーは scope なしでも恒久 NG。

=== REPORT COMPLETE ===
