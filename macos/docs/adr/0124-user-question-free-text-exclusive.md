---
status: accepted
last-verified: 2026-07-26
---

# ADR 0124: AskUserQuestion の自由入力と選択肢は相互排他にし、自由入力欄は複数行へ折り返す

> **このファイルの役割**: 自由入力欄にフォーカスしたら選択肢を解除する（およびその逆）決定と、自由入力欄を単一行から複数行へ変えた理由。
> **書かないもの**: AskUserQuestion カード全体の構造（→ [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md)）、iOS 側がこれを鏡写しにする方針（→ [iOS ADR 0024](../../../ios/docs/adr/0024-user-question-card-mirror.md)）。

## 文脈

AskUserQuestion カードには「提示された選択肢」と「自由入力」の両方がある。従来は**選択肢を触ったときだけ自由入力をクリア**しており、逆方向（自由入力を触ったときに選択肢を解除する）が無かった。そのため選択肢を選んだあとに自由入力へ書き始めると、画面上は選択肢がハイライトされたまま自由入力にも文字がある状態になる。送信時は自由入力が優先されるので、**ユーザーが見ている選択状態と実際に送られる回答が食い違う**。

自由入力欄は `TextField`（単一行）だったため、右端まで書くと横スクロールし、入力済みの文字列が読めなくなる。

## 決定

1. **自由入力欄にフォーカスが入った時点で、その質問の選択肢をすべて解除する**（`freeTextDidFocus(question:)`）。逆に選択肢を触ったらその質問の自由入力をクリアする（既存動作を維持）。どちらか一方だけが回答になる状態を、画面上でも常に保つ。
2. **フォーカス中の入力変更でも選択肢を解除する**（macOS のみ `freeTextDidChangeWhileFocused`）。macOS の `@FocusState` はプログラム的な代入や再描画でフォーカス通知が前後することがあり、フォーカス通知だけに頼ると解除が漏れる。iOS では `onChange(of: focusedQuestion)` だけで足りることを実測で確認した。
3. **自由入力欄を `axis: .vertical` + `lineLimit(1...4)` にする**。右端で折り返し、最大4行まで伸びる。4行を超える長文はスクロールに任せる（カード自体が transcript 内の1要素であり、無制限に伸ばすと transcript の他の内容が押し出されるため）。
4. **選択・排他ロジックを View から値型のフォームモデルへ切り出す**。macOS は既存 `UserQuestionFormModel`、iOS は新規 `UserQuestionFormState` を使い、View は状態を持たない。排他規則をテストできる場所を1箇所にするため。

## 棄却案

- **選択肢と自由入力の併存を許し、送信時に自由入力を優先する**（従来動作）: 画面表示と送信内容が食い違う。ユーザー報告の起点そのもの。
- **フォーカスではなく「1文字目の入力」で解除する**: 選択肢を選んだあと自由入力欄をタップして何も打たずに戻った場合、選択が残る。フォーカスが入った時点で「自由入力で答える」という意思表示として扱うほうが状態が単純になる。
- **`lineLimit` を付けず無制限に伸ばす**: 長い貼り付けでカードが transcript を占有する。

## 結果

- 排他規則は値型（`UserQuestionFormModel` / `UserQuestionFormState`）の単体テストで凍結した。
- **View 配線はソース assert でも凍結した**。理由: task-5 のレビューで `UserQuestionCell.swift` を修正前へ丸ごと巻き戻しても 387 件のテストが1件も落ちないことが実測された。値型だけをテストすると、ユーザーの症状に直結する View 配線が無防備なまま green になる。受け入れテストが `#filePath` からソースを読み、`@FocusState` / `freeTextDidFocus(` / `axis: .vertical` / フォームモデル型名の存在を検査する（同パッケージの `Wave3SessionDetailChromeWhiteboxTests` に前例のある方式）。
- **実描画の折り返し・タップ時の payload は自動テストで裏が取れない**。実機確認が要る。
