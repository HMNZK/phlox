---
status: accepted
last-verified: 2026-07-19
---

# ADR 0102: AskUserQuestion を CLI control protocol（can_use_tool 中継）で実装する

> **このファイルの役割**: Claude チャットが `AskUserQuestion` ツール（選択肢提示→回答）に対応するため、`claude -p` の stream-json 輸送層へ CLI control protocol（`can_use_tool` → `control_response`）を最小実装した決定と理由。
> **書かないもの**: 現状の spawn/respawn 状態機械全体（→ [architecture/claude-chat-session-lifecycle.md](../architecture/claude-chat-session-lifecycle.md)）、wire DTO・REST 経路（→ [ADR 0103](0103-user-question-wire-mirror.md)）。

## 文脈

Phlox の Claude 連携は headless `-p` + stream-json 直結（`ClaudeChatClient`）で、tool_result / control_response を CLI へ書き戻す経路が存在しなかった（ADR 0017 の submit ゲートは turn 単位の事前承認のみで、per-tool 対話は明示的にスコープ外）。このため `AskUserQuestion` が呼ばれても選択肢が UI に出ず、回答を返送する手段もなかった。

生の stream-json（公式 TypeScript/Python SDK 不使用）で SDK の `canUseTool` 相当を有効化する条件は公式ドキュメントに明記がなく、フェーズ0時点では「仮説」扱いだった。フェーズ1で公式 **Python SDK ソース**（`client.py` / `subprocess_cli.py`）を確認し、以下を裏取りした:

- SDK は `canUseTool` 指定時に CLI へ **`--permission-prompt-tool stdio`** を渡す。
- `AskUserQuestion` は **allow ルールの一致に関わらず常に** `can_use_tool` コールバックへフォールスルーする（`dontAsk` モードのみ deny）。
- `allowedTools` に一致する通常ツールは `can_use_tool` へ飛んでこない（spawn 時固定の acceptEdits + allow ルールで自動承認される既存動作は変わらない）。

## 決定

1. **spawn 引数に `--permission-prompt-tool stdio` を常時付与する**（`ClaudeChatClient+Respawn.swift` の `buildArguments`）。既存 `ClaudeChatClientTests` の spawn 引数完全一致アサーション2箇所は、意図した仕様変更への追随として PM が新引数込みの期待値へ更新した（完全一致検証は維持）。
2. **`can_use_tool` は `AskUserQuestion` のみ中継し、それ以外は即時 deny する**。`toolName != "AskUserQuestion"` の分岐は `sendControlDeny(message: "Phlox: per-tool permission prompts are not supported")` を返す（`ClaudeChatClient+ControlProtocol.swift:14-27`）。allow ルール一致の通常ツールはそもそも `can_use_tool` へ来ないため、この deny 経路は「allow ルール外で呼ばれた未知ツール」への保守的フォールバックとして機能する（有効化条件の解釈違いで通常ツールの問い合わせが流れてきても既存挙動を壊さないための防衛）。
3. **AskUserQuestion は保留台帳（`pendingUserQuestions[requestId]`）に登録し `.userQuestionRequested` を yield**、回答は `respondToUserQuestion(requestId:answers:)` が `behavior: "allow"` + `updatedInput.answers` を `control_response` として stdin へ書く（`controlResponseLine`、`ClaudeChatClient+ControlProtocol.swift:171-186`）。

## 失効セマンティクス

保留質問は次のいずれかで expire（`.userQuestionResolved(.expired)` を yield し台帳から除去）する:

| トリガー | scope | 実装 |
|---|---|---|
| `close()` | 全世代 | `ClaudeChatClient.swift:375` |
| respawn（`spawn()`） | 全世代（close 前後の二段） | `Respawn.swift:7,18` |
| `interrupt()` | 当該世代 | `ClaudeChatClient.swift:334-335` |
| stream 終了（`handleStreamEnded`） | 当該世代 | `:50` |
| control_response 送信エラー | 個別 request | `markUserQuestionResponseFailed` |

**世代ガード**（`pending.generation == spawnGeneration`）により、respawn 後に旧世代の応答が新しい transport へ書き込まれることはない（白箱 `respawnExpiresPendingAndOldResponseNeverWritesToNewTransport` で `secondTransport.sent.isEmpty` を確認）。`interrupt()` は `transport.interrupt()` の**前**に deny を送信し、`.turnInterrupted` の後で control_response 送信エラーを throw する（interrupt で必ずイベントが出る契約を壊さない）。

## 二重応答ガード（2層で対処した2件の競合）

実装過程で、非同期の await 境界をまたぐ「pending 判定の有効期限切れ」に起因する二重応答レースを2箇所で検出・修正した。いずれも凍結受け入れテストは通っていたが、追加の競合再現テストで red→green を実証したうえでの修正。

### 1. actor 層: interrupt が allow 送信中の質問へ deny を重ねる（stage2 MEDIUM・608db5b）

`respondToUserQuestion` は `pending.isResponding = true` をセットしてから `await transport.send(line)` で suspend する。旧実装の `interrupt()` は `pendingUserQuestions.filter { $0.value.generation == generation }` で deny 対象を集めており、`isResponding` を見ていなかった。送信 suspend 中に `interrupt()` が走ると、同一 `request_id` へ **allow（送信中）＋ deny（interrupt）の二重 control_response** が届きうる。

修正: deny 対象スナップショットから `isResponding` の質問を除外する1行（`!$0.value.isResponding`）。`isResponding` フラグ自体は respond 側の再入ガードとして既に存在していたが、interrupt 側がそれを横断参照していなかった設計上の内部不整合が原因。suspend 可能なモック transport による競合再現テスト（`interrupt()` を send suspend 中に呼び、`sent` に allow と deny が両方現れないことを確認）で red（`["deny","allow"]`）→ green を実証。

### 2. VM 層: await をまたぐ pending 判定無効化（stage1 MUST・0ca0431）

macOS 質問カードの `ChatSessionViewModel.respondToUserQuestion` は「`.pending` 判定（同期）→ `await client.respondToUserQuestion(...)`（サスペンションポイント）→ `.answered` へ appendOrReplace（同期）」の順序で、ガード判定が await の**前**にしか行われなかった。真の同時呼び出し（連打等）で2つの呼び出しがほぼ同時に発火すると、片方の await 完了前にもう片方がガードを通過し、両方が true を返して transcript の answers が競合上書きされうる（actor 側の `isResponding` は CLI への実二重送信は防ぐが、VM 層の戻り値の二重成功は防がない）。

修正: 送信中 requestId の集合（`respondingUserQuestionIds`）を `@MainActor` 同期で管理し、await 前に登録・完了後に解除するガードを追加。gate 付き fake client による競合再現テストで red（両方 true・2回送信）→ green を実証。詳細は [ADR 0103](0103-user-question-wire-mirror.md) ではなく本 ADR のスコープ（control protocol の輸送・応答経路）として扱う。

## 回答の内部表現

- **VM/actor 内部表現**: 「質問文 → label 配列」（`[String: [String]]`）。single-select は1要素配列、自由入力は任意文字列をそのまま値にする。
- **wire（control_response の `updatedInput.answers`）への射影**: SDK 仕様に合わせ `projectAnswers` が single=`String`・multiSelect=`[String]` に変換する（`ClaudeChatClient+ControlProtocol.swift:155-169`）。multiSelect で選択が無い質問はキー自体を出力しない。

## 棄却案

- **公式 SDK（claude-agent-sdk）への乗り換え**: `canUseTool` が最初から使えるが、既存 `ClaudeChatClient`（stream-json 直結・self-heal・resume 追従）の全面置き換えになり影響範囲が桁違いに大きい。不採用。
- **独自 MCP サーバーによる `--permission-prompt-tool`**: 別プロセス・別プロトコルの追加になり、stdio control protocol より複雑。SDK 自身が stdio 方式を使っているため踏襲。
- **turn 単位ゲート（ADR 0017）の拡張で代替**: AskUserQuestion は「実行許可」ではなく「回答の注入」であり、submit ゲートでは原理的に代替不能。

## 未検証事項

- **実 Claude セッションでの E2E は未実施**（課金となるためフェーズ0の方針どおり、別途の明示承認があるときのみ実施とした）。検証はモック transport（fixture 準拠の受け入れテスト・競合再現テスト）まで。生 CLI の control protocol 実挙動（二重 control_response をどう扱うか等）は未確認。
- interrupt 中に到着した同世代 `can_use_tool` を握って誤ラベルの warning を出す点、malformed AskUserQuestion / 重複 request_id で無応答になりうる点は、レビューで LOW と裁定され契約外の稀ケースとして未対応（信頼できる CLI 相手では現実性が低い。対応するなら deny 方針の拡張で足りる）。

## 結果

- `ClaudeAgentKit` 116テスト green（受け入れ・白箱・競合再現テストを含む）。既存承認テスト（ADR 0017）の回帰なし。
- 回答配送の wire ミラー（DTO・REST）は [ADR 0103](0103-user-question-wire-mirror.md)、UI 実装は [architecture/claude-chat-session-lifecycle.md](../architecture/claude-chat-session-lifecycle.md) 参照。
