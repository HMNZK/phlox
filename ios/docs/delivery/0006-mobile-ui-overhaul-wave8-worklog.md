---
status: completed
last-verified: 2026-07-16
---

# 0006: モバイル UI 刷新 wave-8（QR接続直後オフラインバグ・チャット画像添付表示）作業ログ

> **このファイルの役割**: この run（base = `task/mobile-chat-live`＝wave-5〜7 統合ブランチ・未マージ、in-place 作業）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（wave-8・実機検証由来）

1. **バグ**: QR ペアリング直後に「オフライン / Mac に到達できません / ping … → timeout」になり、「再接続を試す」でも即繋がらず、少し経つと勝手に接続される。
2. **機能**: 画像を添付して送信したメッセージに添付があったことが分からない。デスクトップ（macOS）同様に分かるようにする。

task-1（到達性=Codex/deep）+ task-2（添付バッジ=Cursor/standard）に分解。file-disjoint だが共有ワーキングツリーのため逐次実行。

## 何をしたか（task-1・task-2）

- **task-1**（`ReachabilityMonitor.swift`／`ReachabilityMonitoring.swift`／`Stubs.swift`／`AppRoot.swift`・実装＝Codex ヘッドレス）: 到達性のオンデマンド再判定 `refresh()` を追加。`ReachabilityMonitor._current` は `NWPathMonitor` 経路変化でしか更新されないキャッシュで、QRペアリング完了も手動リトライも更新しなかったのが根本原因。`refresh()` が現在のネット状態（監視中は live `currentPath`、未起動時はキャッシュ）で healthCheck を即実行し `_current` を `update(to:)` 経由で更新（stream yield）。`AppRoot` の QRペアリング完了 `qrScanOnApplied` と手動 `refreshReachability` の両方から呼ぶ配線に変更（→ [ADR 0019](../adr/0019-reachability-on-demand-refresh.md)）。
- **task-2**（`SessionAttachmentReconciler.swift`(新規)／`SessionDetailViewModel.swift`／`SessionDetailView.swift`／`DSChatBubble.swift`・実装＝Cursor ヘッドレス）: 送信済みユーザーメッセージに画像添付バッジを表示。サーバ/ワイヤ/`ChatMessage`/凍結 API 契約は不変（`send` は ID を返さないためクライアント完結）。送信テキストで送信後スナップショットに突き合わせ（`SessionAttachmentReconciler`）、message.id 起点 side-map（`attachmentCountsByMessageID`）に保持して `refresh()` 全置換に耐える。`DSChatBubble` に画像アイコン＋枚数バッジ（→ [ADR 0020](../adr/0020-chat-attachment-badge-client-side.md)）。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0019-reachability-on-demand-refresh.md](../adr/0019-reachability-on-demand-refresh.md)
- [ios/docs/adr/0020-chat-attachment-badge-client-side.md](../adr/0020-chat-attachment-badge-client-side.md)
- [ios/docs/architecture/overview.md](../architecture/overview.md)（到達性 refresh・添付バッジ/side-map を反映）
- [ios/docs/adr/README.md](../adr/README.md)・[ios/docs/delivery/README.md](README.md)（索引追記）

## 検証結果（run 内で実施）

- 両凍結受け入れテストを先出し（`ReachabilityRefreshAcceptanceTests`・`SessionAttachmentReconcilerAcceptanceTests`）。red-for-the-right-reason（未実装シンボルのみ）を確認して凍結。片方のみ実装時は full swift test が相手の未実装で red のため、task-1 は相手退避での isolation、task-2 は両実装後の full で検証。
- task-1: 独立 isolation で 361 tests green（reachability 受け入れ2件含む）。task-2: 権威ゲート `agentic-loop-verify-task.sh task-2` = pass（full swift test green）。
- レビュー: stage-1 persona-reviewer（wave-8 全体）= pass。stage-2 reviewer(sonnet, task-1) = needs_changes（MEDIUM: `refresh()` がキャッシュ satisfied を鵜呑みで offlineNetwork/unreachableHost 誤分類）。PM が live `currentPath` 優先へ修正＋凍結テストに offlineNetwork ケース追加（再著）、stage-2 再確認で pass。
- 独立性: 実装＝Codex/Cursor × レビュー＝Claude のクロスツール。
- **統合検証 = pass**: `.claude/verify.sh` 実走 `verify: OK`（PhloxKit ユニット〔XCTest 408・swift-testing 368、0 failures〕・macOS 134・iOS シミュレータビルド）。`Wave5RegressionUITests` を iOS シミュレータで 4/4 pass（DSChatBubble/SessionDetail 変更の回帰なし）。
- task-1・task-2 を `done` に確定。

## 積み残し・後続確認事項

- **`refresh()` のライブ `currentPath` 分岐はユニット未検証**（`NWPathMonitor` を注入できず。`NWPathMonitor.currentPath` は `start()` 直後・初回評価前に未確定を返しうる）。実機での「ペアリング直後に即オンライン化」「圏外時に offlineNetwork 表示」を次回実機検証で裏取り。
- 添付バッジの実機体感（送信→バッジ表示のタイミング、同一テキスト連投時の割当）は次回実機検証で確認。
- wave-5〜7 の積み残し（音声サブシステム孤児化の撤去要否、ライブアクティビティ実配信等）は本 run スコープ外で継続。dev への統合マージは未実施（ユーザー明示承認待ち。wave-5〜8 すべて `task/mobile-chat-live` 上）。
