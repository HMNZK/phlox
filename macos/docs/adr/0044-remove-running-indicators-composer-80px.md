---
status: active (入力欄80px の決定は ADR 0046 が supersede)
last-verified: 2026-07-07
---

# ADR 0044: 実行中インジケータを全撤去し、入力欄のデフォルト高を80pxに統一する

> **注記（2026-07-07）**: 本 ADR のうち「入力欄デフォルト高80px（エディタ min=80）」の決定は、実機検証でパネル全体約140pxのデグレと判定され **ADR 0046 が supersede** した（「80px はパネル全体の見た目高さ」と解釈確定）。実行中インジケータ撤去の決定は不変。
> **このファイルの役割**: なぜ running スピナー／"N running" バッジを全廃したか、なぜ入力欄デフォルト高を single/grid とも80pxにしたかの決定・文脈・結果。ADR 0042 point5・ADR 0036 の関連サブ決定を部分的に撤回する。
> **書かないもの**: コンポーネント構造・トークン値（→ `architecture/design-system.md` / `chat-mode-ux-components.md`）。

## 文脈

- ADR 0042 point5 は `AgentSessionIcon` に「running のみ控えめインジケータ」を残し、プロジェクト行に `RunningCountBadge`（"N running"）を出していた。実運用では **スピナーがアイコンに重なって見苦しく**（サイドバー行・ウィンドウ上部タイトル・シングルヘッダの3箇所で顕著）、ユーザーは実行中の視覚表示そのものの廃止を要望した。
- 加えて `AgentSessionIcon` の `RunningSpinner`（Core Animation）と、サイドバー各行での非キャッシュな `runningBreakdown`（毎行 `SessionTree.buildForest` 再構築）が、サイドバー開閉アニメ時のカクつきに寄与していた。
- 入力欄の安静時高さは ADR 0036 で grid=40／single=44 と定めていたが、ユーザーは「入力欄全体の縦幅をデフォルト80px」に要望を更新した。

## 決定

1. **実行中インジケータを全撤去**する（ユーザー決定＝実行中/待機の視覚区別が UI から消えることを許容）。`AgentSessionIcon` の `RunningSpinner` overlay をコンポーネント階層で除去し、全呼び出し箇所のスピナーを一括で消す。`RunningCountBadge`（"N running"）の本番描画を撤去する。→ **ADR 0042 point5 の running サブ決定を撤回**。
2. **サイドバー開閉の再レイアウトを局所化**する。開閉アニメを対象 `Group`（サイドバー／インスペクター）にスコープし、`detailContent` へのアニメ波及を抑える。プロジェクト行の毎回 `runningBreakdown` 呼び出し（バッジ撤去に伴い不要）を除去する。
3. **入力欄デフォルト高を single/grid とも80pxに統一**する（`ComposerHeightBounds` を 80〜160）。auto-grow（伸縮）は維持。→ **ADR 0036 の安静時高さ（grid=40/single=44）を80へ更新**（autogrow 再有効化という 0036 の核は維持）。

## 棄却案

- **スピナーを最小ドットに置換**: 重なりは解消するが実行中表示は残す案。ユーザーは完全撤去を選択。
- **runningBreakdown のキャッシュ化**: 実装当初はキャッシュを足したが、バッジ撤去で本番の呼び出し元が消え死重になったため撤去し、呼び出し元除去（＝根本除去）に寄せた。

## 結果

- UI から実行中スピナー・running 文字が消え、アイコンの重なりが解消。サイドバー開閉のホットパス（毎行ツリー再構築）が除去された。
- **残る確認事項**: カクつき解消の実効と、`detailContent` の `.transaction{animation=nil}` がグリッドの drop-highlight を過剰抑制していないかは実機 runtime で要確認。
