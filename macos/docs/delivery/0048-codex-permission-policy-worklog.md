---
status: complete
last-verified: 2026-10-09
---

# Codex・Claude の権限変更と表示の一致

## 要件と原因

「承認なし・実行制限なし」を選んでも `permissions` だけ更新していたため、`approvalPolicy: on-request` が残った。保存済みの権限の再適用でも同じ問題があり、失敗時にも保存値を画面へ反映していた。

ユーザー指示により、権限名は各エージェントの標準の名称を使い、日本語の説明は別に維持する。

## 設計

- Codex の組み込みプリセットは、プロファイルと承認方針を同じリクエストで変更する。Read Only / Default は `on-request`、Full Access は `never`。カスタムプロファイルの選択では承認方針を上書きしない。
- `thread/settings/update` の応答は空。適用後の状態は `thread/settings/updated` 通知と開始・復元応答を正本とし、選択値を先に画面へ代入しない。更新失敗は既存のエラー表示へ載せる。
- 実際のサンドボックスと承認方針が組み込みプリセットに一致する場合だけ、その名称を表示・選択状態にする。それ以外の組み合わせは Custom と表示する。
- 承認方針を保存・復元する。Foundation のみに依存する AgentDomain には JSON 文字列として保存し、名前付き・項目別の両形式を保持する。旧保存データに承認方針がなければ組み込みプリセットの方針を補う。
- 復元途中は会話の ID がまだ公開状態に入っていないため、復元対象の ID を別に保持して、その会話の設定通知だけを受け取る。復元完了前に届いた実際の権限を捨てない。
- 権限の一覧取得で既定の Full Access を表示する処理を削除し、確認された状態だけを表示する。
- 開始画面の起動カードにも同じ名称を使う。Cursor の実行許可は公式の Run Everything と表示する。
- 設定画面の既定権限の説明と読み上げラベルにも、同じ標準名称を使う。ターミナルの起動設定に従う場合や、Cursor のサンドボックス解除は別に説明する。
- Codex 0.162.0 の名称は Read Only / Default / Full Access。Claude は Manual / Accept Edits / Auto / Bypass Permissions / Don't Ask / Plan。Cursor は Agent / Ask / Plan。いずれも表示名は標準名称、説明は表示言語に従う。

## 参照した正本

- [Codex 0.162.0 のプリセット定義](https://github.com/openai/codex/blob/rust-v0.162.0/codex-rs/utils/approval-presets/src/lib.rs)
- [Codex の実行範囲と承認方針](https://learn.chatgpt.com/docs/sandboxing)
- [Claude Code の権限モード](https://code.claude.com/docs/en/permission-modes)
- [Cursor CLI のモード](https://cursor.com/docs/cli/overview)
- [Cursor CLI の Run Everything](https://prod.cursor.com/docs/cli/reference/slash-commands)

## 検証計画

### Claude の追加修正（2026-10-09）

- 権限変更は公式 SDK と同じ `set_permission_mode` 制御要求を使う。CLI の成功応答を受けてから入力欄と保存値を変更する。モデル・effort の変更は従来の次ターンでの再起動を維持する。
- 制御要求の失敗は表示し、選択値を変更しない。同時変更は受け付けず、応答待ちに上限を設ける。送信失敗・タイムアウトで実権限が不明な場合は対象の CLI を閉じ、次の送信では確認済みの権限で起動する。
- 新規会話は起動時の既定権限を使う。復元する会話は保存済みの権限・Plan を優先し、CLI の起動前に設定する。
- Claude の標準権限を使う起動経路では、Phlox が追加の全ツール許可を注入しない。Bypass Permissions から Manual に変更しても別の許可リストが残らないようにする。AskUserQuestion は従来どおりユーザーへ提示する。
- 実 CLI で Auto → Bypass Permissions が `bypass_not_launched` で拒否された。起動引数に `--allow-dangerously-skip-permissions` を渡し、後から Bypass Permissions を選択できるようにする。この引数だけでは承認を省略せず、実際のモードは引き続き `--permission-mode` と変更の成功応答で決まる。
- 成功・拒否・送信失敗・タイムアウト・切断・実行中の変更、保存済み設定を用いた起動順序を検査する。修正がまとまった後、Claude の別セッションで Codex と Claude の差分をまとめて独立レビューする。

一次情報: [Anthropic の SDK 制御要求](https://github.com/anthropics/claude-agent-sdk-python/blob/main/src/claude_agent_sdk/_internal/query.py) の `set_permission_mode`。実 CLI の応答も手元で確認する。

### 独立レビュー後の修正

- Claude の実行中に適用状態が不明になり CLI を閉じた場合は、ターンの中断を通知して画面の実行中状態も解除する。
- Codex の保存設定の再適用が失敗した場合、表示は現在の実権限を保ち、起動時の値で保存済みの設定を上書きしない。成功応答・設定通知による保存は維持する。
- 起動引数の完全一致テストも、後から Bypass Permissions を選べるオプションを含む契約へ更新する。無条件の承認省略と追加ツール許可が無いことは引き続き検査する。
- Plan の表示名を既存の文言定義にまとめ、削除した Claude の追加許可処理の説明を除く。最終差分を固定して Claude に再レビューする。
- 再レビューで、権限変更中の次メッセージが CLI に拒否されると、既存の実行中表示が待機へ変わる事象が見つかった。送信可否・下書きの取り出し・Control API の送信入口で変更中を判定し、状態・下書き・履歴を変更する前に送信を止める。
- Codex の再適用の成功応答も権限の確認ではない。保存値と現在の権限が一致するまでは保存コールバックを呼ばず、後から届く設定通知で保存する。通知による保存自体も回帰テストに含める。
- CLI の終了待ちの途中で会話が再起動された場合、旧権限要求の終了通知を新しいターンへ送らない。同じ要求を二重に終了しないよう、要求とプロセスの世代を照合する。
- 最終レビューは Codex・Claude とも pass。内部エラー名の表示と古いコメントの軽微な指摘も直す。終了処理に入った CLI の遅い成功・拒否応答では、未確認の変更を確定しないことを追加検査する。
- 追加検査で遅い応答の問題を 7 issue で再現し、終了処理中の transport を確認条件から除いた。追加テストの最初の診断実行はイベント待ちが終わらず停止（exit 143）したため、検査自身を先に閉じて結果を確定する形へ直してから red を採取した。
- 追加レビューで、Codex の JSONRPC エラーと CLI の送信エラーには読める説明がなく、localizedDescription で拒否理由が消える点が見つかった。画面の入口ごとの補正ではなく、実際のエラー型に説明を持たせる。本番と同じエラー型で拒否理由・送信失敗の表示を回帰検査する。
- Codex のサーバー拒否と CLI の stdinClosed を使う表示検査は 2 issue の red を再現し、エラー型へ LocalizedError を追加後に green。保存設定の再適用でも複数行・長い拒否理由が省かれないことを検査する。

- 権限変更の両フィールド、通知による状態同期、失敗、応答順の逆転、旧データ・項目別方針の復元を回帰テストに含める。
- 標準名称と、承認方針が違う場合に Full Access と表示しないことを検査する。
- 適用対象の Swift パッケージは `run-swift-tests.sh` を compact-test 経由で実行する。
- Debug のビルド・リンク、およびユーザーの Release / Debug とデータを分離した UI 確認を行う。

## 実行結果

### 依頼項目

- 承認なしの選択で承認方針が残る問題: 修正済み。プロファイルと承認方針を同時に送る。
- 各 AI の標準名称: 入力欄・メニュー・起動カード・設定画面を更新済み。説明は日本語・英語を維持。
- 保存・復元と失敗時の表示: 確認済みの権限だけを表示・保存し、復元途中の通知も受け取る。
- Claude の適用・復元: 制御要求の成功後に表示・保存。保存済みの権限・Plan を CLI の初回起動前に適用し、Phlox の追加ツール許可を除いた。変更待ちの送信と旧 CLI 終了の競合も回帰テストで検査。
- Codex・Claude の独立レビュー: 実際の Claude Opus 5.5 の別セッションで実施。指摘を修正し、最終判定は両方 pass、追加指摘なし。

### 自動検証と実画面

すべてのテスト実行は `~/.agents/scripts/compact-test` 経由。

| 検証 | 結果 |
|---|---|
| AgentDomain | 589 件成功 |
| DesignSystem | 193 件成功 |
| StructuredChatKit | 28 件成功 |
| CodexAppServerKit | 100 件成功 |
| ClaudeAgentKit | 197 件成功 |
| SessionFeature | 1,162 件成功 |
| DashboardFeature | 本体 1,986 件・実 git 26 件成功 |
| AppBootstrap | 162 件成功 |
| 対象 8 パッケージ合計 | 4,443 件成功、canonical runner exit 0 |
| 実 Codex 0.162.0 app-server | 3 プリセットの変更通知で `never` / `on-request` とサンドボックスの組を確認 |
| 実 Claude CLI | Manual → Plan → Manual、Auto → Bypass Permissions → Manual の成功応答を同じ CLI プロセスで確認 |
| Debug のビルド・リンク | `BUILD SUCCEEDED`、exit 0 |
| 分離した Debug の実画面 | Codex の Full Access / Read Only、Claude の権限メニュー、3 AI の起動カードと設定画面の名称を確認 |
| 実会話の復元 | 短い確認メッセージと応答を保存。Read Only / `on-request` を変更・保存し、再起動後も表示と保存値が維持されることを確認 |
| Claude 実会話の復元 | Manual と Plan をそれぞれ保存して再起動。表示と CLI 起動引数が一致し、追加 `--allowedTools` がないことを確認。最終ビルドでも Plan と会話履歴の復元を確認 |

標準のパッケージ検査は `macos/scripts/run-swift-tests.sh` を使用。実 app-server の検査と実画面操作は手元で実行し、リポジトリの E2E テストには未登録。権限を直接扱う XCUITest は見つからず、XCUITest 一式は実行していない。単独の lint・静的解析の設定は見つからず、型チェックは Swift のコンパイルで行った。

実 Claude CLI の制御要求ドライバはモデルのターンを実行しない。実行中の変更・失敗はテスト用 transport で検査しており、本物の CLI の実行中ターンでの変更は未検証。実画面で確認したのは権限の変更と保存済み会話・権限の再起動復元。エラー理由の全文保持はリポジトリの回帰テストと描画経路のコードレビューで検査し、実画面での拒否エラー表示は未検証。

### 観測した失敗・警告

- 修正前の権限テストを red にして、承認方針の欠落・失敗時の誤表示を再現。実画面で見つけた復元途中の通知の欠落も、追加テストで 4 issue を再現して修正した。
- 旧名称・通知を送らないテストダブル・未設定時に Full Access を作る旧期待の検査が失敗した。標準名称と実際の通知による同期を検査するよう更新し、成功を確認した。最終の設定画面更新では「名称は言語ごとに異なる」という旧前提が 1 件失敗した。名称は共通、説明は言語別という要件を検査するよう更新し、DesignSystem 193 件を再実行して成功。他の対象パッケージは同じ最終ソースで成功済み。
- 中間段階で引数不足・テストダブルの呼び出し誤りによるコンパイル失敗、ビルド中のソース変更の検出があった。修正を確定した後にビルドとテストを再実行した。
- Claude の独立レビューで、CLI 終了後の実行中表示、旧起動引数の期待、Plan の旧日本語期待、変更中に次の送信を行った場合の状態変更が見つかった。修正した。また Codex の復元失敗時の保存値上書きと空の成功応答による保存、旧 CLI の終了通知が新しい会話へ届く問題を red で再現し、修正後の回帰テストが成功した。
- 公開の任意 `preApprovalPolicy` API は互換性のため維持した。`resolvedPermissionMode` / `resolvedAllowedTools` 自体はコンストラクタ・起動引数構築で呼ばれている。Phlox の既定 Claude factory はこの API に値を渡さず、追加の全ツール許可を注入しない。Manual はインストール済み CLI の起動引数と制御要求で受け付けられることを実走で確認した。
- メッセージ未送信の検証用会話は、再起動時に `no rollout found for thread id` で復元に失敗した。メッセージを送って履歴を作った別の検証用会話で権限の復元を確認した。未送信会話の既存の復元失敗は本変更では修正していない。
- 既存の `popupAnimatesOnlyTheSelectedDescription` が一度 `animationKeys()?.count == 1`（実測 2）で失敗。後続の単独・パッケージ検査では成功。キーを採取する一時診断を入れ、11 件のスイートを 20 回実行したが再現せず（いずれも `descriptionScroll` だけ）。診断コードは削除した。原因は未特定で、再実行の成功を根本解決とは扱わない。
- Debug のフルビルドで既存の警告が 4 種類出た: PTYKit の `init(cString:)` 非推奨、TerminalUI の non-Sendable コールバック、DashboardView の明示 return による ViewBuilder 無効化、AppIntents.framework 不在によるメタデータ抽出スキップ。最終の増分ビルドでは DashboardView とメタデータ抽出スキップの警告が出た。
- 最終パッケージ検査では、変更対象外のテストに AX API 非推奨、MainActor 以外から UI へアクセスする警告、不要な try、戻り値の未使用が出た。ビルドとテストは成功したが、この警告を本変更で修正したとは扱わない。

### 作業状態

- 実際の Claude Opus 5.5 の独立した新規セッションで、Codex と Claude のまとまった差分をレビューした。初回・2 回目の指摘を修正し、3 回目で両方 pass。軽微な文言指摘と追加の遅い応答の競合を直した。4 回目の実エラー型の説明不足も修正し、5 回目の最終判定は Codex・Claude とも pass、追加指摘なし。最終レビューの実走は SessionFeature 33 件、ClaudeAgentKit 9 件、CodexAppServerKit 7 件成功。
- レビューで範囲外とされた既存課題: Codex の Plan 切り替えの一部は try? のため失敗を表示しない。Claude の起動失敗は理由を保つが内部 enum の形で表示する箇所がある。権限変更の成功確認・保存・復元とは別の既存課題として記録し、本変更で修正済みとは扱わない。
- 検証用に起動した Debug と、その子プロセスを停止し、残存しないことを `ps` で確認。ユーザーの Release（PID 55416）と既存 Debug（PID 61367）は継続稼働。
- 2026-10-09、ユーザーがコミット・dev へのマージを承認。dev と作業ブランチの基点は同一で、レビュー・検証済みのソースを fast-forward で取り込む。
- 検証ログ・独立レビュー・検査用ドライバはメイン作業ディレクトリの `.build/permission-validation-20261009/` に保管する。検証専用アプリ・会話データと不要になった作業 worktree は、統合後に後始末する。
- 最終の canonical 検査は `permission-native-final-gate.log`、ビルドは `permission-native-final-build.log`。独立レビューは `claude-independent-review-complete.jsonl`、`claude-independent-review-followup.jsonl`、最終の `claude-independent-review-native-errors.jsonl`。
- 最終レビューと検査の間にソース・テストを変更していないことを SHA-256 で照合した。レビューの拒否された調査コマンドは実行済みと扱わず、レビュアーは許可された個別の読み取りで再取得した。
