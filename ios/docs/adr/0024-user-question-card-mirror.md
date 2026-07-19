---
status: accepted
last-verified: 2026-07-19
---

# ADR 0024: iOS 質問カードミラー（前方互換デコード・成功後楽観更新・確定ボタン式 UI）

> **このファイルの役割**: macOS の質問カード（[macos ADR 0102](../../../macos/docs/adr/0102-ask-user-question-control-protocol.md) / [0103](../../../macos/docs/adr/0103-user-question-wire-mirror.md)）を iOS（PhloxMobile）へミラーする際の3つの設計判断（デコード方針・回答の楽観更新順序・カード UI の操作様式）を記録する。
> **書かないもの**: wire キー・DTO 形状そのもの（→ macos ADR 0103）、control protocol（→ macos ADR 0102）。

## 文脈

macOS 側で `AskUserQuestion` 対応（質問カード表示・回答返送）が実装され、wire 契約（`PhloxQuestionWireContract`、macOS 側 `ControlQuestionWireContract` と値を一字一句一致させた二重管理）が凍結された。iOS（PhloxMobile）はこの wire をミラーする側であり、独自の輸送プロトコル判断は不要だが、**デコードの安全性**・**回答送信の失敗時挙動**・**カード操作の UX**の3点は iOS 側固有の設計判断として必要だった。`PhloxQuestionWireContract.implemented` は本 run 完了まで `false` に固定されており、実装完了と同時に `true` へ反転した（1行のみの変更で、他の wire 定数は無改変）。

## 決定

### 1. デコードは前方互換（必須欠落・未知 state は nil で除外）

`ChatMessageDTO.toDomain()` に `case PhloxQuestionWireContract.messageType`（`"userQuestion"`）を追加し、`decodeUserQuestion()` へ委譲する。`requestId` / `state` / `questions` のいずれかが欠落、または `state` が `UserQuestionState(rawValue:)` で解決できない未知文字列の場合は **nil を返しメッセージ自体を除外する**（既存7ケースの switch は文言・戻り値とも不変）。旧アプリが新しい `state` 値（将来の拡張）を受け取っても、クラッシュせず該当メッセージが静かに消える方針とし、既存の Codable 前方互換ポリシー（未知ケースの安全な無視）を踏襲する。

### 2. 回答は API 成功後にのみローカル反映（ロールバック不要な順序）

`SessionDetailViewModel.answerQuestion` は、`visibleMessages` で当該 `requestId` が **pending 状態で存在すること**を確認してから `chatMessages` 内の pending index を取得し、`respondToQuestion(...)` の**成功を待った後にのみ** `chatMessages[index]` を answered（answers 反映）へ置換する。API 呼び出しが throw する、または pending が既に無い場合は置換せず `false` を返す。

先に楽観的にローカルを answered にしてから API 失敗時にロールバックする設計は採らなかった。**成功後にのみ更新する順序であれば、失敗時のロールバック処理が構造的に不要**になり、pending 状態のまま UI に留まる（再送可能）という一貫した失敗時挙動が得られる。

### 3. UI は single/multi とも確定ボタン方式、自由入力が選択肢より優先

`UserQuestionCard` は single-select・multi-select のいずれも「選択（または自由入力）→確定ボタンで送信」の操作様式を採る（single のタップ即送信はしない。macOS 側 `UserQuestionCell` の「single は各タップで draft 更新→揃い次第送信」とは異なる UI 判断だが、回答の wire 表現・VM の受理条件には影響しない）。自由入力フィールドが非空の場合は、その質問の選択肢よりも自由入力の値を優先して送信する。multiSelect の answers 配列は選択順ではなく label のソート順で組み立てる。

## 棄却案

- **未知 state を既定値（例: pending）にフォールバックしてメッセージを残す**: 意味不明な状態のカードを操作可能に見せてしまうリスクがあり、既存の「デコード不能は nil で除外」方針との一貫性を優先し不採用。
- **先に楽観更新してから API 失敗時にロールバック**: ロールバックのための追加状態管理が必要になり、成功後更新のみで同等以上の一貫性が得られるため不採用。

## 結果

- `swift test --package-path ios/Packages/PhloxKit --no-parallel` で凍結受け入れ2スイート（`UserQuestionDecodingAcceptanceTests` 4件 / `UserQuestionAnswerAcceptanceTests` 5件）を含む396テストが green（stage1 レビュー実走確認）。
- incremental delta（append-only）経路では既存メッセージ id の state 変化（pending→answered/expired）が取り込まれない既知の制約が残る（task-4 導入ではなく全メッセージ種に共通の既存挙動。全量フェッチ/snapshot 経路では収束する）。統合検証で incremental delta 下の state 収束が要件になった場合は別途確認する。
- macOS 側の作業ログは [macos/docs/delivery/0008](../../../macos/docs/delivery/0008-ask-user-question-worklog.md)、iOS 側は [ios/docs/delivery/0010](../delivery/0010-ask-user-question-worklog.md) 参照。
