---
status: active
last-verified: 2026-07-08
---

# ADR 0050: Control API の操作認可は「変更系のみ祖先/自己」、read は operator モデル

> **このファイルの役割**: 2026-07 監査（IDOR/CWE-639）への対応として「どの Control 操作に requester↔target
> の認可を課すか」を決めた理由・棄却案・帰結。既存 [ADR 0004](0004-session-kill-authorization-and-guide-delivery.md)
> （kill の所有者認可）の範囲を rename へ拡張する。
> **書かないもの**: 実装経緯（→ `delivery/0026-pm1-backend-audit-remediation-worklog.md`）。

## 文脈

- `ControlActionHandler` は認証（Bearer→SessionID 解決）で得た `requester` を、`kill(remove)` の認可
  （`SpawnPolicy.isAuthorizedToRemove`＝自己/祖先/特権/nil で許可）にのみ使い、**`rename` は「有効
  トークンなら誰でも」**、read 系（output/messages/wait/waitReady/listSessions）も requester 未使用だった。
  無関係なエージェントが任意 SessionID を rename でき、他セッションの出力を read できた（IDOR/CWE-639）。
- 既存 E2E `s4_phloxListSendRead` は「operator セッション（対象の祖先でない独立トークン）が他セッションの
  output を read する」ことを**正常系として固定**している。これは PM→worker の横断参照という
  orchestration の基盤機能である。

## 決定

- **変更系（rename）に `isAuthorizedToRemove(id, requester:)` 認可を追加**する（未認可→403）。remove と
  同じ「自己/祖先/特権/requester=nil は許可、無関係エージェントのみ拒否」の意味論を再利用する
  （protocol 要件は変更せず既存メソッドを流用）。
- **read 系（output/messages/wait/waitReady/listSessions）には認可を課さない**。有効トークンを持つ
  任意セッションが読める「operator モデル」として仕様化する（コード注記）。

## 棄却した案

- **read も含め全操作に祖先/自己認可**（監査の第一提案）: 既存 E2E の operator read モデルを 403 で壊し、
  テストを弱めずに通せない。orchestration の sibling/operator read を封じる副作用も大きい。監査自身が
  代替案「権限モデルを仕様化」を提示しており、それに沿って read を operator モデルと定義した。
- **protocol に一般認可メソッドを追加**: DashboardViewModel（App 層）の適合を変える必要があり、
  所有境界を跨ぐ。→ 既存 `isAuthorizedToRemove` の流用に留めた（メソッド名の用途ずれは受容。
  DashboardViewModel の既存コメントも将来の一般化を予告済み）。

## 帰結

- 任意 rename の IDOR write ベクタが塞がれた。read の operator モデルは維持され E2E を壊さない。
- 回帰は「未認可 requester の rename→403 かつ renameSession 未呼び出し」「未認可でも read 系は従来どおり
  （403 にしない）」を両方向で固定（`AppBootstrap/AuditRegressionTests`）。
- モバイル/ローカル（requester=nil）・モバイルトークン（特権 requester）は従来どおり全操作可能。
