---
status: active
last-verified: 2026-07-08
---

# ADR 0049: hook POST を token↔session 検証で認証する

> **このファイルの役割**: 2026-07 コードベース監査（CWE-306 相当）への対応として「HookServer の `POST /hook` を無認証から Bearer トークン認証へ変える」と決めた理由・棄却案・帰結。
> **書かないもの**: 実装の逐次経緯（→ `delivery/0026-pm1-backend-audit-remediation-worklog.md`）、CLI 認証の全体像（既存 `ControlServer` の Bearer 認証と同型）。

## 文脈

- `HookServer.handle` は `POST /hook` を**無認証**で受理し、payload の `sessionId`・`kind` をそのまま
  `HookEvent` として配送していた。ローカルの任意プロセスが偽の `stop`/`notification` を任意セッションへ
  注入でき、セッション完了検知やダッシュボード状態を撹乱できた（CWE-306）。
- `PHLOX_TOKEN` は各エージェントセッションの env に既に注入済み（`AgentLaunchPlanner`）で、
  `SessionTokenStore`（AgentDomain）に token↔session が登録される。認証に必要な材料は揃っていた。

## 決定

- `hook-dispatcher.sh` が `Authorization: Bearer $PHLOX_TOKEN` を付与する（トークンは argv=ps 露出を
  避けるため `curl -K -` の stdin config で渡す。CWE-214 も同時回避）。
- `HookServer` は `SessionTokenStore` を注入され、`POST /hook` で次を検証する:
  - トークン無し / 未知トークン → **401**（本文処理に入らない）。
  - トークンが解決する session ≠ payload の `sessionId` → **403**（有効トークンでも他セッションの
    hook を注入できない。CWE-639 相当）。
- 認証は body-size(413) チェックの後・イベント配送の前に置く。
- `CompositionRoot` は `SessionTokenStore` を**単一インスタンス**で生成し、HookServer・ControlServer・
  AppEnvironment（register 先）で共有する（別インスタンスだと HookServer のストアに誰も register せず
  正当 hook が常に 401 で落ちる）。

## 棄却した案

- **HookServer.init で tokenStore を必須化**: 認証に無関係な既存テスト（body-limit・起動）が
  `HookServer()` で構築するため壊れる。→ optional 既定 nil（nil=認証オフ。本番は必ず注入）にした。
- **トークンを `-H "Authorization: ..."` で付与**: argv に載り `ps aux` で他ユーザーに見える（CWE-214）。
  → `-K -`（stdin config）にした。

## 帰結

- 偽 hook 注入が塞がれた。回帰は「未認証/不正/別セッションの POST では hook イベントが配送されない」
  セキュリティ不変条件で固定（`HookAuthRegressionTests`）。マージ前 E2E の hook 駆動ライフサイクルで
  end-to-end に認証配線を確認。
- 早期拒否（token 無し・即 close）は TCP close が client の pending 送信と競合し**環境により**
  connection reset になり得る（`sendAndClose` は graceful cancel=FIN。未読データを持つソケット close の
  POSIX 挙動）。実クライアントの curl は `|| true` で無視するため実害なし。回帰は非配送で検証する。
