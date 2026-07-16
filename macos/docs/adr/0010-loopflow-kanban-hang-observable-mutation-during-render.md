---
status: active
last-verified: 2026-07-04
---

# ADR 0010: Loopflow カンバン盤ハングの真因＝描画中の @Observable 変更（再発・再修正）

> **SUPERSEDED by ADR 0020（2026-06-30）**: Loopflow サブシステムはコードベースから削除された（命題逸脱の是正）。本 ADR は歴史的記録。
>
> **例外: frontmatter の status は active を維持する**。Loopflow 機能自体は ADR 0020 で削除されたが、本 ADR が記録する「描画中の @Observable 変更による無限再無効化」という教訓は普遍のため、機能削除後も active として参照可能に保つ。

- ステータス: Accepted（実装・runtime 検証済み、feature/fix-kanban-hang-residual）
- 作成日: 2026-06-15
- コンテキスト: ADR 直前の修正（dev `025d41f`「Loopflow カンバン盤メインスレッド・ハング修正: リロード非同期化/
  状態購読削減/GeometryReader 撤去」）後も、**承認待ちカードを盤に表示すると 100% CPU でハングが再発**していた
  （実機 PID 74381 等で再現）。真因が前回の想定（GeometryReader×LazyVStack のレイアウト非収束）とは異なっていたため、
  真因・誤診の経緯・検証方法を記録する。

## 1. 真因
`LoopflowDashboardViewModel.isPending(run:)` は `LoopflowKanbanCard` の **view body 評価中**に呼ばれるが、内部で
`pendingApprovalIdentitiesByRunKey.removeValue(...)` により `@Observable` 追跡対象の state を **mutate** していた。
SwiftUI では body/layout 評価中に観測 state を変更すると「無効化→再評価→また変更→…」の無限再無効化になり、
`GraphHost.flushTransactions()` が収束せずメインスレッドが 100% に張り付く。承認待ち（`isPending` が評価される）
カードでのみ発火した。`removeValue` は「stale な送信済みマーカーの GC」であり、`isPending` の返り値には影響しない
（純粋化しても挙動は不変）。

## 2. 決定事項（修正）
- `isPending(run:)` を**純関数**化（観測 state を一切 mutate しない読み取り専用）。返り値は従来と同値。
- stale マーカーの GC を純関数 `reconcilePendingMarkers(_:against:)` に切り出し、**描画経路外**の
  `refreshSessionStatuses(for:)`（`LoopflowDashboardView` の `onAppear` / `onChange(of: runStore.runs)` から呼ばれる
  データ変化駆動経路）へ移設。これで render 中の @Observable mutation を完全に除去しつつ、マーカーの無限増加防止と
  「送信済み」表示・二重送信ガードを維持する。

## 3. 誤診の経緯（重要な教訓）
本件は **2 つの仮説が runtime 検証で棄却**された後に真因へ到達した:
1. 前回修正が残した `LoopflowProgressView` の GeometryReader → 撤去しても 100% ハング継続（棄却）。
2. `approvalPanel` の縦軸 `TextField(axis:.vertical)` → 単一行化しても 100% ハング継続（棄却）。
3. `isPending` の描画中 mutation → 純粋化で CPU が 0.x% に収束（真因確定）。

`grep GeometryReader == 0` と `swift test green` は**いずれの誤った修正でも満たされた**。静的根拠＋単体テストだけでは
この種の「描画中 state 変更による無限再無効化」を捕捉できない。

## 4. 検証方針（本クラスのハングに必須）
- **runtime 検証を done 条件に必須化**: 実 Debug を起動し、承認待ちカードを盤に表示（AppleScript の System Events/AX で
  loopflow トグル `point.3.connected.trianglepath.dotted` を `AXPress`）→ `ps`/`top` で **CPU が一桁%へ収束**することを確認。
  本件では旧ビルド 100% 固着 ↔ 修正版 0〜0.6% を対比確認した。
- 単体テストでは「`isPending(run:)` を呼んでも観測 state が変化しない（`withObservationTracking` で onChange 不発火）」を
  符号化して再発防止する。GC は public API 経路（approve→refreshSessionStatuses→再 approve）で検証する。

## 5. 影響
- 承認待ちカードを含む loopflow 盤の表示でメインスレッドがハングしない。`isPending` の返り値・承認/差し戻し/送信済み表示は不変。
- 一般則: **SwiftUI の view body / 派生プロパティから @Observable state を mutate しない**（GC・遅延初期化・キャッシュ更新は
  データ変化イベント側で行う）。

## 6. 関連
- 前段の不完全修正: dev `025d41f` / `9edff1f`（GeometryReader 撤去等。本 ADR の真因は別レイヤ）。
- `0008-loopflow-task-launcher.md`（loopflow ランチャー/カンバンの設計）。
