---
status: accepted
last-verified: 2026-07-28
---

# ADR 0135: 巻き戻しで復元した本文は ViewModel が `draft` へ直接書く（View 側で遅れを吸収しない）

> **このファイルの役割**: esc 巻き戻し後にキャレットを復元本文の末尾へ置くために、復元本文の配送経路を変えた決定と、View 側の保留機構を採らなかった理由。
> **書かないもの**: この機能の要件・受け入れ基準（→ [specs/esc-revert-composer-focus.md](../specs/esc-revert-composer-focus.md)）、run の作業経緯（→ [delivery/0023](../delivery/0023-esc-restore-composer-focus-worklog.md)）。

## 文脈

esc を 2 連打すると履歴巻き戻しピッカーが開く。過去のユーザーメッセージを選ぶと会話がその直前まで巻き戻り、選んだ本文が入力欄（composer）へ復元される。このとき満たすべきことが 2 つある。

1. キーボードフォーカスが composer へ戻る（クリックせずに続きを打てる）
2. キャレットが復元本文の**末尾**にある（先頭のままだと打った文字が復元本文の前に入る）

フォーカス復帰は `ChatSessionViewModel.composerFocusRequest`（狭義単調増加の token ＋ `movesCaretToEnd`）を `IMESafeTextView` が見て `window.makeFirstResponder` する形で解決できる。問題は 2 の方だった。

復元本文はもともと次の経路で View へ届いていた。

```
confirmRevert → draftRestoration → ChatEscapeHandling の onChange → viewModel.draft → text binding
```

`composerFocusRequest` は `confirmRevert` の中で同期的に立つのに、本文は `onChange` を挟むぶん**1 更新パス遅れて**届く。つまり「末尾へ動かせ」という要求が来た時点で、入力欄にはまだ**復元前の下書き**が入っている。`syncStringFromBinding` は変更前の選択位置をクランプして保持するので、遅れて本文が届いてもキャレットは途中に取り残される。

## 決定

**`ChatSessionViewModel.confirmRevert` が `draft` を直接書く。** 復元本文とフォーカス要求を同じ代入＝**同じ更新パス**で View へ届かせ、遅れそのものを無くす。

```swift
let restored = await revert(toUserMessageID: id)
if let restored { draft = restored }
draftRestoration = restored
isHistoryPickerPresented = false
lastEscapeAt = nil
requestComposerFocus(movesCaretToEnd: restored != nil)
```

これにより `IMESafeTextView.updateNSView` は、本文同期（`syncStringFromBinding`）を済ませた**直後**に同じパスでフォーカス要求を処理する。末尾化は要求ごとにその場で完結し、View 側に状態を持つ必要が無い。

`draftRestoration` は公開 API かつ受け入れテストが表明しているため引き続きセットし、View は 1 ショット通知として消費する（`consumeDraftRestoration`）だけにした。値としては誰も読まない。

## 棄却案

### View 側で末尾化要求を保留し、本文が届いてから適用する

最初に採ったのはこちらで、`IMESafeTextView.Coordinator` に `pendingCaretToEnd: Bool` を置き、本文が同期された時点・IME 変換が終わった時点で再適用していた。**独立レビュー 4 巡すべてで HIGH / MEDIUM を受けて棄却した。**

棄却の決め手は、指摘が**逆方向に振れた**ことである。

- 3 巡目「非空の旧下書きがあると、旧本文に対して末尾化を消費してしまい、遅れて届く復元本文に適用されない」＝ 保留が**早く消えすぎる**
- 4 巡目「復元本文が旧本文と同一だと同期ブロックが走らず保留が残り続け、後続の無関係な binding 同期でキャレットが飛ぶ」＝ 保留が**残りすぎる**

同じ 1 個の Bool に対して両方向の欠陥が出るのは、閾値や消費点の置き方が悪いのではなく**状態モデルが誤っている**サインである。保留は「どの本文に対する要求か」「どの状態遷移に属するか」「どの token の要求か」のいずれにも結び付いておらず、局所修正を重ねても閉じない。

作り直しの結果、View 側から次がすべて消えた（実装 -146 / +55 行）。

- `pendingCaretToEnd` / `isComposingNow`
- `handleComposingChanged` / `applyPendingCaretToEndIfNeeded`
- 同期ブロックと `textDidChange` での保留解除

### `moveCaretToEnd` を IME 変換中も実行する（あるいは保留して変換終了後に再適用する）

5 巡目レビューは「フォーカス要求が届いた瞬間に IME 変換中だと末尾化が一度で消える」と指摘した。これは**実装ではなくテストで決着させた**。

末尾化つきの要求を出すのは `confirmRevert` だけで、それは必ず履歴ピッカーを開いた後に起きる。よって指摘が実害になるのは、**変換状態がピッカー表示をまたいで生き残る**場合に限られる。実物の overlay（`.chatEscapeHandling`）を通して測ったところ、ピッカーがフォーカスを奪った時点で変換は終了していた（`compositionDoesNotSurviveThePicker`）。旧実装の IME 保留機構は、到達しない経路のために状態を増やしていたことになる。

`moveCaretToEnd` の `hasMarkedText()` ガードだけは残した。変換途中の確定位置を壊さない防御であり、1 行で済む。

## 結果

- キャレット位置の欠陥が、View 側の状態を 0 個にしたまま解消した。レビュー 4 巡ぶんの指摘が構造的に消えた。
- 復元経路の正本が「ViewModel が `draft` を持つ」1 箇所になった。`draftRestoration` は互換のための通知に降格した。
- この前提（＝復元本文が必ず同じ更新パスで届く）が崩れると、キャレット以前に**復元本文の同期自体が止まる**（`updateNSView` の同期ブロックが `hasMarkedText()` で素通しになる）。崩れたときに見直すべきは保留機構ではなく同期の設計であり、その前提を `compositionDoesNotSurviveThePicker` がテストとして固定している。
- 副産物として、overlay 検証ハーネスの text binding が本番と食い違っていたのを修正した。ローカルの `@State` に束ねていたため復元本文が composer へ届かず、既存の overlay テストは「フォーカスが戻るか」しか測れていなかった。

## 関連

- [ADR 0010](0010-loopflow-kanban-hang-observable-mutation-during-render.md) — `updateNSView` は描画パスであり副作用を同期実行しない。フォーカス移動を `Task { @MainActor }` へ回しているのはこの決定に従っている（加えて、ピッカー overlay が responder chain から抜けるのを待つ必要がある）。
