---
status: completed
last-verified: 2026-07-20
---

# 0011: 新規セッション下書きの送信ボタン誤表示バグ修正 worklog

agentic-loop（backend=external, multi N=1）による run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、PM（Claude）が診断・契約凍結・レビュー・統合・蒸留を担当。実機で発見されたバグの修正。

## バグ

プロジェクト一覧「+ セッションを追加」→ 下書き画面（`DraftSessionComposeDestination` が placeholder session を `status: .running` で作る）で、まだ spawn していない（`isAwaitingInitialSpawn == true`）のに入力バーが送信でなく**停止ボタン（赤■）**を出し、最初の1通を送れず操作不能になっていた。

## 根本原因

[ADR 0008](../adr/0008-spawn-screen-to-draft-compose.md) §32 は「未 spawn ドラフトでは `stopButton` 非表示などの分岐を `SessionDetailViewModel.isAwaitingInitialSpawn` でガードする必要がある」と明記していたが、`SessionDetailView` の入力バーの停止ボタン表示条件が `currentStatus == .running && canInterrupt` のままで **`isAwaitingInitialSpawn` を除外していなかった**。placeholder の `.running` と既定 `canInterrupt=true` が両立し、`DSInputBar.actionState`（`if isRunning { return .stop }`）が送信ボタンを停止ボタンに置き換えていた。＝ ADR 0008 の設計に対する入力バー側の実装漏れ。

## 修正

`SessionDetailViewModel` に公開計算プロパティを追加し、`SessionDetailView` の入力バー `isRunning:` をそれへ差し替え（最小差分・2ソース）:

```swift
public var showsStopButton: Bool {
    !isAwaitingInitialSpawn && currentStatus == .running && canInterrupt
}
```

これで下書き未 spawn 中は送信ボタンが出て最初のメッセージで正常に spawn でき、実 running セッションでは従来どおり停止ボタンが出る。ADR 0008 §32 の設計へ復帰。

## 検証

- verify-task（権威ゲート）: allowed_paths 逸脱なし・verify.sh 再実走 green・開示レポート completed。
- persona-reviewer: 独立実走で iOS PhloxKit 全 428 tests・94 suites green（0 failures）、凍結受け入れ4件 pass、回帰スイート（Wave4ModelSelectorAndDraft・SessionControl）14 pass・skip なし、MUST/HIGH/MEDIUM/LOW 0。
- 凍結受け入れテスト `DraftComposeSendButtonAcceptanceTests`（PM 著・4ケース: 下書き未spawn→送信 / 実running→停止 / idle→送信 / 409後canInterrupt=false→送信）を追加。
- 未検証: 実機での再操作確認（インストール後の目視）は未実施。振る舞いは受け入れテストで担保。
