# ADR 0001: AgentDomain を sibling Phlox と共有する（A1 の更新）

- **ステータス**: 承認済み（ゲート② / PM 承認）
- **日付**: 2026-06-19
- **決定者**: PM オーケストレーター（ユーザー承認済み）
- **関連**: 問題定義 仮定 A1 / A2、`doc/architecture.md` §3・§14（A3）、`doc/design-system.md` §0・§2

---

## コンテキスト

問題定義（ゲート①）では以下の 2 仮定を承認した。

- **A1**: `AgentDomain`（`SessionStatus` / `AgentKind` 等）を **Phlox-mobile 内に独立定義（コピー追従）**する。
- **A2**: `DesignSystem` は **sibling `../Phlox/Packages/DesignSystem` を path 依存**で参照し iOS 多プラットフォーム化する。

E1-1 着手時、この 2 仮定が **SwiftPM のパッケージグラフ上で両立しない**ことが判明した。

```
PhloxKit
 ├─ .package(path: ../Phlox/Packages/DesignSystem)
 │     └─ .package(path: ../AgentDomain)  → product "AgentDomain"（Phlox）
 └─ target: AgentDomain（A1 のコピー）   → product "AgentDomain"（mobile）  ← 衝突
```

実際に `swift test` は次のエラーで停止した。

```
error: multiple packages ('agentdomain' (.../Phlox/Packages/AgentDomain),
'phloxkit' (.../Phlox-mobile/Packages/PhloxKit)) declare products with a
conflicting name: 'AgentDomain'; product names need to be unique across the package graph
```

`DesignSystem` は `StatusBadge` / `StatusDot` / `AgentKindBadge` / `Tokens.agentColor(for:)` 等で
Phlox の `AgentDomain`（`SessionStatus`・`AgentKind`）に深く依存しており、A2 を採る限り Phlox の
`AgentDomain` は必ずグラフへ取り込まれる。

## 決定

**A1 を更新し、`AgentDomain` を sibling `../Phlox/Packages/AgentDomain` から共有する（Architecture Y）。**

- PhloxKit は `AgentDomain` ターゲットを**持たない**。`.package(path:)` で Phlox の `AgentDomain` を参照し、`PhloxCore` が再エクスポート（`@_exported import AgentDomain`）する。
- Phlox の `AgentDomain` は Foundation のみに依存するため、`Package.swift` の `platforms` に `.iOS(.v17)` を追加するだけで iOS 対応できる（本 ADR と同時に実施）。
- `DesignSystem` の iOS 化（`.iOS(.v17)` 追加 + `#if os(macOS)` 隔離）は引き続き E2-1 で行う。

## 根拠

1. **両立不能の解消**: product 名衝突は同名ターゲットの存在が原因。コピーを廃し共有すれば衝突が消える。
2. **SSOT 原則**: `design-system.md` §0 は「状態語彙を 2 箇所で定義すると必ずズレる（デザインシステム最大の失敗モード）」と明記。共有は本原則に直接合致する。
3. **データ表現力**: Phlox の `SessionStatus` は `awaitingApproval(prompt:)` / `completed(exitCode:)` / `error(message:)` と associated value を持ち、承認・詳細・エラー画面が必要とする情報をそのまま運べる。コピー版の単純 enum より UI 要件への適合度が高い。
4. **低リスク**: `AgentDomain` は Foundation 依存のみ。iOS 追加で macOS 既存ビルドは壊れない（プラットフォーム追加は退行を生まない）。

## トレードオフ / 影響

- **+** 型ドリフトが原理的に発生しない（単一定義）。`DesignSystem` の状態系コンポーネントを iOS でそのまま再利用できる。
- **−** Phlox-mobile が sibling Phlox リポジトリに**ビルド時依存**する（path 依存）。両リポジトリの同時チェックアウトが前提（既に A2 で同条件）。
- **−** sibling リポジトリ（`../Phlox`、ブランチ `dev`）の `AgentDomain/Package.swift` を変更する（`platforms` に iOS 追加）。Mac 側リポジトリへのコミットが必要。
- **E1-3 の意味変化**: 「`AgentDomain` を新規定義」→「共有 `AgentDomain` が Mac wire format と一致することを検証し、iOS 集約モデルとの変換を `PhloxCore` 側に用意」へ読み替える（board の決定ログに記録）。

## 実施内容（E1-1 時点）

- `../Phlox/Packages/AgentDomain/Package.swift`: `platforms: [.macOS(.v14), .iOS(.v17)]`
- `Packages/PhloxKit/Package.swift`: `AgentDomain` ローカルターゲットを廃止し、`.package(path:)` 2 件（AgentDomain / DesignSystem）を宣言。`PhloxCore` が `AgentDomain` product に依存・再エクスポート。
- `problem-definition.md` の A1 注記を本 ADR 参照に更新。
