---
status: active
last-verified: 2026-07-15
---

# ADR 0012: チャット入力欄の branch 表示は「表示のみ」とし、機能化しない

> **このファイルの役割**: wave-5（task-1）で入力欄カードに追加した branch 風表示を、Session モデル/API を変えない制約下で「表示のみ」（実データはプロジェクト名で代替）とした決定を記録する。
> **書かないもの**: 入力欄カードの chrome・ドラッグ閉じ・音声入力の実装詳細（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

wave-5 task-1 はチャット入力欄をカード型デザイン（Image #2）へ刷新するタスクで、カード内に branch 情報の表示が求められた。一方 `Session` ドメインモデルに branch フィールドは無く、macOS 側 API にも branch 選択エンドポイントは無い。ゲート①でユーザーが「branch は表示のみ（Session モデル/API は不変）」と明示決定した（decision-log wave-5 フェーズ0/1）。

## 決定

- `DSInputBar` に `contextLabel: String?` を追加し、`selectorRow` 内で `Label(contextLabel, systemImage: "arrow.triangle.branch")`（branch アイコン＋テキスト、`DSColor.textTertiary`）として表示する。
- `SessionDetailViewModel.inputContextDisplayName`（`session.projectName ?? draftProject`）を `contextLabel` に渡す。branch の実データが存在しないため、**取得可能なプロジェクト名で代替**する。
- task-1 stage-1 レビューで「branch チップが実際にはブランチアイコンでプロジェクト名を表示している」旨の MEDIUM 指摘が出たが、PM 裁定で受理した（decision-log wave-5「task-2/5 マージ・task-1 レビュー」）。branch 選択機能そのものの実装（Session モデル拡張・API 追加）は本 wave のスコープ外。

## 結果

- 入力欄カードに branch 風の視覚要素（アイコン＋プロジェクト名）が表示されるが、実際の git ブランチ名や選択機能は無い。
- 将来 branch を機能化する場合、`inputContextDisplayName` の実装（および表示アイコン・ラベル）を実データに差し替える必要がある。

## 却下した代替案

- **branch 欄を表示しない**: Image #2 のデザイン意図（カード内に branch 情報を見せる）を満たさないため却下。
- **`Session` モデルへ branch フィールドを追加し API から取得する**: ユーザー決定でモデル/API 不変が明示されており、本 wave のスコープ外。
