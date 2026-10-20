---
status: active
last-verified: 2026-08-01
---

# codex app-server の server request 処理（現状仕様）

> **このファイルの役割**: codex app-server が client（Phlox）へ送る server request を、
> Phlox が「今どう捌いているか」——承認・質問・未対応の 3 経路と、フルアクセス設定の適用先。
> **書かないもの**: なぜこの設計か（→ ADR [0154](../adr/0154-codex-unsupported-server-request-is-not-an-approval.md)
> / [0155](../adr/0155-codex-request-user-input-as-question-card.md)
> / [0156](../adr/0156-full-access-setting-applies-to-app-server.md)
> / [0157](../adr/0157-secret-answers-are-not-persisted.md)）、
> Claude チャットのプロセスライフサイクル（→ claude-chat-session-lifecycle.md）。

## 1. 3 つの経路

`JSONRPCClient` は受信した server request を `ServerRequest` へデコードし、
`ChatApprovalBroker.serverRequestHandler` へ渡す。分岐は次の 3 つだけ。

| 種別 | method | 捌き方 |
|---|---|---|
| 承認 | コマンド実行承認 / パッチ適用承認 | 承認バナーを出し、ユーザーの決定を wire へ返す |
| 質問 | `item/tool/requestUserInput` | 質問カードを出し、回答を wire へ返す |
| 未対応 | 上記以外（ログイン系を除く） | `unsupportedServerRequest` を throw → `-32601 Method not found` |

未対応を承認へ写像しない。画面には何も出さない。

## 2. 質問（`item/tool/requestUserInput`）の流れ

```
codex app-server
  └─ item/tool/requestUserInput { threadId, turnId, itemId, questions[], autoResolutionMs? }
       └─ ChatApprovalBroker
            ├─ userInputRequests: AsyncStream<ChatUserInputRequest>  ← VM が購読
            └─ 継続を保留（回答 or 拒否 or cancelAll で必ず 1 回だけ resume）
                 └─ ChatSessionViewModel
                      └─ 既存の .userQuestionRequested ハンドラ（Claude 経路と共通）
                           └─ transcript に .userQuestion / status = awaitingUserQuestion
```

- **回答**: `respondToUserQuestion(requestId:answers:)` は requestId が codex 質問なら
  `broker.answerUserInput` へ回す（Claude 質問は従来どおり `client.respondToUserQuestion`）。
- **回答キー**: `ChatUserQuestion.answerKey`（`id ?? question`）。codex は `questions[].id`、
  Claude は質問文。カード・フォーム・エクスポータはすべてこの 1 つの規則で引き当てる。
- **wire の応答形**: `{"answers": {"<question id>": {"answers": ["<label>", ...]}}}`（入れ子）。
- **拒否**: `declineUserQuestion(requestId:)` が broker を決着させてから `client.interrupt()`。
- **失効**: ターンが終わるどの経路（中断ボタン・`.error`・`terminate`・`cancelAll`）でも
  `expireAllPendingUserQuestions()` が保留中の質問を決着させ、カードを `expired` にする。

### 伏せ字（`isSecret`）

`questions[].isSecret` が true のとき、自由入力欄は `SecureField` になり、回答済み表示も
マスクされる。さらに **wire へ送った直後に平文を捨て**、転写には固定長のマスクだけが積まれる
（`ChatUserQuestion.persistedAnswers` が唯一の正本）。永続化 JSON にも Markdown エクスポートにも
平文は現れない。

### 実行を止めない質問の通知（Codex 0.163.0）

`request_user_input_async` は server request ではなく、`item/completed` の
`agentMessage`（`delivery: "async"`、`questions: [{title, options?}]`）で届く。
スキーマと Transcale の `thread/read` 応答で、この形式を確認した（2026-10-20）。

- ライブターンの質問到着ごとに Mac とモバイルへ質問通知を送る。実行状態は変更しない。
- 質問の単位は thread / turn / item ID。同じ項目の再送では重複させない。
- 履歴の読み込み、別 thread、終了済み turn のイベントでは通知しない。
- 通常の質問も要求 ID ごとに通知する。同じ入力待ち状態のまま次の質問が来ても通知する。
- 質問通知は会話を表示中でも出す。OS の許可、音・バナー設定、クライアントからの到達性は尊重する。
- 非同期質問は実行中なので、停止状態の解消に連動して通知を消さない。通知はユーザーが閉じるまで残す。
- 非同期質問の回答は通常のメッセージ入力を使う。回答待ちの質問カードや自動回答は作らない。
- 普通の文章の疑問符から質問を推測する処理は入れない。構造化された質問の通知が対象。
  引用・独り言まで通知する誤検知を避けるため、文章だけの質問の全数検知は保証しない。
- 通知送信の失敗は、本文を含めず診断ログへ記録する。

## 3. フルアクセス設定の適用

`BypassSettings`（キー `phlox.bypass.codex`、未設定時 ON）を
`SessionSpawnService.appServerApprovalPolicy(for:defaults:)` /
`appServerSandboxPolicy(for:defaults:)` が読み、スレッド開始時の初期値を決める。

| フルアクセス | approvalPolicy | sandboxPolicy |
|---|---|---|
| ON（既定） | `never` | `danger-full-access` |
| OFF | `on-request` | `workspace-write` |

開始後はコンポーザの Permission メニューで上書きできる（設定は初期値のみを決める）。
`SessionLaunchContext`（`.interactive` / `.remoteUser` / `.orchestration`）ごとに同じ規則を適用する。
