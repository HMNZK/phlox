---
status: active
last-verified: 2026-07-28
---

# esc 巻き戻し後の composer フォーカス復帰 — 要件と受け入れ基準

> **このファイルの役割**: 「esc 2 連打 → 履歴巻き戻し → そのまま入力再開」が満たすべき条件と、その検証点。
> **書かないもの**: なぜこの実装方式を選んだか（→ [ADR 0135](../adr/0135-restored-draft-is-written-by-the-view-model.md)）、run の作業経緯（→ [delivery/0023](../delivery/0023-esc-restore-composer-focus-worklog.md)）。

## 対象

macOS のチャット画面のみ。iOS（`ios/Packages/PhloxKit`）に esc / double-esc / revert の実装は存在しない。

## 用語

| 語 | 意味 |
|---|---|
| composer | チャットの入力欄。実体は `IMESafeTextView`（`NSViewRepresentable`）→ `SubmitAwareTextView`（`NSTextView`） |
| 履歴ピッカー | esc 2 連打で開く「会話を巻き戻す」overlay（`ChatHistoryRevertPicker`） |
| 復元本文 | ピッカーで選んだ過去のユーザーメッセージの本文。composer へ戻される |
| フォーカス要求 | `ChatSessionViewModel.composerFocusRequest`。狭義単調増加の `token` と `movesCaretToEnd` を持つ値型 |

## 機能要件

| # | 要件 |
|---|---|
| FR1 | ピッカーで過去メッセージを選んで確定すると、キーボードフォーカスが composer へ戻る（クリック不要で入力を再開できる） |
| FR2 | そのときキャレットは**復元本文の末尾**にある（先頭のままだと打った文字が復元本文の前に入る） |
| FR3 | ピッカーを**キャンセル**した場合（esc / 閉じるボタン / 背景タップ）もフォーカスは composer へ戻る。ただしキャレットは動かさない |
| FR4 | 単発 esc（interrupt 経路）と、ピッカーを開く操作そのものでは、フォーカス要求を発火しない |
| FR5 | 単一表示（`ChatSessionView`）とグリッド表示（`GridChatColumn`）の両方に配線する |

## 非機能要件・不変条件

| # | 要件 |
|---|---|
| NFR1 | 初回描画でフォーカスを奪わない。以後も**同じ要求（同一 token）での再描画**ではフォーカスを奪い返さない（ユーザーが他所を操作中に取り返さないため） |
| NFR2 | IME 変換中にキャレットを動かさない（変換途中の確定位置を壊さない） |
| NFR3 | 復元以外の binding 同期（外部からの `draft` 書き換え全般）でキャレットが末尾へ飛ぶ副作用を出さない |
| NFR4 | `updateNSView`（描画パス）で副作用を同期実行しない（[ADR 0010](../adr/0010-loopflow-kanban-hang-observable-mutation-during-render.md)）。フォーカス移動は `Task { @MainActor }` で次の runloop へ回す |
| NFR5 | `IMESafeTextView` は `SubAgentDrawerView` からも使われるため、フォーカス要求パラメータは既定値付きで追加し既存呼び出しを壊さない |

## 受け入れ基準（検証点）

機械判定するもの:

1. フォーカス要求を渡すと、`NSWindow` 上でホストされた `NSTextView` が `window.firstResponder` になる
2. `confirmRevert(toUserMessageID:)` 完了後、`composerFocusRequest` の token がちょうど 1 進み、`movesCaretToEnd == true`
3. ピッカーをキャンセルした経路でも token がちょうど 1 進み、`movesCaretToEnd == false`
4. 復元後の `NSTextView.selectedRange().location` が復元本文の UTF-16 長と一致する
5. `GridChatColumn` が同じフォーカス要求を `IMESafeTextView` へ渡している（ソース走査アサーション）
6. 実物の `ChatHistoryRevertPicker` overlay を載せた状態でピッカーを閉じると、退場アニメーション（0.15 秒）完了後も composer が first responder を保つ。**配線を外した負の対照が赤になること**を同時に確認する
7. `.claude/verify.sh` が exit 0（SessionFeature / DashboardFeature の全テストと AppBootstrap ビルド）

機械判定しないもの（本リポジトリに GUI E2E ターゲットが無いため手動）:

8. Debug ビルドを（稼働中のリリース版を終了させずに）併存起動し、esc 2 連打 → 履歴選択 → **クリックせずに**入力を開始できることを目視確認する。手順は [guides/running-release-and-debug-together.md](../guides/running-release-and-debug-together.md)

## スコープ外

- iOS 側（該当機能が存在しない）
- 履歴ピッカーの UI 改善（並び順・検索・件数上限）
- `revert` / 文脈リプレイのロジックそのもの
- `SubAgentDrawerView` の入力欄のフォーカス挙動
- esc 単発（interrupt）の挙動変更
- ターミナル側のフォーカス制御（`TerminalHostingView`）
