---
status: active
last-verified: 2026-10-23
---

# Codexの質問ツール必須化

## 解決したい問題

ユーザーへの質問が文章と箇条書きだけで出力され、選択肢から回答できない。Codexへ質問ツールの利用を必須とする指示を渡し、同期・非同期どちらの質問にも既存の質問カードで回答できるようにする。

対象はPhloxが管理するCodexのapp-server会話。Claude、Cursor、外部で起動したCLIへの指示注入は対象に含めない。

## 現状と根拠

- `AppEnvironment.codexAppServerProcessArguments()` は通常モードの質問機能を有効化していない。
- `ChatSessionViewModel` の新規開始・復元・履歴再開は `developerInstructions` を指定していない。
- 同期の `item/tool/requestUserInput` は `ChatApprovalBroker` から質問カードへ届き、回答をJSON-RPC応答で返す。
- 非同期の `agentMessage` は `delivery: async` と `questions` を保持するが、`notifyLiveAsyncQuestion` による通知と通常本文の表示だけで、質問カードと回答経路を持たない。
- 既存の `expireAllPendingUserQuestions()` は通常のターン完了でも質問を失効させる。

## 質問の方針

1. 質問、要件の確認、選択の依頼、承認の依頼は、利用条件を満たす質問ツールで行う。通常本文や最終返答だけで回答を求めない。
2. 回答を待つか、独立作業を続けるかはエージェントが判断する。利用可能で用途が許される場合は `request_user_input`、独立作業を続ける場合は `request_user_input_async` を使う。
3. 同期ツールが禁止する用途やモードでは、利用可能な非同期ツールで質問する。回答が必要な作業は明示的な返答が届くまで進めない。
4. 未回答、時間経過、ツールの受付成功、選択肢の初期選択を回答や承認と解釈しない。不要な確認を増やさず、既存の承認を尊重する。
5. 質問ツールを利用できない場合は制約を報告する。文章で質問し直して代用しない。
6. 新規開始、復元、履歴再開、会話リセット後にも同じ方針を渡す。モデルやPlanの標準指示は維持し、その利用制限を上書きしない。

既存のCodex開発者指示は、対象ディレクトリの有効な設定を `config/read` で取得してから方針を追記する。取得失敗を空の指示として握りつぶさない。設定ファイルは書き換えない。同じ方針をリセットのたびに重複追加しない。

保持対象は有効な設定と、呼び出し元が明示した開発者指示。他のクライアントが過去のthread開始時だけに指定した固有の指示は、現在の応答APIから取得できないため、保持を保証しない。外部由来の会話をPhloxで再開する場合の制約とする。

## ツールの提供

- PhloxのCodex起動引数で `features.default_mode_request_user_input=true` を指定する。ユーザーのグローバル設定は変更しない。
- 非同期質問はモデルカタログが提供する `request_user_input_async` を使う。別の自由文通知ツール `send_message_to_user_async` を質問ツールの代用として有効化しない。
- 非同期ツールの提供条件はCLIとモデルに依存する。使用できないツールを存在すると仮定する指示は渡さない。

## 非同期質問の表示と回答

| 契機 | 必要な動作 |
|---|---|
| 正しい構造のライブ質問が到着 | 既存の質問カードで選択肢と自由入力を表示する。実行中の状態を維持する。本文との二重表示を避ける。 |
| 同じ質問の再送 | thread、turn、itemの組で一枚とし、通知も一回にする。 |
| 同じ文の質問が複数ある | 配列の位置から安定した回答キーを付け、別々に回答を保持する。 |
| 同期質問が併存 | Macの一枚表示では同期質問を先に表示し、実行を止めている質問を隠さない。iOSは未回答カードを複数表示する。 |
| 実行中に回答 | `turn/steer` と `expectedTurnId` で現在のターンへユーザー入力を送る。通常の入力欄、添付、選択中のスキル、ターンの計測状態を変更しない。 |
| ターン完了後に回答 | `turn/start` で新しい入力として送る。質問が届いたターンの完了だけでは未回答カードを失効させない。 |
| 回答が受理された | 質問文と回答を対応させた入力が実際に送信できた後にだけ、カードを回答済みにして保存する。 |
| 不完全な回答・二重送信・送信失敗 | 成功扱いにしない。送信失敗はエラーを表示し、未回答カードを残して再試行できるようにする。 |
| 非同期カードを閉じる | 対象カードだけを失効させて保存する。独立作業のターンを中断せず、同意も送らない。回答送信中は閉じる操作とEscによる中断を受け付けない。 |
| 中断・リセット・別会話へ切替・プロセス終了 | 保留を失効させ、保存した未回答状態を復活させない。古い質問への回答を別threadへ送らない。 |
| 復元 | 保存済みの回答済み・失効状態を維持し、通知を再送しない。状態のない過去の質問を、未回答だと推測して再承認させない。 |

質問の配送元は既存の不透明な `requestId` に安定して符号化し、生成・解析をCodex専用の一つの型へ集める。既存の `ChatItem.userQuestion`、質問フォーム、制御APIの回答経路を再利用する。不正な構造から一部の質問だけを取り出したり、通常文章の疑問符から質問を推測したりしない。

配送IDは版を持ち、不正形式、空識別子、未知の版、別threadへの送信を拒否する。Codex用の不正IDを、別エージェントの回答経路へ流して成功表示にしない。Mac・iOSのフォームと質問DTOは、質問IDがあればそのIDを回答キーとし、古いIDなしの質問では質問文を使う。表示の識別子も回答キーに揃える。

## 成功基準

以下をリポジトリのテストで検証する。実装後に対応テストと結果を確認する。

- 起動引数が通常モードの質問を有効化し、新規・復元・履歴再開・リセットが同じ方針を保持する。
- 選択式と自由入力の非同期質問がカードになる。通常の文章、不正な質問、異なるthreadや過去turnのライブ通知からカードを作らない。
- 実行中は `turn/steer`、完了後は `turn/start` に正しい質問と回答を送る。二重送信と不完全な回答を拒否し、送信失敗で回答済みにしない。
- 通常完了後の保留、非同期だけの拒否、同期カードの優先、復元時の回答状態、リセット・終了時の失効を検証する。
- 既存の同期回答、Claude質問、制御API回答、伏せ字保存の検査が退行しない。

標準検査入口は `macos/scripts/run-swift-tests.sh CodexAppServerKit AppBootstrap SessionFeature DashboardFeature`。`compact-test` と `managed-build` を経由し、作業専用の出力先を指定する。iOSは `PhloxKit` の標準パッケージテスト、既存のraw-value lint、シミュレーター向けビルドを実行する。実Codexの質問送信と画面外描画の確認は手元検証として区別して記録する。

| 検証対象 | リポジトリのテスト |
|---|---|
| 指示保持と回答先 | `CodexAppServerKit/CodexQuestionPolicyTests` |
| 非同期wireの検証 | `CodexAppServerKit/AsyncQuestionProtocolTests` |
| 配送ID・回答キー・同期優先 | `SessionFeature/CodexAsyncQuestionIDTests` |
| 非同期質問の回答・拒否・保存・復元 | `SessionFeature/AsyncQuestionNotificationTests` |
| 実行中・完了後の描画とEsc | `SessionFeature/UserQuestionCellTests` |
| モバイルへ渡す質問ID | `AppBootstrap/UserQuestionWireTests` |
| iOSのID保持と旧形式互換 | `PhloxNetworkingTests/UserQuestionIdentityDecodingTests`、`FeaturesTests/UserQuestionIdentityTests` |

## 仮定・制約・既知リスク

手元のCLIは0.164.0。非同期質問の上流実装と提供条件は [request_user_input_async.rs](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/request_user_input_async.rs) と [spec_plan.rs](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/spec_plan.rs) を参照する。上流mainの確認はインストール済みバイナリの実行検証とは区別する。

モデルが質問を自然文で書くことを、アプリが完全に識別して阻止する保証はしない。必須指示、ツールの提供、構造化質問の確実な表示・回答経路を実装対象とする。自然文を正規表現で遮断すると引用や修辞疑問を誤検知するため採用しない。

回答を受け付ける間にターンが終わる競合は送信失敗として扱い、無条件に再送しない。回答の二重配送や、別ターンへの意図しない入力を避ける。

## スコープ外

- 質問ツールの独自MCPサーバ、独自の `dynamicTools`、新しい入力画面。
- 承認方針、権限設定、上位指示の回避。
- 未回答時の自動回答と、自動的なタイムアウト承認。

関連仕様は [Codexのフルアクセスとユーザー質問](codex-full-access-and-user-input.md)。
