---
status: completed
last-verified: 2026-07-16
---

# 0007: モバイル UI 刷新 wave-9（接続中オーバーレイ・添付バッジ分離）作業ログ

> **このファイルの役割**: この run（base = `task/mobile-chat-live`・in-place 作業）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（wave-9・実機検証由来の追依頼）

1. **添付バッジ分離**: 画像添付バッジがチャットバブルの中に入っているので、macOS デスクトップ同様にバブルの外へ分けて表示する。
2. **接続中ローディング**: QR ペアリング直後、接続されるまで中央に大きな「接続中…」ローディングを出す。
3. **接続中が即消えるバグ**: 上記を入れたが「接続中」が即座に閉じてエラー画面が出て、少し待つと接続される。原因調査と修正（→ `/agentic-loop backend=external` で正式化）。

## 何をしたか

- **添付バッジ分離**（直接実装・コミット `970aaba`）: `DSChatBubble` でバッジを `userMessageContent`（バブル背景内）から出し、バブルの下・右寄せの**カプセル型チップ**として描画。テキスト空で画像のみのときは空バブルを出さずバッジのみ表示。凍結の reconciler 受け入れテストは不変（配置変更のみ）。
- **接続中オーバーレイ**（直接実装・コミット `1e62165`。閉じ判定は後述 task-1 で修正）: `AppModel.isConnecting` フラグ＋`AppRoot.ConnectingOverlayView`（中央大スピナー＋「接続中…」）を追加し、`AppRoot` の QR ペアリング完了 `qrScanOnApplied` から立てる。
- **task-1（agentic-loop single / external=Cursor）— 接続中即消えバグの修正**: 根本原因は、オフライン画面が到達性（`AppModel.reachability`）ではなく **`SessionListViewModel.state`（`SessionsState`・リポジトリの定期ポーリング）** で駆動されるのに、`connectAfterPairing()` が到達性 `refresh()==.online` で接続中を閉じていたこと（healthCheck が一覧取得より速く通り、一覧未ロードのまま閉じてオフライン画面が一瞬出る）。閉じ判定をテスト可能な純関数 `PairingConnectGate.shouldContinueConnecting(listState:elapsed:timeout:)` に切り出し、`AppRoot.connectAfterPairing()` が **一覧の取得成功（`.loaded`/`.empty`）またはタイムアウト（約20秒）** まで接続中を保つよう配線変更（→ [ADR 0021](../adr/0021-connecting-overlay-gated-on-session-list-load.md)）。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0021-connecting-overlay-gated-on-session-list-load.md](../adr/0021-connecting-overlay-gated-on-session-list-load.md)
- [ios/docs/architecture/overview.md](../architecture/overview.md)（接続中オーバーレイ／添付バッジ分離を反映）
- [ios/docs/adr/README.md](../adr/README.md)・[ios/docs/delivery/README.md](README.md)（索引追記）

## 検証結果（run 内で実施）

- 凍結受け入れ `PairingConnectGateAcceptanceTests`（5ケース）を先出し。red-for-the-right-reason（未実装 `PairingConnectGate` symbol のみ）を確認して凍結（コミット `4c6361d`）。
- task-1 実装＝Cursor（ヘッドレス）。権威ゲート `agentic-loop-verify-task.sh task-1` = pass（スコープ違反なし・テスト pass・レポート present/completed）。
- レビュー: stage-1 persona-reviewer = **pass**（FeaturesTests 176 全 pass、受け入れ 5/5・白箱 3/3、根本原因到達、凍結テスト未改変、誠実性問題なし）。single モードのため stage-2 なし。MEDIUM（統合パスは View のため自動テスト外）・LOW（ループ内 `listVM?.refresh()` が state を駆動しない冗長呼び出し）は非ブロッカーとして受容。
- 独立性: 実装＝Cursor × レビュー＝Claude のクロスツール。
- **統合検証 = pass**: `.claude/verify.sh` 実走 `verify: OK`（PhloxKit ユニット・macOS・iOS シミュレータビルド）。実機（stultus / iPhone 14 Plus）へクリーン再インストール＋起動成功。

## 積み残し・後続確認事項

- **接続中の閉じ判定の実地正当性はユニット未検証**（`AppRoot.connectAfterPairing` は View で、`SessionListViewModel.observe()` のポーリングが state を駆動することに暗黙依存）。実機で「QR ペアリング直後に接続中…が一覧が読めるまで出続け、オフライン画面が挟まらない」ことを次回実機検証で裏取り。
- LOW（ループ内 `listVM?.refresh()` の冗長性）は受容。state 更新は背景の `observe()` ポーリングが担うため correctness には影響しないが、必要なら後続で除去。
- **スコープ**: 修正の主経路は初回セットアップ完了（`qrScanOnApplied` が `setupRequired` のみフック）。設定タブからの QR 再ペアリングは対象外（同症状があれば別タスク）。
- dev への統合マージは未実施（ユーザー明示承認待ち。wave-5〜9 すべて `task/mobile-chat-live` 上）。
