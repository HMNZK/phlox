---
status: active
last-verified: 2026-07-04
---

# ADR 0012: claudeCode の resumeID を claude のネイティブ session id へ on-change 追従

- ステータス: 採用（Accepted, 2026-06-17）
- 作成日: 2026-06-17
- 関連: セッション永続化（`PersistedSessionDescriptor.resumeID` / `SessionPersistenceCoordinator`）。codex の resumeID 捕捉機構（`.codexNativeFromHook` + rollout discovery）と対になる決定。
- コンテキスト: claudeCode セッションは起動時に `claude --session-id <PhloxのSessionID UUID>` で会話IDを固定し、その UUID をそのまま永続 `resumeID` にしていた（`initialResumeIDStrategy: .phloxUUID`）。しかし claude は長時間・大量ターンのセッションで会話IDを別 UUID へ**再採番（ロールオーバー）**することがあり（`~/.claude/projects/<proj>/<id>.jsonl` が新IDになる）、Phlox はこれを追従しなかった。結果、再起動時の `claude --resume <古いID>` が会話を見つけられず `No conversation found with session ID` で error となり、セッションが開けず作業履歴が迷子になった。フック配信は claudeCode でも実 session id を `nativeSessionId` で運んでいた（`hook-dispatcher.sh` が claude のフック入力 `.session_id` を詰める）が、`persistCodexResumeIDIfNeeded` が `.codexNativeFromHook` のときだけ保存し、claudeCode では捨てていた。

## 1. 決定

1. **追従フラグの新設**: `AgentLaunchSpec` に `followsNativeSessionIDFromHook: Bool`（既定 `false`）を追加し、claudeCode descriptor のみ `true` を付与する。claudeCode の `initialResumeIDStrategy` は `.phloxUUID` のまま（初期 resumeID = 起動 UUID を維持し、`--session-id` 固定起動は不変）。`.phloxUUID` を共有する **goose は既定 false で非対象**（goose の名前付きセッションは再採番しないため追従不要）。

2. **on-change 追従経路**: `DashboardViewModel.persistCodexResumeIDIfNeeded` で、フックが運ぶ `nativeSessionId` を受けたとき、codex の once-when-nil 早期 return **より前に** claudeCode 追従を分岐する。`followsNativeSessionIDFromHook == true` のセッションでは、`nativeSessionId` を **UUID として検証し小文字へ正規化**（`normalizedUUIDString`）した上で、現 `resumeID` と**異なる**有効値なら永続 `resumeID` を最新値へ更新する。初回（`nativeSessionId == 起動 UUID == 現 resumeID`）・無効 UUID・大文字小文字差はすべて **no-op**（不要な save を発生させない）。

3. **永続化メソッドの追加**: `SessionPersistenceCoordinator.persistFollowedNativeResumeID(sessionID:nativeSessionId:shouldFollow:)` を `enqueue` 直列化チェーンの中で行う（後勝ち競合を防ぐ）。`shouldFollow(agentRef)` 述語で追従対象を再確認し、`existing.resumeID != nativeSessionId` のときだけ `updating(resumeID:)` する。codex の once-when-nil 用 `persistedCodexNativeResumeIDs`（一度保存ガード）には**触れない**（複数回の追従更新が必要なため別経路）。

## 2. 根拠 / トレードオフ

- **codex との非対称性**: codex は「ネイティブ id を一度捕捉して resumeID にする」（once-when-nil。フック or rollout discovery のフォールバック）で十分だが、claudeCode は会話IDが**途中で変わる**ため「変化したら追従」が要る。両者を同じ経路に統合すると codex を on-change 化して回帰させるため、`followsNativeSessionIDFromHook` フラグで経路を分離した。codex の native id は UUID 形式とは限らないため、UUID 検証＋正規化は **claudeCode 追従経路のみ**に適用し codex 経路の値を壊さない。
- **goose を巻き込まない**: `.phloxUUID` を strategy として共有するが、追従可否は strategy ではなく専用フラグで判定するため goose は非対象のまま（テストで固定）。
- **タイミング**: ロールオーバー直後にフックが来ないと追従は次フックまで遅延するが、ロールオーバーは会話継続中に起きる＝以後フックが来るため、再起動前に resumeID は最新化される。
- **直列化**: 書き込みは `enqueue` のみを通り、空/不正IDは call-site で除外。多重・競合書き込みを避ける。

## 3. スコープ外

- **既存の迷子セッション救済**（古い resumeID を実会話 id へ手動リンク）は本決定の対象外（再発防止のみ）。起動時に `~/.claude/projects` を走査して stale resumeID を自動補正する移行処理は、誤リンクリスクが高く別タスク/任意スコープ。
- 会話ファイルが既に存在しないケースは復元不能。

## 4. 検証

- 単体（`DashboardViewModelTests`）: 追従（複数回 on-change）/ 初回 no-op / 無効値無視 / 大文字小文字 no-op / goose 非追従 / 復元経路で `--resume <最新ID>` 構築、を save 回数検証つきで符号化。`AgentDescriptorTests` でフラグの kind ごとの値を固定。既存 `codexHookNativeSessionId_persistsResumeIDOnce` は無改変。
- 実走（PM）: `swift test` AgentDomain 65 + DashboardFeature 591 + ヘッドレス E2E 16 すべて green。Claude reviewer go（blocker/major 0）。
