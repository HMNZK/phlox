---
status: active
last-verified: 2026-07-18
---

# ADR 0023: iOS セッション初回ロード中の接続ローディング表示（DSConnectingIndicator 配線・実データ到達で閉じる）

> **このファイルの役割**: セッションを開いた直後の初回ロード中（メッセージ履歴/出力の取得中）に既存 `DSConnectingIndicator` を中央表示し、「描画のため待っている」ことをユーザーへ示す決定と、その表示ゲート（何をもって表示し・何をもって閉じるか）の設計理由を記録する。
> **書かないもの**: 履歴の折りたたみ（→ ADR 0022）。現行の実装仕様（→ `Features/SessionDetail/SessionDetailView.swift`・`SessionDetailViewModel.swift`）。

## 文脈

セッションを開くと、メッセージ履歴/出力を取得している初回ロードの間、`transcriptSection`（`loadError`→バナー / `showsChat`→チャット / それ以外→ターミナル出力 の三分岐）では `chatMessages` 空かつ `outputText` 空となり **素の空白**が表示されていた。ユーザー報告のUX不具合「セッションを開く→しばらく空白→一気に描画」の空白区間で、描画中であることが伝わらない。macOS 側の接続中アニメと同種のフィードバックが iOS には無かった。

## 決定

1. **初回ロード状態を ViewModel に持つ**。`SessionDetailViewModel` に `public private(set) var isInitialLoading: Bool` を追加。生成時 `true`、**初回 `load()` が解決した時点で `false`**（成功／メッセージ空フォールバック／失敗いずれでも）。終了保証は `load()` 先頭の `defer { isInitialLoading = false }` に置き、全 return 経路（早期 return・内部 catch）で必ず false 化する。ポーリングの `refresh()` では触らない（復帰時に表示を消さない既存方針と整合・フリッカー防止）。
2. **表示ゲートを純粋な計算プロパティに集約**。`showsInitialLoadingIndicator = isInitialLoading && !isAwaitingInitialSpawn && chatMessages.isEmpty && outputText.isEmpty`。`transcriptSection` は `loadError`・`showsChat` の後にこのプロパティで分岐し、既存 `DSConnectingIndicator(size: 96)` を画面中央に表示する。データ到達（chat/output 非空）またはエラーで通常分岐へ抜ける。
3. **閉じ判定は「到達性」でなく「実データのロード完了」に紐付ける**（iOS ADR 0021 の教訓）。表示は初回 `load()` の解決で閉じ、空データで永久スピナー・早すぎる消滅にしない。
4. **ドラフト作成画面（未 spawn）を除外する**。新規セッション作成（compose draft）経路は `startPolling(composeDraft:)` が `prepareDraft(...)` を実行して `load()` を呼ばない設計のため、`isInitialLoading` の初期 `true` が false 化されない。ゲートに `!isAwaitingInitialSpawn` を含めることで、入力バーと同時に大きなスピナーが永続表示される回帰（ADR 0021 の「永久スピナー」アンチパターン）を防ぐ。
5. **既存 `DSConnectingIndicator` を再利用**（新規部品を作らない）。QR 画面で使用中のレーダー風アニメ・Reduce Motion 対応部品をそのまま配線する。

## 棄却案

- **到達性（reachability）で開閉する**: 空データで永久スピナー・早すぎる消滅を生む（ADR 0021 で iOS 実機確定済みの失敗パターン）。採らない。
- **表示判定を View 内のインライン条件に留める**: 初回レビューで `isInitialLoading` の初期 true だけに反応してドラフト画面で永久表示する回帰が出た。計算プロパティへ集約し ViewModel 白箱で検証可能にした。
- **新規ローディング部品の作成**: 既存 `DSConnectingIndicator` で足り、重複を避ける。

## 結果

- 白箱 `SessionDetailLoadingWhiteboxTests`（6件）: 生成直後 true／messages 成功→false+showsChat／空 messages+output フォールバック→false／両失敗→false+`loadError`／refresh で再点灯しない／**ドラフト作成画面ではゲートが成立しない**。`swift test --package-path ios/Packages/PhloxKit --no-parallel` 全数 green（388・XCTest 別途）。
- 初回ロード区間の空白がインジケータ表示に置き換わり、描画待ちが可視化される。
- **未検証（フェーズ4/実機）**: 実機/シミュレータでの初回オープン体感は次段で確認する。
