---
task: task-49
status: completed
---

# task-49 開示レポート

UX-11b。`HistoryEntryPresentation` で作業名／プロジェクト／最終利用を決め、`ChatHistoryStartView` の行・help・AX・案内へ接続した。task-41 の `SessionTitleDeriver.derive(from:)` を再利用し、task-51 の材料と元 entry は変更していない。レビュー r1 差し戻しで、高さ配線のコメント回避を撤去し、表示モデルを一覧単位で一度導出するようにした。

## 詰まった点

配線検査は当初、`availableHeight:` 引数テキストに `overlayGeometry.size.height` が含まれることだけを見ていた。凍結基準の `ChatSessionView` は直前で `let availableHeight = overlayGeometry.size.height` とし、引数は別名だけなので、未変更でも NG になる食い違いがあった。初回実装は同一行コメントで検査を満たしていたが、実行に無関係なコメントによる greening であり、r1 で不誠実と判定された。

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
- r1 の高さ検査は PM 承認のハーネス修理（decision-log 2026-09-13「task-49 レビュー r1 裁定」）。引数からコメント・文字列を除き、`overlayGeometry.size.height` そのものか同一 GeometryReader スコープの `let` 別名代入だけを正例とする。製品のコメント回避は撤去し、147 行の実測値代入は維持した。

## 契約からの逸脱

なし。製品の高さ計算は凍結 blob と同じ `availableHeight` ローカル経由。検査 greening 用コメントは撤去済み。

## レビュー重点

- 識別性: 主表示が `presentation.title`、補助が projectName と最終利用、help/AX に fullTitle と sessionID。
- 導出の再利用: ユーザー材料 → 除外 → `SessionTitleDeriver.derive` → summary。nil／[] の分岐。
- 操作の保護: `ForEach(entries)` → `row(for: entry)` → `onSelect(entry)` → `startFromHistory(entry)`。VM の表示条件・キャッシュ・復元は未変更。
- 描画への接続: 未使用モデルではなく行の `Text(presentation.title)` と help/AX。表示モデルは `entries` と `workingDirectory` から一覧単位で一度導出し、行へ渡す（描画中の観測状態更新や無制限キャッシュは使っていない）。
- 責務境界: task-51 の entry／取得器に未接触。表示条件を弱めていない。
- 証拠: 下記 4 コマンド。selftest／Swift Testing／`git diff --check` は GREEN。本番 rb は rb 自身の基準不一致のみ（想定内）。App ビルドと PM 目視は未実施／未達。

## 検証原文

作業ディレクトリは `/tmp/ui-ux-wt-49`。

```
$ ruby .claude/scripts/task49-wiring.rb --selftest
task49-wiring --selftest: OK
```

exit 0。

```
$ env TASK49_BASELINE=02072dd ruby .claude/scripts/task49-wiring.rb
task49-wiring: NG 基準時点のrb 自身が現在と同一ではない
```

exit 1。rb 自身の基準不一致のみ（想定内）。他の NG は無い。

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t49-rw swift test --no-parallel)
✔ Test run with 963 tests in 115 suites passed after 12.228 seconds.
```

exit 0。

```
$ git diff --check
```

exit 0。標準出力は空。

=== REPORT COMPLETE ===
