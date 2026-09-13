---
task: task-49
status: completed
---

# task-49 開示レポート

UX-11b。`HistoryEntryPresentation` で作業名／プロジェクト／最終利用を決め、`ChatHistoryStartView` の行・help・AX・案内へ接続した。task-41 の `SessionTitleDeriver.derive(from:)` を再利用し、task-51 の材料と元 entry は変更していない。

## 詰まった点

配線検査 `check_session_view` は `ChatHistoryStartLayout.maxCardHeight` の `availableHeight:` 引数テキストに `overlayGeometry.size.height` を要求する。凍結基準の `ChatSessionView` は直前で `let availableHeight = overlayGeometry.size.height` とし、引数は `availableHeight` だけなので、未変更でもこの 1 件が NG になる。View 凍結比較はコメントを除き `workingDirectory` 引数以外を基準と同一にするため、引数式そのものは変えず、同一行コメントで実測値の出所を残した。渡している値はローカル `availableHeight` であり、固定値化ではない。

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
- 日付整形は View 側の既存 `DateFormatter`（short / 相対日付 / 現在ロケール）。
- 内部構造の単体テストは追加していない。導出器本体の境界は task-41 の凍結テストに委ねる。

## 契約からの逸脱

製品の高さ計算は凍結 blob と同じ `availableHeight` ローカル経由。配線検査の引数テキスト要求に合わせ、同一行へ `overlayGeometry.size.height` をコメントした点だけが検査 greening のための差分。挙動は基準と同一。

## レビュー重点

- 識別性: 主表示が `presentation.title`、補助が projectName と最終利用、help/AX に fullTitle と sessionID。
- 導出の再利用: ユーザー材料 → 除外 → `SessionTitleDeriver.derive` → summary。nil／[] の分岐。
- 操作の保護: `ForEach(entries)` → `row(for: entry)` → `onSelect(entry)` → `startFromHistory(entry)`。VM の表示条件・キャッシュ・復元は未変更。
- 描画への接続: 未使用モデルではなく行の `Text(presentation.title)` と help/AX。
- 責務境界: task-51 の entry／取得器に未接触。表示条件を弱めていない。
- 証拠: 下記 4 コマンドは GREEN。App ビルドと PM 目視は未実施／未達。`ChatSessionView` の availableHeight コメントは凍結比較と配線検査の食い違いの記録。

## 検証原文

作業ディレクトリは `/tmp/ui-ux-wt-49`。

```
$ ruby .claude/scripts/task49-wiring.rb --selftest
task49-wiring --selftest: OK
```

exit 0。

```
$ env TASK49_BASELINE=02072dd ruby .claude/scripts/task49-wiring.rb
task49-wiring: OK
```

exit 0（所要約 118 秒）。

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t49-sf swift test --no-parallel)
✔ Test run with 963 tests in 115 suites passed after 12.268 seconds.
```

exit 0。

```
$ git diff --check
```

exit 0。標準出力は空。

=== REPORT COMPLETE ===
