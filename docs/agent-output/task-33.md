---
task: task-33
status: completed
---

## 詰まった / 完了できなかった点
- なし（機械完了条件は通過）。契約成功基準 3 の PM 目視ゲート（隔離 Debug・AX `enabled == false`・A 選択中に B 行＋から custom を B へ作成）は実装役の allowed_paths 外かつ課金経路を踏まない条件付き確認なので、本タスクでは未実施。

## できた風だが実は未完（最重要）
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:694` — 作成先行は契約どおり素の `Text(model.destinationText)`。配線検査は Button label に入っていないことだけを見る。Menu 内 Text が実機 AX で `enabled == false` になるかは未確認（SwiftUI Menu の非活性行慣例に依存）。
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:697-709` — `createSession` は async のため、契約疑似コードの `Button { createSession(...) }` にはできず、既存実装と同じ `Task { await createSession(...) }` で包んだ。配線検査は引数の空白除去後文字列だけを見るので、Task 包みの有無は検査対象外。
- primary と組込チャット／ターミナル経路の実起動は、契約どおり課金セッションになるため未実行。ref/backend 対応は凍結テストと配線検査のみ。

## 置いた前提・仮定
- チャット／ターミナル判定は `AgentStartCardsModel.modes(for:)` の戻り値に委ね、`supportsStructuredChat` をモデル側で再判定しない。custom も `kind` を触らず `ref` と `modes(for:)` だけ使う。
- backend は `mode.backend`（primary は先頭チャット Item の backend）のみ。`.appServer` / `.pty` リテラルは書かない。
- destination の trim は `.whitespacesAndNewlines`（`GridScopeSummary` / task-31 と同じ）。空・nil・空白のみは「名称未設定のプロジェクト」。
- 節タイトルは定数で一意なので `ForEach(model.sections, id: \.title)` で足りる。
- `NewSessionMenuModel.swift` は SwiftUI を import しない。`AgentStartCardsModel` は同モジュールの値型 API として再利用する（定義ファイルが SwiftUI を import していても、本モデルは View を持たない）。

## 契約からの逸脱
- 契約の配線疑似コードは `Button { createSession(ref:primary.ref, projectID:projectID, backend:primary.backend) }`（await なし）。`createSession` のシグネチャを変えない不変条件のため、既存どおり `Task { await ... }` にした。引数名・順序・`projectID` をそのまま渡す点は契約どおり。

## レビュー重点（PM 用）
- 旧 6 経路（組込 3 エージェント × チャット／ターミナル）がチャット節・ターミナル節に残っているか。Cursor がチャット非対応のときチャット節から落ち、ターミナル節には残るか。
- 「新しいチャット（\(displayName)）」でエージェントが項目名だけで分かるか。descriptors 順の primary（Codex 先頭なら Codex）か。
- 作成先語彙が UX-04/UI-08 の「名称未設定のプロジェクト」と一致しているか。
- 作成先行が Button になっていないか。A 選択中に B 行の＋から custom（ui01-probe / `.pty`）を作ると B に入るか（`projectID` を引数のまま `createSession` へ渡していることの実機確認）。
- `AgentStartCards.swift` / `TeamTimelineView.swift` を触っていないこと、`modes(for:)` の単一規則がメニュー側で再実装されていないこと。

## 2026-09-12 再開注記（PM=Claude 記載）
- resume の理由は開示レポートの書式（frontmatter 前の前置き段落）であり、製品コード・テストは実装役の完了時点から変更していない。再実装は行っていない。

=== REPORT COMPLETE ===
