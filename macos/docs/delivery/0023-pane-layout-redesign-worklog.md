---
status: completed
last-verified: 2026-07-28
---

# グリッドビュー再設計（分割ツリー）作業ログ

> **このファイルの役割**: この run で何をしたかの経緯・状態スナップショット・積み残し。
> **書かないもの**: 恒久仕様（→ specs/pane-layout.md）、現行構造（→ architecture/session-pane-layout.md）、
> 決定の理由（→ adr/0135）。

## 何を求められたか

「グリッドビューで複数セッションを GUI から自由に配置したい。例えば 3 セッションのとき、
片方を画面半分に、もう半分を上下に分ける」。**今のグリッドビューのことは完全に忘れて 0 から再設計する**。

## 何をしたか

`/agentic-loop`（PM = Claude、独立レビュー = Codex gpt-5.6-terra / effort=high / read-only）で
6 フェーズを回した。ブランチ `feature/grid-layout-redesign`、worktree で隔離。

| フェーズ | 内容 |
|---|---|
| 0 問題定義 | 現状の限界を `file:line` で特定、成功基準 S1〜S9・仮定・制約・リスクを起こす。Codex の独立検証で事実誤り 3 件を訂正 |
| 1 タスク分解 | task-1〜5 に分解。**分解自体も Codex にレビューさせ**、着手前に実バグ経路 1 件（分割線の同一性）と契約の穴 4 件を発見 |
| 2 実装 | 逐次実行（最大並列幅が 2 しかなく、SPM のビルドキャッシュ分断が並列の利得を上回るため） |
| 3 独立レビュー | 各タスクを Codex がレビュー。task-1 で退化ケースのバグ、task-4 でドロップ判定の符号バグとカーソル API の不整合を発見・修正 |
| 4 統合検証 | デバッグ版をリリース版と併存起動して実機確認、旧モデル撤去、全テスト＋アプリビルド |
| 5 ドキュメント蒸留 | adr/0135・architecture/session-pane-layout.md・specs/pane-layout.md・本ログ |

## タスクと成果物

| タスク | 内容 | 主な成果物 |
|---|---|---|
| task-1 | 分割ツリーのモデルと幾何計算 | `PaneTree` / `PaneTreeGeometry` / `PaneTreeOperations` / `PaneLayoutPresets` |
| task-2 | 分割線ドラッグの状態機械（ゴースト方式） | `PaneDividerDrag` / `PaneLayoutAction` |
| task-3 | 永続化と `DashboardViewModel` 配線 | `PaneLayoutStore` / `paneLayout` / `paneLayoutForDisplay()` / `handlePaneLayoutAction` |
| task-4 | 描画ビューと分割線 UI・ドロップ判定 | `PaneLayoutView` / `PaneDividerHandleView` / `PaneDropZone` / `PaneDividerInteraction` |
| task-5 | プリセット選択 UI と画面配線 | `PaneLayoutPresetMenu` / `DashboardTopBarControls` / `DashboardDetailView` |
| PM（フェーズ4） | 旧 k×k モデルの撤去 | `GridColumns` 等 5 ファイル＋旧テスト 7 本を削除、`SessionGridView` を薄い殻に |

## 実機確認（フェーズ4）

デバッグ版を**リリース版と併存起動**（別 `derivedDataPath` ＋ `open -n`）してスクリーンショットで確認した。

| 確認項目 | 結果 |
|---|---|
| プリセット「左1枚＋右に2枚」1クリック | 左半分に1枚・右半分に縦積み。旧の等分グリッドでは作れない形 |
| 分割線ドラッグ | ドラッグ中はタイルが動かずゴースト線だけが動き、離した時に 50:50 → 約 64:36 で確定 |
| `.pty` タイル境界での分割線 | 端末タイルの上にゴースト線が描かれ、境界で掴めた |
| アプリ再起動後の保持 | ドラッグで変えた比率が保持されていた |
| タイルのドラッグ移動・分割 | ユーザーの実マウス操作で確認。PM の合成マウスイベントでは開始させられなかった（下記「積み残し」） |

## 検証結果

- `swift test`: SessionFeature **567 tests / 60 suites**、DashboardFeature **1489 tests / 139 suites**、いずれも pass
  （旧モデル撤去でテスト数が減っている）
- `xcodegen generate` ＋ `xcodebuild -configuration Debug`: **BUILD SUCCEEDED**

## 途中で見つけた問題と対処

| 問題 | 対処 |
|---|---|
| 退化ケース（`spacing*(n-1) > length`）でタイルが bounds の外に出る | 実効間隔を `max(0, min(spacing, length/(n-1)))` にし、受け入れテストを追加 |
| ドロップ判定が**符号付き**の比を比較しており、タイル外の角の点で最も遠い辺を選ぶ | 絶対値の比に変更＋「外の点は常に最も近い辺へ split」 |
| 分割線ハンドルが `NSCursor.push/pop` を再導入していた（macOS 15 で定着しない既知の実装） | `dsColumnResizeCursor()` と `pointerStyle(.rowResize)` へ変更 |
| 分割線の同一性を index で持つと、絞り込み中に別の分割線が動く | `PaneDividerID = { split, leading, trailing }` へ再設計（着手前に発見） |
| タイルのドラッグが開始しない | ヘッダーの `.draggable` をゼロ距離 `DragGesture` より先に適用するよう修正（最小 SwiftUI アプリで A/B 実測）。適用順をソーススキャンのテストで固定 |

## 積み残し・注意

- **合成マウスイベントでタイルのドラッグを開始させられない**。同じ合成イベントで Finder のファイルドラッグ・
  最小 SwiftUI アプリ・Phlox のタイル構造を忠実に再現した最小アプリ（ZStack ＋絶対配置・AppKit 本文・
  20Hz 再描画・同じ修飾子）はいずれも成功するのに、Phlox 本体だけ外部の受け皿にもドラッグが届かない。
  原因は未特定。実機の手動操作では動くため機能自体は成立しているが、**この操作は自動 UI テストで回帰を
  検出できない**。旧グリッドのヘッダーも同一コードだったため、今回の作り直しで入った不整合ではない。
- **`reorderSession`（`DashboardViewModel`）は本番の呼び出し元が無くなった**。独立したテストを持つ public API のため
  撤去はスコープ外としたが、次に触るときに整理候補。
- **削除カスケードで `paneLayoutStore.save` が複数回走る**（ADR 0135 の受容残余）。バッチ境界の導入は
  削除カスケード自体の restructure が必要。
- 旧キー `phlox.grid.arrangement.<k>` は削除せず残してある（ロールバック余地）。

## 手法として残す知見

- **タスク分解そのものを独立レビューにかけると、実装前にバグ経路を潰せる**。標準の agentic-loop は
  フェーズ0とフェーズ3にしか敵対レビューを置かないが、フェーズ1にも置いて実バグ 1 件＋契約の穴 4 件を得た。
- **性能保証は「純粋型の契約」に落とすと機械検査できる**。「ドラッグ中に再レイアウトしない」を
  ソースの grep で守るのは脆いが、`changed` が決して確定値を返さない純粋型に切り出せばテストで列挙できる。
- **Codex の read-only サンドボックスでは `swift test` が走らない**（`/tmp/xcrun_db-*` を作れない）。
  テストは PM が実走し、結果をレビュー依頼文に添えて、verdict は「コード読解に基づく指摘の有無」で判定させる。
- **同名プロセスが2つあるとき、System Events の `first process whose unix id is <pid>` は誤解決する**。
  リリース版とデバッグ版が両方 "Phlox" のため、pid 指定が別プロセスに解決された。
  `NSRunningApplication(processIdentifier:)` と `CGWindowListCopyWindowInfo` による
  「クリック点の最前面ウィンドウの pid 照合」に切り替えて確実にした。
