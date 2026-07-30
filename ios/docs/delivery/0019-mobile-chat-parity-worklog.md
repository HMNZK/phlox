---
status: completed
last-verified: 2026-07-31
---

# 0019: デスクトップのチャット表示刷新をモバイルへ適用する（作業ログ）

## この run で何をしたか

macOS 1.4.0 で入ったチャット表示の刷新（ADR 0142〜0147）を iOS へ適用した。実装は Codex（gpt-5.6-luna /
effort=max）、独立レビューは Claude `persona-reviewer`（クロスモデル）、進行は agentic-loop の 6 フェーズ。

| task | 内容 | 結果 |
|---|---|---|
| task-1 | 表示の純関数を共有ターゲット `ChatRenderKit`（`macos/Packages/AgentDomain` 内）へ移設し、macOS 側は委譲だけにする | pass（差し戻し 0 回） |
| task-2 | iOS の共通カード器 `DSChatCodeCard` と、共有トークン列 → iOS テーマ色の入口 | pass（差し戻し 1 回） |
| task-3 | ツール実行グループ: 見出しをコマンド原文へ、装飾撤去、シェブロンをタイトル直後、コマンドカード化 | pass（差し戻し 0 回） |
| task-4 | ファイル変更の diff コードビュー（行番号・ハイライト・帯・既定折りたたみ・増減行数・原文コピー） | pass（差し戻し 1 回） |
| task-5 | Reasoning の 1 行化、サブエージェント詳細を同じ器へ、`ChatRowKind` の 1 本化 | pass（差し戻し 1 回） |

決定の蒸留先: [ADR 0041](../adr/0041-chat-render-rules-shared-via-chatrenderkit.md)。

## 状態スナップショット（完了時点）

- `swift test --package-path ios/Packages/PhloxKit`: **693 tests / 135 suites pass**（開始時 643 → +50）
- `swift test --package-path macos/Packages/{AgentDomain,DesignSystem,SessionFeature,DashboardFeature}`: すべて pass
- macOS 側のテストは **1 行も変更していない**（`git diff --exit-code 109d8d9 -- macos/Packages/*/Tests` が exit 0。`.claude/verify.sh` がこの判定を含む）
- `xcodebuild` ビルド: macOS アプリ（Phlox）・iOS アプリ（PhloxMobile / iPhone 17 Pro シミュレータ）とも BUILD SUCCEEDED
- iOS シミュレータで実画面を目視確認（`-UITesting -UIScreen=sessionDetail`）: ツール実行グループの見出し＝コマンド原文、
  展開でツール名ラベル＋`$ command`＋出力の枠線付きカード、ファイル変更の展開で行番号・追加削除の帯・構文ハイライト・
  フルパス 1 行を確認。スクリーンショットは run 限りの作業物のため残していない。

## 途中で判明したこと（次に効くもの）

- **Swift のテストターゲットは 1 つのビルド単位**なので、未実装 API を参照する受け入れテストを複数タスク分まとめて
  凍結するとパッケージ全体がビルド不能になり、並列タスクの verify が相互にブロックされる。本 run では
  タスクを直列にし、**受け入れテストは各タスクのディスパッチ直前に凍結**する運用にした。
- **受け入れテストのハーネス欠陥は 2 件出た**（SwiftUI の `body` を MainActor 外で評価してクラッシュ／
  「hunk 行は表示しない」と「共有分類と一致」を素朴に比較して矛盾）。いずれも実装者が実装で回避せず報告し、
  PM がハーネスを直した。凍結前の実走ができない（＝実装が無いとコンパイルできない）Swift では、この経路が要る。
- **独立レビューの実測が効いた**: 「長い diff 行に到達できない」「`nonisolated(unsafe)` は不要」「`ChatRowKind` が
  飾りになっている」は、いずれもテストが緑のまま見逃していた欠陥で、レビュアーが実コンパイル・レイアウト実測で検出した。
- 統合検証で**シミュレータの目視でしか分からない不整合**（ツール実行グループの外側にだけ背景が残り、
  ファイル変更カードと見た目が割れていた）を 1 件見つけて直した。テストは器の同一性を型でしか見ていなかった。

## 積み残し（この run では対処しない）

- サブエージェント詳細の diff に描画行数の上限が無い（既定折りたたみが実質の歯止め）。
- ツール実行グループのヘッダ構築が毎描画 O(N)、`SessionDetailCommandCardData.copyText` を毎 init で生成。いずれも未実測。
- markdown 用の Swift トークナイザが `ChatRenderKit` と二重（意図的。→ ADR 0041）。
