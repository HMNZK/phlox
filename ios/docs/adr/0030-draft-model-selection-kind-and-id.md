---
status: accepted
last-verified: 2026-07-26
---

# ADR 0030: ドラフトのモデル選択は表示用 ID 文字列ではなく `(kind, modelID?)` で保持する

> **このファイルの役割**: カタログが一時的に欠けたときにエージェント種別が無言ですり替わる事故を、選択の保持形式で防いだ決定。
> **書かないもの**: モデル一覧の取得側（→ [macOS architecture/agent-model-catalog.md](../../../macos/docs/architecture/agent-model-catalog.md)）、既定モデル規則（→ [macOS ADR 0123](../../../macos/docs/adr/0123-agent-default-model-single-source.md)）。

## 文脈

未 spawn のドラフト画面では `prepareDraft(_:)` が 3 エージェント分のカタログを取得してモデルピッカーの行を作る。選択は `selectedModelPickerEntryID`（`kind` と `modelID` を結合した**表示用の ID 文字列**）だけで保持していた。

`prepareDraft` は再入する（画面復帰・再取得）。再入時にカタログ取得が一時的に失敗すると、ユーザーが選んだ行が一覧から消える。従来の実装は「選択中の ID が一覧に無ければ**一覧全体の既定へフォールバック**」していたため、

- Cursor を選んでいたのに Cursor のカタログだけ落ちる → **Claude で spawn される**
- Claude を選んでいたのに Claude のカタログだけ落ちる → **Codex で spawn される**

といったすり替わりが、警告も表示もなく起きる。ユーザーは自分が選んだエージェントで動いていると思ったまま別のエージェントに課金・実行される。

Codex の行は「空カタログでも agent-only 行を必ず持つ」という既存契約があったため一覧の末尾に常在し、フォールバック先になりやすかった。

## 決定

1. **選択を `DraftModelSelection { kind: AgentKind, modelID: String? }` で保持する**。表示用 ID 文字列（`selectedModelPickerEntryID`）はピッカーのハイライト専用に降格する。
2. **再取得時の解決順を「kind を必ず守る」形で固定する**:
   1. 同一 `(kind, modelID)` の行があればそれ
   2. 無ければ**同じ kind の既定モデル**の行
   3. 無ければ**同じ kind の任意の行**
   4. 同じ kind の行が1つも無ければ、`(kind, modelID: nil)` を保持し**ピッカーは未選択表示**にする
3. **spawn は保持済みの `DraftModelSelection` を使う**。ピッカーが未選択に見えていても、`kind` は必ずユーザーが選んだものになる。
4. **Codex の agent-only 行は、Codex のカタログが空のときだけ出す**。live カタログが取れているなら通常のモデル行が並ぶ（→ [macOS ADR 0122](../../../macos/docs/adr/0122-live-agent-model-catalog.md) で Codex のモデル選択が解禁されたため）。

## 棄却案

- **ID 文字列のまま、フォールバック先を「同じ kind の先頭」にする**: ID 文字列から kind を復元するパースが必要になり、ID の書式変更で静かに壊れる。
- **行が消えたら選択をクリアして spawn をブロックする**: カタログの一時的な失敗でユーザーの操作が止まる。kind は分かっているので `model: nil` で spawn すればサーバ側の既定が使える。
- **すり替わり時に警告を出す**: 警告を出す前に、そもそもすり替わらせない。

## 結果

- `DraftSelectionStabilityWhiteboxTests` / `AcceptanceDraftSelectionStabilityTests` で、Cursor→Codex / Claude→Codex / Claude→Cursor / Cursor→Claude の 4 パターンのすり替わりが起きないことを検証した。修正前はこの 4 件が赤になる（PM が修正前ツリーで確認済み）。
- **受け入れテストのハーネス自体に欠陥があった**（PM の誤り）。`sendMessage()` を引数なしで呼ぶと 2 回目の `prepareDraft` が走らず、バグを再現できていなかった。`sendMessage(composeDraft:)` へ修理して初めて 4 件が赤になった。実装役はハーネスを書き換えず、再現しない事実をそのまま報告して正しかった。
