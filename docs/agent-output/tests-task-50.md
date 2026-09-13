---
task: task-50
status: completed
---

task-50（UX-10b）の受け入れ検査を新規作成した。製品コード・契約・台帳は未変更。コミットしていない。他担当の未コミットファイルには触っていない。

## 作成物

- `tasks/frozen/staged/AcceptancePermissionWordingTests.swift`（実パス `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptancePermissionWordingTests.swift`。先頭コメントに実パスを記載。Swift Testing。`UIWording+Permissions` 未実装のコンパイル RED が正常）
- `.claude/scripts/task50-wiring.rb`（`TASK50_BASELINE` 必須、契約 `baseline_commit` 一致、HEAD/ブランチ名拒否、祖先確認、基準に `UIWording+Permissions.swift` 不在、凍結テストと rb の blob 同一性、製品配線検査、`--selftest`）
- `docs/agent-output/tests-task-50.md`

## 期待値の出所

正本は `tasks/task-50.md`。task-48 凍結公開面（`enum UIWording` / `enum Key: String, CaseIterable` / `text(_:languageCode:)`）を前提にする。製品の辞書・列挙・出力から期待値を生成していない。各行はテスト内の独立リテラル。

| 検査 | 契約 |
|---|---|
| 公開面 `PermissionAgent` / `PermissionKind` / `permission(agent:kind:value:languageCode:)` / `launchPermission` / `settingsPermissionFooter` | L51-56（名前・引数型・英語は PM がテスト作成時に確定） |
| Claude 権限モード（`default`／`manual` 同一、`dontAsk`≠`bypassPermissions`） | L60-75 |
| Codex 承認方針・実行制限・プロフィール（`never`≠`danger-full-access`、ID と設定値を混同しない） | L77-104 |
| Cursor 承認方式・実行制限・動作モード（`ask` を Claude ルールへ流用しない） | L106-123 |
| 起動時 ON/OFF（組み込み3＋カスタム）と共通 footer | L125-148 |
| ルール区分・画面導入（パスと起動トグルの別設定） | L163-173 |
| 未知値・未設定・各 `nil` | L177-184 |
| 日本語・英語・未対応言語・再取得 | 成功基準 1（L209）、言語規則は task-48 L57-58 |
| 配線：通常/省略メニュー、選択中ラベル、管理画面、ON/OFF、直値置換、Binding/tag/既定値/action/起動引数 | 成功基準 2（L227-256） |
| `--selftest` の正例・負例 | L244-256 |

英語表示名で契約が指定したもの（`Manual` / `Accept Edits` / `Auto` / `Bypass` / `Don't Ask` / `Plan` / `Read Only` / `Full Access` / `Approval` / `Agent` / `Ask`）はそのまま凍結。説明文の英語は契約の「同じ意味」を独立リテラルにした。

## `xcrun swiftc -parse` 原文

作業ディレクトリはリポジトリルート。構文のみ。モジュール解決・型検査はしない（`UIWording+Permissions` 未実装のコンパイル RED は PM が凍結時に実パスへ移して確認する）。

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptancePermissionWordingTests.swift
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と負例の期待エラー集合を `==` で厳密比較する。

```
$ ruby .claude/scripts/task50-wiring.rb --selftest
task50-wiring --selftest: OK
```

終了コード 0。

正例は、契約どおりの接続、説明の折り返し、raw value・未知値の保持、コメント/URL/補間の追加、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、を含む。負例は契約が列挙した「通常メニューだけ修正（省略メニュー・選択中ラベル・管理画面が旧文言）」「dontAsk と bypass の説明交換」「Codex 承認方針と実行制限の混同」「Cursor 動作モードへ承認説明を流用」「カスタムのフルアクセス扱い」「未設定から権限を推測」「Binding / tag / 既定値 / action / 起動引数の改変」「表示時の保存処理追加」「task-48 一般文言の巻き戻し」「コントロール削除」「未使用の正本参照」「基準未設定・HEAD・ブランチ名・契約不一致・実装後自己比較・凍結テストと rb の改変」を、期待配列との `==` で固定している。

本番パス（`TASK50_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` のみ。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **公開 API**: `extension UIWording` に `PermissionAgent`（`claude`/`codex`/`cursor`/`custom`）と `PermissionKind`（11 case、表順、rawValue は case 名）。`permission(agent:kind:value:languageCode:)` が表示名と説明。`launchPermission(agent:displayName:languageCode:)` が行ラベルと OFF/ON。footer は共有のため別関数 `settingsPermissionFooter(languageCode:)`。`UIWording.swift` は変更しない。
2. **言語コード**: task-48 と同じ。主言語（最初の `-` / `_` の前）を大小無視。`en` は英語、`ja` は日本語、空・`zh`・`fr` 等は日本語。
3. **`default` と `manual`**: 同じ表示。メニューへ `default` 項目は増やさない。
4. **`nil` の意味**: Cursor 動作モード `nil` は `Agent`。Codex プロフィール `nil` は未選択（`承認設定` / `Approval`）。Codex・Cursor の設定値 `nil` は `既定（未設定）`。Claude 権限モード `nil` は bypass へ倒さず、未知値説明を返す。
5. **同じ raw value**: `ask` は Cursor 動作モード＝質問、Claude ルール＝確認する、それ以外は未知。`plan` の説明は Claude 権限モードと Cursor 動作モードで別。`allow` の説明は Claude と Cursor で別。
6. **プロフィールと設定値**: `:read-only` の英語は `Read Only`、`sandbox_mode=read-only` は `Read-only`。`:danger-full-access` は `Full Access`、`danger-full-access` は `No sandbox limits`。`never` をプロフィール ID として聞くと未知。
7. **Cursor `unrestricted` の英語名**: 契約指定が無いので `Bypass` を使わず `Skip approval prompts`。Claude の `ask` ルール英語名は `Ask to confirm`（動作モードの `Ask` と区別）。
8. **Plan 見出し**: メニュータイトルは task-48 の `UIWording.text(.planOption)`。権限説明は本タスクの `permission`。
9. **管理画面**: 見える項目名・説明・導入文だけ正本へ。`successMessage` の `displayName` と `key.options(current:)`・tag・apply は維持。権限以外の行は `key.displayName` / `key.explanation`。
10. **カスタム起動行**: `displayName` を補間。組み込み3件は `displayName` を無視して表の行ラベルを使う。
11. **折り返し**: 権限説明に `lineLimit(2)` を残さない。
12. **`baseline_commit`**: プレースホルダのまま。rb 本番は凍結 SHA 設定後。基準に新設 `UIWording+Permissions.swift` がある状態は自己比較として拒否する。`UIWording.swift` は task-48 完成実装として基準に存在してよい。

## 凍結時メモ（PM）

- テストを実パスへ移し、`UIWording+Permissions` 未実装のコンパイル RED を確認する。
- `.claude/scripts/task50-wiring.rb` は gitignore される。凍結コミットでは `git add -f .claude/scripts/task50-wiring.rb` と実パスのテストを同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と `TASK50_BASELINE` の両方に入れる。HEAD / ブランチ名は rb が拒否する。凍結 SHA は task-48 完成実装を含み、task-50 実装を含まない。
- 成功基準 3 の旧検査改訂（`ComposerModeMenuAcceptanceTests`、`task35-wiring.rb`、`task38-wiring.rb`）は本作成の範囲外。

=== REPORT COMPLETE ===
