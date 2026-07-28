---
status: completed
last-verified: 2026-07-26
---

# delivery 0014: iOS 単独ツールコールの1行集約（agentic-loop run `ios-single-toolcall-row`）

> **このファイルの役割**: この run で何をしたか・どう検証したか・何を残したかのスナップショット。
> **書かないもの**: 決定の理由（→ [ADR 0026](../adr/0026-ios-single-toolcall-grouped-row.md)）・現行の実装仕様（→ [architecture/overview.md](../architecture/overview.md)）。

## 発端

ユーザー報告（モバイルのスクリーンショット付き）: 「ツールコールが1つの場合でも、『ツール実行 ×15』の行のように1行でまとめてほしい」。
単独のツールコールだけが `$ <長いコマンド>` のモノスペースカードになり、折り返しで**縦6行**を占めていた。

## 進め方

agentic-loop（PM = Claude Code / 実装 = Codex CLI `gpt-5.6-terra`・reasoning effort high / 独立レビュー = Claude `persona-reviewer`）。
モード multi・タスク1件。`dev`(c8fc288) から `feature/ios-single-toolcall-row` を worktree で切って作業（メインチェックアウトに無関係な macOS 側の未コミット作業があったため隔離）。

## 実施内容

| 変更 | 内容 |
|---|---|
| `Features/SessionDetail/SessionDetailToolCallGrouping.swift` | `makeBlocks` の「1件なら `.single`」分岐を削除し、`if let first = pendingCommands.first` で1件以上を必ず `commandGroup` に畳む。doc コメントを新契約（macOS とは意図的に異なる）へ更新 |
| `Features/SessionDetail/SessionDetailToolCallGroupRow.swift` | 展開行の空出力フィルタを `items.count == 1` のときは適用しないようにし、理由をコード内コメントで明示。`shouldRender` は元の `isRunning \|\| !rows.isEmpty` のまま（特例分岐を持たない） |
| `Tests/FeaturesTests/AcceptanceIOSToolCallGroupingTests.swift` | PM が凍結した受け入れテストを新契約へ書き換え（`@Test` 12件）。旧契約「単独は single のまま」を削除し、単独ケースの見出し表記・空出力時の可視性・identity 安定・ジャンプ先解決を追加 |
| `Tests/FeaturesTests/IOSToolCallGroupingWhiteboxTests.swift` | window 末尾1件のケースを新契約へ更新（identity 固定の検証意図は維持）。単独・空出力でコマンド行が残ることの白箱テストを追加 |

ユーザー判断（承認ゲート①）で確定した2点: **見出しは複数件と同一書式の「ツール実行 ×1」**／**対象は `.command` のみ**（`.fileChange`「ファイル変更」行はスコープ外）。

## 検証（すべて実走・出力を確認）

| 検証 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | **491 tests / 100 suites passed**（変更前ベースライン 484 から +7・減少なし） |
| `scripts/lint-raw-values.sh Packages/PhloxKit` | OK |
| `make build`（iPhone 16 シミュレータ・Debug） | **BUILD SUCCEEDED** |
| `make run-ui-test`（XCUITest 17ケース） | **TEST SUCCEEDED** |
| 視覚確認 | `ImageRenderer` で集約行を実レンダリングし、単独が「ツール実行 ×1」の1行（「ツール実行 ×15」と同一の見た目）に収まることを目視確認 |
| 独立レビュー（`persona-reviewer`・2巡） | 1巡目 `needs_changes`（[HIGH] 空出力単独で展開が空になる契約欠陥 → PM が契約修正）→ 2巡目 **pass** |

lint はリポジトリ全体ではなく `Packages/PhloxKit` スコープで実行した。`ios/App/AppRoot.swift:237,625` に
`dev` 由来の raw font literal 違反（`.font(.system(size:))`）が既存で残っており、本 run は `App/` を触らないため対象外にした
（**未修正のまま残る既知の課題**）。

## 残課題（この run では直さなかった）

1. **集約グループの開閉キーがグループ先頭 message の id と同一** — 単独グループではヘッダと唯一の行の開閉状態が共有される。
   2件以上の先頭行でも変更前から存在する既存挙動で実害なしと判断。恒久対策は開閉キーの別名前空間化（→ ADR 0026「既知の残課題」）。
2. **`SessionDetailView.chatRow(for:)` の `.command` 分岐が transcript 経路から到達不能** — `switch` の網羅性に必要で
   `SubAgentDetailView` では今も使うため削除しない。
3. **`ios/App/AppRoot.swift` の既存 lint 違反**（上記）。
4. **デモ経路にチャット transcript のモックデータが無い**（`AppEnvironment+UITesting` の `messages(sessionID:)` が空配列を返す）ため、
   シミュレータのデモ画面ではツールコール行を目視できない。今回は `ImageRenderer` で代替した。
   モック transcript を足せば XCUITest のスクリーンショット検証に載せられる。

## 関連

- [ADR 0026: ツールコールは1件でも集約行に畳む](../adr/0026-ios-single-toolcall-grouped-row.md)
- [architecture/overview.md「ツールコールの集約行」](../architecture/overview.md)
- [ADR 0022: チャット履歴の末尾ウィンドウ描画](../adr/0022-ios-transcript-tail-window.md)（`visibleSlice` の identity 固定契約の由来）
