---
status: accepted
last-verified: 2026-08-01
---

# ADR 0155: `item/tool/requestUserInput` は既存の質問カードで受ける（拒否はターン中断）

> **このファイルの役割**: codex app-server の「モデルからの質問」を、Claude の AskUserQuestion 用に
> 既にある質問カード UI へ合流させた決定と、回答キー・拒否時の挙動の決定。
> **書かないもの**: 未対応 method 一般の扱い（→ [ADR 0154](0154-codex-unsupported-server-request-is-not-an-approval.md)）、
> 伏せ字回答の保存方針（→ [ADR 0157](0157-secret-answers-are-not-persisted.md)）。

## 文脈

ADR 0154 で未対応 method をエラーで返すようにしたが、報告の発端になった
`item/tool/requestUserInput` は「モデルがユーザーに質問している」要求であり、
エラーで返すと**質問に答える手段が無くなる**（ゲート①でユーザーは「質問 UI をきちんと実装する」を選択）。

Phlox には Claude の AskUserQuestion 用の質問カード（`UserQuestionCell`）が既にある。
両者は「ヘッダ・質問文・選択肢・自由入力」という構造がほぼ同じで、UI を二重に持つ理由がない。

## 決定

1. **既存の質問カードへ合流させる。** `ChatApprovalBroker` が承認とは別の
   `userInputRequests` ストリームで `ChatUserInputRequest` を流し、`ChatSessionViewModel` が
   **Claude 経路と同じ `.userQuestionRequested` ハンドラ**へ渡す。カードを作る処理は 1 箇所のまま。
2. **回答キーは `questions[].id`。** codex の応答は
   `{"answers": {"<question id>": {"answers": ["<label>", ...]}}}` の形で、質問文ではなく id で
   引き当てる。`ChatUserQuestion.id`（Optional）を足し、`answerKey = id ?? question` を
   単一の引き当て規則にした。Claude 経路は `id` が nil のままなので挙動不変で、
   同じ文言の質問が複数あっても取り違えない。
3. **拒否はターンを中断する。** カードの dismiss は broker で wire を決着させたうえで
   `client.interrupt()` を呼ぶ（ゲート①の決定 D4。空回答で続行しない）。
4. **決着は入口ごとではなくターンの終わりで塞ぐ。** dismiss だけでなく、思考インジケータの
   中断・エラー経路・`terminate` でも保留中の質問が宙吊りにならないよう、
   `expireAllPendingUserQuestions()` の 1 箇所で broker を決着させる。

## 結果

- codex の質問が画面に出て回答が返るようになり、`Unsupported server request` のバナーは出ない。
- 質問カードの見た目・キーボード操作・フォーカス挙動は Claude 経路と完全に共通のまま増えない。
- 拒否＝中断なので、ユーザーが答えたくない質問でターンが宙吊りにならない。代償として
  「質問だけ飛ばして続行」はできない（codex 側にそのセマンティクスが無いため）。
- `ChatUserQuestion` に Optional の `id` が増えたが、既存の永続データ（このキーが無い JSON）は
  従来どおり読める。
