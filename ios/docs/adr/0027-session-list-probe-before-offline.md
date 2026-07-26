---
status: accepted
last-verified: 2026-07-26
---

# ADR 0027: セッション一覧のオフライン画面は「実際に到達性の判定が済んで失敗した」ときだけ出す（未判定は接続中表示のまま待つ）

> **このファイルの役割**: 到達性が `.unknown` の間に何を表示するか、いつオフライン画面へ落とすかの決定理由。
> **書かないもの**: QR ペアリング直後のオーバーレイ（→ [ADR 0021](0021-connecting-overlay-gated-on-session-list-load.md)）、到達性の on-demand 再判定そのもの（→ [ADR 0019](0019-reachability-on-demand-refresh.md)）、セッション詳細の初回ロード表示（→ [ADR 0023](0023-ios-initial-load-connecting-indicator.md)）。

## 文脈

`SessionRepository` のポーリングは `reachability.current` が `.online` 以外なら即座に `.offline` を yield していた。`ReachabilityMonitor` の初期値は `.unknown`（まだ一度も判定していない）なので、**アプリを開いた直後、到達性の判定が終わる前に必ずオフライン画面が出る**。実際には繋がる環境でも「接続できません」が一瞬（環境によっては数秒）表示される。

`.loading` 状態の表示も素の `ProgressView()` で、macOS 側や QR ペアリング時の接続中アニメと見た目が揃っていなかった。

加えて `SessionListView` はオフライン画面へ渡す理由を `offlineReachability` で丸めており、`.unknown` も `.unreachableHost` として表示していた。未判定を「ホストに届かなかった」と断定する表示になっていた。

## 決定

1. **`.unknown` を offline として扱わない**。`SessionRepository.emitOnce` は `.unknown` を観測したら `reachability.refresh()` で**能動的に判定を促し**、判定が付いたらその結果で分岐する。
2. **判定が付くまでは何も yield しない**（`.loading` のまま留まる）。ポーリング開始時の `.loading` が接続中アニメを出し続ける。
3. **未判定のまま `defaultUnknownTimeout`（20 秒）を過ぎたらオフラインへ落とす**。ADR 0021 で確定済みの「永久スピナー」アンチパターンを避けるため、脱出条件を必ず持たせる。締切はポーリング開始時に一度だけ引き、`init(unknownTimeout:)` でテストから注入できる。
4. **`.loading` の表示を `DSConnectingIndicator(size: 96)` にする**。QR ペアリング時・セッション詳細初回ロードと同じ部品に揃える。
5. **オフライン画面には実際の `reachability` をそのまま渡す**。`.unknown` を `.unreachableHost` に丸める `offlineReachability` を削除した。決定 1〜3 により、オフライン画面に到達する時点で到達性は判定済みか、20 秒待っても判定できなかったかのどちらかである。

## 棄却案

- **`.unknown` を即 `.offline` にし、判定後に復帰させる**（従来動作）: 「オフライン画面 → 一覧」というちらつきが毎回起きる。ユーザー報告の起点そのもの。
- **締切を設けず判定が付くまで待つ**: 到達性判定が返らない環境で永久に接続中アニメが回る。ADR 0021 で実機確定済みの失敗パターン。
- **締切をポーリングの毎周期で引き直す**: 未判定が続く限り締切が延び続け、実質「締切なし」になる。

## 結果

- `ConnectingStateWhiteboxTests` / `AcceptanceConnectingStateTests` で、未判定中は `.offline` を yield しないこと・`refresh()` が呼ばれること・締切超過で `.offline` へ落ちること・判定が online なら一覧を出すことを検証した。締切はテストから短い値を注入する。
- **実機での見え方（接続中アニメの体感・オフライン画面へ落ちるまでの 20 秒）は自動テストで裏が取れない**。実機確認が要る。
