---
status: accepted
last-verified: 2026-08-01
---

# ADR 0153: タイル内クリックでの即時選択は「イベントを消費しないローカル監視」で行う

> **このファイルの役割**: タイルの矩形内ならどこをクリックしても即座にそのセッションが選択される
> ようにした決定と、なぜジェスチャ強化ではなく `NSEvent` のローカル監視を選んだか。
> **書かないもの**: 分割ツリーの幾何・描画制約（→ [architecture/session-pane-layout.md](../architecture/session-pane-layout.md)）、
> 要注意（赤枠）の判定（→ `SessionAttentionPolicy`）。

## 文脈

グリッドのタイル選択は 3 経路しかなかった:

1. ヘッダーのゼロ距離 `DragGesture`（mouseDown で即選択）
2. タイル本文の弱い `TapGesture`（`.simultaneousGesture`）
3. appServer タイルの composer の `onFocusGained`（`becomeFirstResponder` の**遷移時のみ**）

2 は AppKit（`TerminalView` / `NSTextView`）がマウスイベントを取るため本文では実際には発火しない。
3 は既に first responder のテキストビューを再クリックしても発火しない。結果、ユーザーから見ると
「タイルの中をクリックしても選択されない（ヘッダーを狙う必要がある）」状態だった。

ジェスチャを強くする方向（本文にもゼロ距離 `DragGesture` を張る）は採れない。`PaneLayoutView` には
「`.draggable` より先にゼロ距離 `DragGesture` を適用するとドラッグセッションが一切開始しない」という
A/B 実測の記録があり（ADR 0136 の受容残余）、同じ理由でターミナル・テキストビューのテキスト選択・
スクロール・キャレット移動を奪う危険が高い。

## 決定

**タイルごとに `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` を張り、イベントを
一切変更せずそのまま返したうえで、座標がそのタイルの矩形内なら選択を発火する。**

- 判定は純粋関数 `PaneTileClickSelectionPolicy.shouldSelect(pointInWindow:tileFrameInWindow:isFocused:)`
  に閉じる。矩形は**半開区間**（右端・下端は隣のタイルのもの）で、既に選択中なら発火しない。
- 発火は `PaneTileClickSelector.handleMouseDown(pointInWindow:)`。矩形・選択状態はクロージャ注入で、
  AppKit のイベントを持ち込まずに単体テストできる。
- モニタの所有は `PaneTileClickObserver`。ウィンドウ一致（`event.window === tileWindow`）を確かめ、
  登録は多重化させず、`onDisappear` で解除する。
- **矩形はクリックのたびに backing view から取り直す（pull）。キャッシュしない。** タイルは
  `.position` で絶対配置されるため、原点だけが変わる移動（`.swap`）では AppKit の `layout()` が
  呼ばれず、push されたキャッシュは陳腐化して**別セッションを誤選択する**（レビュー時に headless
  プローブで実測）。

## 検討した代替案

- **本文にゼロ距離 `DragGesture`**: AppKit のマウストラッキングを奪う。上記の実測から却下。
- **`onFocusGained` を全タイルへ拡張**: `.pty` に相当する仕組みがなく、再クリックで発火しない問題も残る。
- **矩形を push でキャッシュ**: 原点のみの移動で陳腐化する（上記）。

## 結果

- ターミナル・トランスクリプト・入力欄のどこをクリックしても選択される。既存 3 経路は残置（重複して
  `onSelect` が走っても、ポリシーが「選択済みなら発火しない」ので実害はない）。
- **左マウスダウンを消費しない**ことが不変条件。壊すとアプリ全体のクリックが飲まれるため、
  `AcceptancePaneTileClickPassthroughTests` がモニタのハンドラを直接捕まえて `handler(event) === event`
  を凍結している。
- 選択しても、承認待ち・質問待ちの赤枠（`SessionAttentionPolicy`）は仕様どおり残る。赤枠は「非選択」
  ではなく「ユーザーの対応待ち」の印であり、この決定では変更しない。
- 受け入れテスト: `AcceptancePaneTileClickSelectionTests` / `AcceptancePaneTileClickPassthroughTests`（SessionFeature）。
