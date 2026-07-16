---
status: active
last-verified: 2026-07-03
---

# ADR 0024: 復元中の破壊的永続化ゲートと Commands の disabled 条件規約

## 文脈

2件の実害が観測された。

1. **sessions.json / projects.json の巻き添え上書き**: 起動時のセッション復元が部分完了（13件中3件）の状態でアプリが終了すると、永続化の read-modify-write（load 全件→変更→save 全件）が縮退した in-memory 状態を土台に走り、未復元セッションの定義が失われた（実測: 13→3 件）。復元完了まで `CompositionRoot.init` が返らないため、SIGTERM ハンドラの保護パス（`terminateAllAndWait`）も未配線で迂回されていた。
2. **「次/前のセッション」メニューの disabled 固着**: SwiftUI の Commands ツリーは View.body と異なり `@Observable` のプロパティ変更では再評価されない。`.disabled(dashboard?.sessions.isEmpty != false)` のように**可変プロパティの中身**に依存すると、`composition`（@State）が nil→non-nil に遷移した1回のスナップショットで判定が固定され、後からセッションが増えても enabled に戻らない。

## 決定

1. **復元ゲート**: `SessionPersistenceCoordinator` に `beginSessionRestore()` / `completeSessionRestore()` を導入し、復元走査完了まで**エントリ数を減らしうる保存**（sessions / projects とも）を抑止する。復元中の pid 書き戻しは `pendingRestorePIDUpdates` に溜めて走査完了後に一括反映。解除は `defer` でも保証（将来 throwing 化してもゲートが張り付かない）。`CompositionRoot(onDashboardReady:)` で復元開始**前**に `AppDelegate` へ PTYManager / dashboard を配線し、復元中 SIGTERM でも保護パスに入れる。
2. **Commands 規約**: メニューの `.disabled` 条件は **Commands が確実に再評価できる値**（@State 遷移で変わる参照の有無、例 `dashboard == nil`）だけに依存させる。`@Observable` の可変プロパティ（`sessions.isEmpty` 等）を Commands の disabled に使わない。空コレクション時の安全は実行側の guard（`adjacentSessionID` の isEmpty guard）で担保する。

## 棄却案

- 13→3 の単一 write 経路の完全特定を待ってからの修正: 静的に特定しきれず、防御ゲートで失敗モードのクラス全体（縮退状態での destructive save）を塞ぐ方が堅い。
- Commands への sessions 件数の @State ブリッジ: 参照有無への単純化（既存 FontSizeCommands と同型）で足りるため不採用。

## 結果

- 回帰テスト `partialRestore_preservesStoreEntryCountWhenDestructiveSaveRunsDuringRestore` が契約（部分復元中の destructive save 抑止・復元後は従来どおり）を符号化。
- runtime 実測: 起動 0.5s/1s/2s 後の SIGTERM ×3 で sessions=13・projects=4 を保全。メニューは復元後 enabled=true・Cmd+Opt+↓/↑ で切替動作。
- 副作用: セッション0件でもメニューは enabled（実行は no-op）。
