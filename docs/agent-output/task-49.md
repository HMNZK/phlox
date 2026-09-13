---
task: task-49
status: completed
---

# task-49 開示レポート

UX-11b。`HistoryEntryPresentation` で作業名／プロジェクト／最終利用を決め、`ChatHistoryStartView` の行・help・AX・案内へ接続した。task-41 の `SessionTitleDeriver.derive(from:)` を再利用し、task-51 の材料と元 entry は変更していない。レビュー r2 差し戻しで、表示モデルの導出を `@State` に保持し、VoiceOver ラベルを help 相当（作業名全文・プロジェクト・最終利用・元 ID）へ作り直した。`ChatSessionView` の高さ配線（147 行の実測値代入）は未変更。

## 詰まった点

r2 の再導出は、`body` 冒頭の `presentationsBySessionID()` が親の `composerHeight`／GeometryReader 再評価でも走ることが原因だった。前担当の一覧単位 `let` は破棄し、`@State` に `[sessionID: HistoryEntryPresentation]` を置き、初回は `init`、以降は `.task(id:)` と `.onChange(of:)` で `entries`（ID 集合と材料）または `workingDirectory` が変わったときだけ `makePresentations` で辞書を作り直す。body 内での状態更新はしていない。entries に無い ID は新しい辞書に入らない。

AX は配線検査が modifier 引数に `presentation.fullTitle` と `sessionID` を要求する。相対日付の整形は契約どおり View 側のため、モデルに日付入りの単一ラベルは持たせず、`HistoryEntryPresentation.accessibilityDetails(lastUsedText:)` にプロジェクト名・パス・最終利用文言を置き、行で `fullTitle` と `entry.sessionID` と結合した。見た目の Text／help は変えていない。

## できた風だが実は未完

- 契約成功基準 3 の App `xcodebuild`、`verify.sh`、task-41／task-51 回帰配線は、今回指定の 4 コマンドに含まれておらず未実行。
- PM 目視は契約どおり課金なし到達経路が未成立。`visual-task-49.md` を参照し、履歴一覧の目視成功とは扱わない。
- ブラウザ／GUI での操作確認はしていない（表示条件を弱めて到達させていない）。
- 「新規作成」は案内テキストのみ。セッション生成・送信はしない。

## 置いた前提・仮定

- `titleUserMessages == nil` のときだけ `[entry.preview]` を材料にする。`[]` は preview へ戻らない。
- 定型文除外は trim 後の接頭辞 `<` と `Base directory for this skill:` のみ（大文字小文字を区別）。残った本文は改行・先頭空白ごと導出器へ渡す。
- cwd の「空白のみ」は `CharacterSet.whitespacesAndNewlines`（検査の半角空白・タブ・U+3000 を含む）。
- `projectPath` は入力文字列を保持し、末尾 `/` 除去は名前抽出だけ。help のパス不明時は空文字で、架空パスは補わない。
- `rawWorkspacePath` は非 Optional の生パス（空文字あり）。空は「プロジェクト不明」。
- 日付整形は View 側の既存 `DateFormatter`（short / 相対日付 / 現在ロケール）。AX の最終利用も同じ整形を使う。
- 内部構造の単体テストは追加していない。導出器本体の境界は task-41 の凍結テストに委ねる。
- r1 の高さ検査は PM 承認のハーネス修理（decision-log 2026-09-13「task-49 レビュー r1 裁定」）。147 行の実測値代入は維持した。
- 導出キーは `ClaudeSessionHistoryEntry` の Equatable（ID と材料を含む）と `workingDirectory`。`maxCardHeight` はキーに入れない。
- 新しい entry が `@State` に載る前の 1 フレームは、その行を描かない（強制アンラップしない）。

## 契約からの逸脱

なし。公開 API の必須フィールドは維持し、AX 用 `accessibilityDetails` を追加しただけ。製品の高さ計算は凍結 blob と同じ `availableHeight` ローカル経由。

## レビュー重点

- 識別性: 主表示が `presentation.title`、補助が projectName と最終利用、help に fullTitle／projectPath／sessionID。AX は fullTitle・プロジェクト（名とパス）・最終利用・元 sessionID。
- 導出の再利用: ユーザー材料 → 除外 → `SessionTitleDeriver.derive` → summary。nil／[] の分岐。
- 操作の保護: `ForEach(entries)` → `row(for: entry)` → `onSelect(entry)` → `startFromHistory(entry)`。VM の表示条件・キャッシュ・復元は未変更。
- 描画への接続: 未使用モデルではなく行の `Text(presentation.title)` と help／AX。導出は `@State` に保持し、entries／workingDirectory 変化時だけ再計算する。
- 責務境界: task-51 の entry／取得器に未接触。表示条件を弱めていない。ChatSessionView の高さ配線は未変更。
- 証拠: 下記 4 コマンドはすべて GREEN。App ビルドと PM 目視は未実施／未達。

## 検証原文

作業ディレクトリは `/tmp/ui-ux-wt-49`。

```
$ ruby .claude/scripts/task49-wiring.rb --selftest
task49-wiring --selftest: OK
```

exit 0。

```
$ env TASK49_BASELINE=fc8519e ruby .claude/scripts/task49-wiring.rb
task49-wiring: OK
```

exit 0。

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t49-rw2 swift test --no-parallel)
✔ Test run with 983 tests in 118 suites passed after 12.704 seconds.
```

exit 0。

```
$ git diff --check
```

exit 0。標準出力は空。

=== REPORT COMPLETE ===
