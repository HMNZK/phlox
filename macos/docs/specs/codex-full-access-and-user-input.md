---
status: active
last-verified: 2026-08-01
---

# Codex のフルアクセスとユーザー質問（要件・受け入れ基準）

> **このファイルの役割**: 「フルアクセス ON のとき承認を出さない」「codex の質問に答えられる」が
> 満たすべき条件と、その受け入れ基準・用語。
> **書かないもの**: 今どう動いているか（→ [architecture/codex-app-server-server-requests.md](../architecture/codex-app-server-server-requests.md)）、
> なぜこの設計か（→ ADR 0152〜0155）。

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
  上書きできる。
- **FR-4** `item/tool/requestUserInput` を質問カードで表示し、回答を wire へ返す。
  応答形は `{"answers": {"<id>": {"answers": [...]}}}`。
- **FR-5** 回答の引き当ては `answerKey`（codex は `questions[].id`、Claude は質問文）。
- **FR-6** 質問カードの拒否は wire を決着させたうえでターンを中断する。
- **FR-7** ターンが終わるどの経路でも、保留中の質問を決着させる（宙吊りにしない）。
- **FR-8** `isSecret` の質問は伏せ字入力にし、回答済み表示もマスクする。
- **FR-9** `isSecret` の回答は wire 送信後に破棄し、永続化 JSON にも Markdown エクスポートにも
  平文を残さない。マスクは固定長で、回答の長さも漏らさない。

## 非機能要件

- **NFR-1** Claude の AskUserQuestion 経路の挙動は完全に不変。
- **NFR-2** 既存の永続データ（`id` / `isSecret` キーを持たない JSON）が従来どおり読める。
- **NFR-3** 質問カードを作る処理・マスク規則は、それぞれ 1 箇所にだけ置く（正本の一元性）。

## 受け入れ基準（凍結テスト）

| 観点 | テスト |
|---|---|
| プロトコル（デコード・-32601） | `CodexAppServerKit/AcceptanceRequestUserInputProtocolTests` |
| 橋渡し（broker） | `SessionFeature/AcceptanceCodexUserInputBridgeTests` |
| VM 配線・回答返送 | `SessionFeature/AcceptanceCodexUserInputViewModelTests` |
| 拒否・中断での決着 | `SessionFeature/AcceptanceCodexUserInputDismissTests` |
| 伏せ字入力・表示 | `SessionFeature/AcceptanceUserQuestionSecretTests` |
| 伏せ字の非永続化 | `SessionFeature/AcceptanceUserQuestionSecretPersistenceTests` |
| フルアクセス方針 | `DashboardFeature/AcceptanceFullAccessPolicyTests` |

## スコープ外

- 未対応のまま残る 8 種の server request の実装。
- 未対応 method を診断ログへ可視化すること。
- 秘密の質問における選択肢の説明文（`options[].description`）のマスク。
