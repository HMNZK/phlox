---
status: active
last-verified: 2026-10-09
---

# Codex のフルアクセスとユーザー質問（要件・受け入れ基準）

> **このファイルの役割**: 「フルアクセス ON のとき承認を出さない」「codex の質問に答えられる」が
> 満たすべき条件と、その受け入れ基準・用語。
> **書かないもの**: 今どう動いているか（→ [architecture/codex-app-server-server-requests.md](../architecture/codex-app-server-server-requests.md)）、
> なぜこの設計か（→ ADR 0154〜0157）。

## 用語

| 用語 | 意味 |
|---|---|
| server request | codex app-server が client（Phlox）へ送る JSON-RPC 要求。全 11 種 |
| 承認 | コマンド実行・パッチ適用の可否を尋ねる server request。`approvalPolicy` の支配下にある |
| 質問 | `item/tool/requestUserInput`。モデルがユーザーに尋ねる。承認ではなく `approvalPolicy` の支配外 |
| フルアクセス | 設定 `phlox.bypass.codex`（`BypassSettings`）。未設定時は ON |
| 回答キー | 回答ディクショナリのキー。`ChatUserQuestion.answerKey` = `id ?? question` |
| 伏せ字 | `questions[].isSecret`。パスワード等の秘匿入力 |

## 機能要件

- **FR-1** 未対応の server request を承認バナーとして表示しない。JSON-RPC の
  `-32601 Method not found` で応答する。
- **FR-2** フルアクセス ON のとき、app-server セッションで承認を出さない
  （`approvalPolicy = never` / `sandboxPolicy = danger-full-access`）。
  OFF のときは `on-request` / `workspace-write`。
- **FR-3** 設定はスレッド開始時の初期値を決める。開始後はコンポーザの Permission メニューで
  上書きできる。組み込みプリセットはプロファイルと承認方針を同じリクエストで変更する。
  Read Only / Default は `on-request`、Full Access は `never`。カスタムプロファイルでは
  承認方針を変更しない。開始・復元応答と設定変更通知が示す実際の状態を表示し、確認前や
  失敗時に選択値を表示しない。異なる方針の組み合わせは Custom と表示する。
- **FR-3a** 確認された承認方針も保存・復元する。旧保存データには組み込みプリセットの
  方針を補う。項目別の承認方針はその形式を保持する。復元途中に届く設定通知も、
  復元対象の会話 ID と照合して反映し、開始時の権限で保存値を上書きしない。
- **FR-3b** Claude の権限変更は `set_permission_mode` の成功応答後に表示・保存する。
  変更中は設定操作・次ターンの送信を受け付けない。拒否時は旧値を維持しエラーを表示する。
  送信失敗・タイムアウトで適用状態が不明なら対象 CLI を閉じ、次の送信で確認済みの権限を使う。
  新規会話は起動時の既定権限、復元は保存済みの権限・Plan を使い、CLI の起動前に設定する。
  標準権限を使う経路には追加の全ツール許可を注入しない。
- **FR-4** `item/tool/requestUserInput` を質問カードで表示し、回答を wire へ返す。
  応答形は `{"answers": {"<id>": {"answers": [...]}}}`。
- **FR-5** 回答の引き当ては `answerKey`（codex は `questions[].id`、Claude は質問文）。
- **FR-6** 質問カードの拒否は wire を決着させたうえでターンを中断する。
- **FR-7** ターンが終わるどの経路でも、保留中の質問を決着させる（宙吊りにしない）。
- **FR-8** `isSecret` の質問は伏せ字入力にし、回答済み表示もマスクする。
- **FR-9** `isSecret` の回答は wire 送信後に破棄し、永続化 JSON にも Markdown エクスポートにも
  平文を残さない。マスクは固定長で、回答の長さも漏らさない。
- **FR-10** `agentMessage` の `delivery: async` と非空の `questions` を持つライブ質問は、
  実行を止めず質問到着を通知する。同じ thread / turn / item の再送は通知せず、
  別の質問は同じ実行状態でも通知する。履歴復元では通知しない。
- **FR-11** 通常の質問も要求 ID ごとに通知する。表示中の会話の質問も通知し、
  OS 許可・ユーザーの通知設定は尊重する。通知送信の失敗は本文を含めず記録する。

## 非機能要件

- **NFR-1** Claude の AskUserQuestion の回答・拒否の経路は維持する。通知は要求 ID ごとに送り、
  別の質問が続いた場合も省略しない。
- **NFR-2** 既存の永続データ（`id` / `isSecret` キーを持たない JSON）が従来どおり読める。
- **NFR-3** 質問カードを作る処理・マスク規則は、それぞれ 1 箇所にだけ置く（正本の一元性）。

## 受け入れ基準（凍結テスト）

| 観点 | テスト |
|---|---|
| プロトコル（デコード・-32601） | `CodexAppServerKit/RequestUserInputProtocolTests` |
| 橋渡し（broker） | `SessionFeature/CodexUserInputBridgeTests` |
| VM 配線・回答返送 | `SessionFeature/CodexUserInputViewModelTests` |
| 非同期質問の形式保持 | `CodexAppServerKit/AsyncQuestionProtocolTests` |
| 実行継続中の質問通知・重複・復元とturn識別 | `SessionFeature/AsyncQuestionNotificationTests` |
| 拒否・中断での決着 | `SessionFeature/AcceptanceCodexUserInputDismissTests` |
| 伏せ字入力・表示 | `SessionFeature/AcceptanceUserQuestionSecretTests` |
| 伏せ字の非永続化 | `SessionFeature/UserQuestionSecretAnswerTests` |
| フルアクセス方針 | `DashboardFeature/FullAccessPolicyTests` |
| Claude の権限適用・失敗・起動順序 | `ClaudeAgentKit/LivePermissionTests`、`SessionFeature/ClaudePermissionApplyTests`、`DashboardFeature/chatSessionViewModel_claudeRestoreUsesSavedPermissionBeforeLaunchingCLI` |
| セッション内の権限変更・復元・表示・失敗 | `SessionFeature/EffortCycleTests` の権限関連テスト |
| 標準の権限名と説明 | `DesignSystem/AcceptancePermissionWordingTests` |

## スコープ外

- 未対応のまま残る 8 種の server request の実装。
- 未対応 method を診断ログへ可視化すること。
- 秘密の質問における選択肢の説明文（`options[].description`）のマスク。
