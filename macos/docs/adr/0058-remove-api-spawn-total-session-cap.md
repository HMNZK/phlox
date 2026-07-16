---
status: active
last-verified: 2026-07-09
---

# ADR 0058: API 経由 spawn の総セッション数上限（16）を撤廃する

> **このファイルの役割**: `SpawnPolicy.maxAPISpawnSessionCount = 16`（総数上限）を撤廃した判断と根拠を記録する。
> **書かないもの**: 実装差分・作業ログ（→ `delivery/0031`）。現行の spawn 制限の事実一覧（→ `architecture/` および `SpawnPolicy.swift`）。
> **入力となった依頼書**: `docs/delivery/0031-remove-api-spawn-session-cap-request.md`（撤廃に至る経緯・実測データの一次資料）。

## 文脈

- API 経由 spawn（`$PHLOX_CLI spawn` = `POST /sessions`）には初出コミット `971d7b1` 以来、暴走防止として3つの上限が課されていた: 総数16・深さ3・レート5回/秒。
- このうち**総数16**は次の性質を持つと確定した（依頼書 §8-9・付録の実測）:
  - 判定は `sessionCount >= 16` の**ハードコード定数比較**で、空きメモリ・fd・CPU 等の**実リソースを一切測っていない**。
  - **GUI（人間）経路（`from == nil`）はこの上限を素通り**する。技術的天井なら GUI も縛るはずで、無ガードなのは 16 を技術限界と見なしていない証左。
  - 16/3/5 は 1 コミットでセット導入され、以後**一度も調整されず、正当化する ADR も CPU/メモリ由来のコメントも無い**。
  - 実測上の真の壁は **RAM**（24GB 機で claudeCode 同時 ~25〜40 本でスワップ開始のソフトな劣化）。固定値でアプリが「容量」を表現するのは役割違い。
- 発端は課金ガード `guard_billing_spawn.sh` の失敗（`.pty` spawn で ask を提示できず自動 deny ループ）。第三者レビューの結論は「対話的 per-spawn 承認は機構と設置点が誤り。判断ミス対策は行動規範、暴走対策は非対話の自動キャップ」。判断ミス（無償のローカル再現で足りるのに課金 spawn する）は spawn 時点で機械判定不能で、総数キャップでは捕捉できない。

## 決定

- **総数固定上限16（`SpawnPolicy.maxAPISpawnSessionCount` と `AgentSpawnError.tooManySessions`）を撤廃する。**
- **深さ上限3（`depthLimitExceeded`／HTTP 403）・レート上限5回/秒（`spawnRateLimited`／HTTP 429）は残置する。** 深い連鎖・短時間バーストは「総数」とは別の暴走側面であり、レート上限は急激な暴走への安価な非対話の歯止めとして価値があるため（依頼書 §4）。
- 判断ミスへの一次対策は `~/.claude/rules/escalation.md` に強化済みの**行動規範**（課金 spawn 前に無償のローカル再現で代替できないか必ず自問する）が担う。総数の自然な壁は RAM のソフト壁に委ねる。
- マシン依存の動的容量ガード（空きメモリ連動の spawn 拒否）は**追加しない**（現規模では不要。将来 spawn 単価・並列規模が上がった時に別途検討）。

## 検討した代替案

- **16 を別の固定値へ調整**: 中途半端さ（実リソース非依存・GUI 素通り）は値を変えても解消しない。却下。
- **総数の動的メモリ連動ガードへ置換**: 現規模では過剰。macOS がメモリ圧で自然に劣化を吸収する。将来課題として保留。
- **総数上限 E2E を「16超でも成功」へ反転**: 撤廃した機能の不在を重い E2E（多数 spawn）で証明し続けるのはコスト過多で、テスト方針（確信とコストの比較）に反する。総数上限テストはユニット・E2E とも削除した。

## 結果・影響

- API 経路の「数の壁」が消え、UX 上は **GUI と同じ（総数無制限）**に揃う。深さ(403)・レート(429 "spawn rate limited")の歯止めは従来どおり効く。
- `validateAPISpawn(sessionCount:newDepth:)` は `sessionCount` 引数が不要化し **`validateAPISpawn(newDepth:)`** へ整理。
- 検証はゼロ課金（spawn/list はサーバ側で確定）。ユニット（DashboardFeature・AppBootstrap）と E2E が green。
- 運用ドキュメント（`guides/orchestration-verification.md` の HEAVY-2 等・`specs/e2e-test-design.md` S5）から総数上限の記述を撤廃反映済み。
