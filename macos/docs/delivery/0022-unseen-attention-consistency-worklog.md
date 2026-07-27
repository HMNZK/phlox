---
status: completed
last-verified: 2026-07-27
---

# 0022: 消えないバッジと到達できないセッションの修正 作業ログ

> **このファイルの役割**: `feature/unseen-attention-consistency` で何をしたか、どこまで検証したか、何が未検証かの記録。
> **書かないもの**: 各決定の理由（→ [ADR 0126](../adr/0126-session-store-unknown-value-tolerance.md) / [0127](../adr/0127-control-api-requester-parent-separation.md) / [0128](../adr/0128-notification-reachability-per-client.md) / [0129](../adr/0129-orphaned-remote-session-rescue.md)）。

## 背景

ユーザー報告: 「Dock に4の通知マークが出ているが、アプリのどこに向けて通知が溜まっているのか分からない」。

調査の結果、iPhone アプリから作られたセッションが**生成された瞬間に UI から到達不能になり、通知だけを出し続けていた**ことが判った。既読化は macOS の「選択中セッション」でしか発火しないため、ユーザーには解消手段が無かった。

依頼は「局所最適な修正ではなく、恒久的な全体最適の視点で根本から直す」。

## やったこと（4タスク）

| # | 内容 | 決定 |
|---|---|---|
| 1 | セッション保存を未知の列挙値に強くする（1件の未知値で全滅していた） | [ADR 0126](../adr/0126-session-store-unknown-value-tolerance.md) |
| 2 | Control API の「要求元」と「ツリーの親」を分離し `.remoteUser` を導入（**真因**） | [ADR 0127](../adr/0127-control-api-requester-parent-separation.md) |
| 3 | 通知の4出口を、届け先ごとの到達可能性で判定する | [ADR 0128](../adr/0128-notification-reachability-per-client.md) |
| 4 | すでに取り残されている孤児を起動時に救済する | [ADR 0129](../adr/0129-orphaned-remote-session-rescue.md) |

順序には依存関係がある。1は2の前提条件（区分を足す前に前方互換が要る）。3は2の後（`.remoteUser` が可視である前提）。4は3の後。

## 途中で方針を変えた点

**task-3 は一度差し戻した。実装ではなく契約（PM が書いた仕様）が間違っていた。**

当初は「通知の4出口すべてを同一の判定で塞ぐ」としていた。独立レビューで「APNs の受け手は iPhone なのに macOS の画面基準で塞いでいる」と指摘され、検算した結果その通りだった。iPhone のセッション一覧は絞り込みをしていないため、**iPhone からは開けるセッションの通知が消える**状態になっていた。凍結済みの受け入れテストが誤った契約を固定していたので、**PM がテストを書き換えて再凍結**し、実装を差し戻した（実装役がテストを緩めたのではない）。

## 検証

**実走したもの**（すべて `swift test` を1つずつ順に実行）:

| パッケージ | 結果 |
|---|---|
| DashboardFeature | 1487 pass |
| SessionFeature | 407 pass |
| AgentDomain | 234 pass |
| MessageStore | 40 pass |
| AppBootstrap | 148 pass |
| ClaudeAgentKit / CodexAppServerKit / CursorAgentKit | 132 / 41 / 31 pass |
| APNsClient / AgentConfigKit / DesignSystem / HookServer | 9 / 79 / 76 / 21 pass |
| LocalHTTPServer / MobileProxy / PTYKit / StructuredChatKit / TerminalUI | 28 / 68 / 31 / 26 / 50 pass |

App ターゲット（`xcodebuild -scheme Phlox -configuration Debug`）: **BUILD SUCCEEDED**。

独立レビュー（persona-reviewer、実装役の Codex とは別モデル）を全タスクに実施。task-2 は差し戻し1回（幽霊セッションを作り得る競合）、task-3 は差し戻し1回（上記の契約誤り）を経て pass。

**既存の失敗（この run とは無関係）**: `ControlServer` の3件が失敗する。基準コミット `793bf08` でも同一の3件が同一メッセージで失敗することを一時 worktree で確認済み。モデル ID の受け渡しに関するもので、本 run は `ControlServer` を1行も変更していない。

**未検証**:

- 実機での動作（Dock バッジが実際に減ること、救済された4件が一覧に現れること）。コード・テスト層までの確認にとどまる。
- 通知バナーと完了音の実発火。テストバンドルからは観測できない（→ ADR 0128 の「検証範囲の限界」）。
- iOS 側のビルド・テスト。

## 残した課題

- `sessions.json` の前方互換は `launchContext` の未知値までで、`backend` / `kind` の未知値は依然としてその1件が落ちる（→ ADR 0126）。
- `.corrupt-<epoch>` という名前が「隔離」と「復旧用バックアップ」の二義になっている（→ ADR 0126）。
- 救済結果の保存だけが永続化の直列チェーンを迂回している（理論上の窓。再現シナリオは構成できなかった）。
- `DashboardViewModel.hasUnseenCompletion(in:)` は本番未使用のまま残している。サイドバー森走査の共通ヘルパーを直接検証する唯一のテスト継ぎ目であり、消すと生きた経路の検証を巻き添えにするため（判断の詳細は run の decision-log に記録）。
