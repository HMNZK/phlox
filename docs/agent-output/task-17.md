---
task: task-17
status: completed
---

task-17（UI-05）の実装を完了しました。コミットはしていません。Release Phlox（PID 61465）には触れていません。

**変更**（`macos/App/SettingsView.swift` のみ）
- 「通知テスト」「エージェント管理を開く」「今すぐ確認」の `.buttonStyle(RichButtonStyle())` を `.buttonStyle(.bordered)` に置換
- その 3 箇所の `.focusEffectDisabled()` を削除
- `RichButtonStyle`（内部 `StyledBody` 含む）と直前の説明コメントを削除

action・ラベル・管理アイコン・`.disabled(!appUpdater.canCheckForUpdates)`・他の `.borderless` / `.plain` はそのままです。

**機械検証（いずれも GREEN）**
- `ruby .claude/scripts/task17-wiring.rb --selftest` → `task17-wiring --selftest: OK`
- `TASK17_BASELINE=7fff82b` の製品配線 → `task17-wiring: OK`
- `git diff --check` → 問題なし
- Debug App ビルド → `** BUILD SUCCEEDED **`

警告は destination の複数一致（arm64 を採用）と AppIntents メタデータ欠落の 2 件だけで、今回の差分とは無関係です。

開示レポートは `docs/agent-output/task-17.md`（`status: completed`）です。PM 目視・AX 焦点・GUI 起動は契約どおり未実施です。配線の自己検査は成功しています（`task17-wiring --selftest: OK`）。task-17 の実装結果に変わりはありません。
- **Release Phlox（PID 61465）は未操作・未終了**。今回の Debug 成果物も起動していない。

## 置いた前提・仮定

- `TASK17_BASELINE` は契約 frontmatter の `baseline_commit: 7fff82b` をそのまま使った（HEAD フォールバックなし）。
- 凍結済み `.claude/scripts/task17-wiring.rb` はバイト単位で未改変の前提で実行した（スクリプト側が凍結 blob 照合する）。
- `.buttonStyle(.bordered)` は旧 `.buttonStyle(RichButtonStyle())` と同一の修飾位置に置いた。「今すぐ確認」は `.disabled(!appUpdater.canCheckForUpdates)` の直前という既存順序を維持し、その後にあった `.focusEffectDisabled()` だけを削除した。
- DerivedData は指示どおり既存パス `/tmp/phlox-t13-visual.SPfR9c/Build` を再利用した。専用クリーンビルドではない。
- `xcodebuild -destination platform=macOS` は複数 destination のうち先頭（arm64 / My Mac）を採用する。これが本機の意図した Debug ビルドである前提。
- 設定内の主操作用強調ボタンは契約記載どおり対象 3 件以外に無い。ヘッダーグラデ・Form tint・テーマ／アイコン選択・失効の `.borderless` + destructive は装飾／共通色／別操作であり、削除対象に混ぜていない。

## 契約からの逸脱

なし。変更ファイルは `macos/App/SettingsView.swift` と本開示レポートのみ。テスト新規作成なし。`RichButtonStyle` の代替 style・`.borderedProminent`・`.focusable(false)`・親への焦点抑制移設は行っていない。

## レビュー重点（PM 用・レビュアーには渡さない）

- 「今すぐ確認」の修飾順が `.buttonStyle(.bordered)` → `.disabled(...)` のままか（焦点抑制削除で `.disabled` が末尾になった）。配線検査は許可差分の局所除去後に固定 SHA と比較するため、順序の取り違いはここで落ちる想定だが、目視でも確認してほしい。
- 対象外の `.buttonStyle(.borderless)`（失効）と `.plain`（テーマ／アイコン行）が残っていること。`.bordered` が別 Button に漏れていないこと。
- `RichButtonStyle` / `StyledBody` / 専用 3 行コメントがファイル末尾付近から完全に消えていること。呼び出し残や同名の再定義が無いこと。
- 5 タブ接続・Section 順・action / Label / 管理アイコン / 更新 disabled / Binding は diff 上無変更。独立レビューは固定 SHA 比較の wiring 原文と `git diff` で判定できる。
- 実画面では標準 bordered の薄い陰影が残る。独自グラデ・発光枠・影が消えたかの判定は PM 目視。AX `set focused` が失敗したら契約どおり未達 vis 記録（OS 設定変更で回避しない）。

## 検証（実走コマンドと原文）

### 1. wiring --selftest

```
$ ruby .claude/scripts/task17-wiring.rb --selftest
task17-wiring --selftest: OK
```

exit 0（所要 35713ms）。GREEN。

### 2. 製品 wiring（baseline 7fff82b）

```
$ env TASK17_BASELINE=7fff82b ruby .claude/scripts/task17-wiring.rb
task17-wiring: OK
```

exit 0。GREEN。

### 3. git diff --check

```
$ git diff --check
```

出力なし、exit 0。

### 4. App Debug ビルド

```
$ cd macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t17.log 2>&1
```

シェル EXIT:0。ログ末尾:

```
** BUILD SUCCEEDED **
```

警告（ログ全文から `warning` を列挙）:

```
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006040-001011C92228801C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006040-001011C92228801C, name:My Mac }
```

```
2026-09-13 11:32:49.528 appintentsmetadataprocessor[39520:36709111] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
```

Swift コンパイル警告は無し。上記 2 件は destination 複数一致と AppIntents メタデータ欠落で、今回の SettingsView 差分とは無関係。

作業ツリー（レポート書き込み前）: `macos/App/SettingsView.swift` のみ変更（3 insertions, 91 deletions）。コミットしていない。

=== REPORT COMPLETE ===
