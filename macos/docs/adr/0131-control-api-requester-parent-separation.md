---
status: accepted
last-verified: 2026-07-27
---

# ADR 0131: Control API の「要求元」と「セッションツリーの親」を分離し、`.remoteUser` を導入する

> **このファイルの役割**: iPhone から作ったセッションが画面のどこにも出なくなっていた**真因**と、それを「偽の親リンクを書くのをやめる」ことで断った決定。
> **書かないもの**: 通知をどこまで出すかの判断（→ [ADR 0132](0132-notification-reachability-per-client.md)）、既に取り残されたデータの救済（→ [ADR 0133](0133-orphaned-remote-session-rescue.md)）、サーフェス別の可視性ルールそのもの（→ [ADR 0027](0027-grid-workspace-filter-includes-subsessions.md)）。

## 文脈

Dock アイコンに赤いバッジが出続けるのに、アプリのどこを探しても対応すべきセッションが見つからない、という報告があった。

調査で判った経路:

1. iPhone アプリからのセッション作成は Control API `POST /sessions` を通る。
2. その実装（`macos/App/ControlActionDashboard+DashboardViewModel.swift`）は、
   - `launchContext` を **`.orchestration` 固定**で渡し、
   - モバイルトークンに紐づく**要求元 ID をそのまま `from:`（＝親セッション）として渡していた**。
3. この要求元 ID は認可のための**合成 ID であって、実在するセッションではない**。したがって生成された瞬間に「実在しない親を持つセッション」＝孤児になる。
4. 孤児は `resolveProjectID` が nil を返すためワークスペースにも属さない。`.orchestration` はトップレベルグリッドとサイドバーから除外される（ADR 0027）。結果、**どのサーフェスにも現れない**。

ユーザーの実機データでこれを確認した（Keychain のモバイル requester ID と、UI から消えていた4件の `parentSessionID` が一致）。

根の問題は `SessionLaunchContext` が**3つの意味を兼ねていた**ことにある: ①どこから起動されたか ②ユーザーに見せるか ③CLI の承認・サンドボックス方針。「モバイルから来た」を表現する区分が無いので `.orchestration` を流用し、その副作用で②③まで巻き込んでいた。

## 決定

1. **偽の親リンクを書くのをやめる**。要求元（レート制限のキー）と、セッションツリーの親（実在するセッションへの参照）を分離する。**親リンクは実在するセッションにしか張らない**。
2. **`SessionLaunchContext` に `.remoteUser` を足し、起動経路の1意味へ戻す**。iPhone 等の遠隔クライアントからユーザー本人が起動したセッションはこれになる。
3. 表示（②）と承認・サンドボックス（③）は、区分から**明示的に導出**する。`.remoteUser` は「ユーザー本人の起動」なので `.interactive` と同じ扱い（画面に出る／承認は on-request／サンドボックスは workspace-write）。CLI 内部サブセッション向けの緩い方針（承認しない・フルアクセス）を継承させない。
4. 親を張らなくなっても、**要求元ごとの spawn レート制限は従来どおり効かせる**（素朴に親を nil にすると上限検査ごと消える）。

## 棄却案

- **`.orchestration` のまま、表示側のフィルタを緩める**: 症状（見えない）は消えるが、`launchContext` が3つの意味を兼ねる構造は残る。CLI 内部サブセッションまで一覧に出てしまい ADR 0027 の決定を壊す。
- **モバイル発セッションに専用の projectID を割り当てる**: 見えるようにはなるが、存在しないワークスペースを合成することになり、ワークスペースの意味が壊れる。
- **要求元 ID を実在セッションとして登録する**: 認可用の合成 ID をセッション実体に昇格させることになり、認可とセッション管理が癒着する。

## 結果

- Control API 由来の spawn は、要求元が実在すれば従来どおり `.orchestration` の子セッション、実在しなければ `.remoteUser` のルートセッションとして着地する。
- 受け入れテスト `AcceptanceSessionOriginTests`（9件）で、分類・可視性・承認/サンドボックス方針・永続化往復・レート制限の非退行を凍結。
- 実装中に判明した副次的な競合も塞いだ: 起動処理の最後の待機中にセッションが連鎖削除されると、`sessions.json` にだけ残る「幽霊セッション」ができ得た。待機完了後に存在を再確認してから永続化する（両バックエンド共通の1点）。
- 前提条件として [ADR 0130](0130-session-store-unknown-value-tolerance.md) の前方互換を先に入れている（区分を足すと旧版で全滅するため）。

作業経緯は [delivery/0022-unseen-attention-consistency-worklog.md](../delivery/0022-unseen-attention-consistency-worklog.md) を参照。
