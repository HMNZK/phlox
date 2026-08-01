---
status: completed
last-verified: 2026-08-01
---

# 0030: Codex のフルアクセスとユーザー質問（codex-full-access-approval run）

> agentic-loop run（backend=codex: deep=gpt-5.6-luna effort=max / standard=gpt-5.6-terra effort=high）。
> ブランチ `feature/codex-full-access-approval`。独立レビューは実装が Codex のため
> Claude `persona-reviewer`（クロスモデル）。

## 何をしたか

「Codex をフルアクセスにしているのに `Unsupported server request: item/tool/requestUserInput` の
承認プロンプトが出る」という報告の原因を調べ、**独立した 2 つの欠陥**を直した。

1. **承認ではないものが承認バナーに化けていた**（報告の直接原因）。`ChatApprovalBroker` が
   未知の server request をすべて `kind: .permissions` へ写像していたため、codex の 11 種のうち
   8 種が偽の承認バナーとして表示され、Accept すると `{"permissions": null, "scope": "turn"}` という
   期待されない応答を返していた。承認ではないので `approvalPolicy` の支配下になく、
   フルアクセスでは決して抑止できなかった。
2. **フルアクセス設定が app-server に届いていなかった**。`BypassSettings` はターミナルモードの
   CLI オプションにしか反映されず、`SessionSpawnService` は承認・サンドボックス方針を
   ハードコードしていた。

あわせて、エラーで返すだけでは質問に答えられなくなるため、`item/tool/requestUserInput` を
既存の質問カードへ合流させて実装した（ゲート①の決定 D1）。

| タスク | 内容 | レビュー往復 |
|---|---|---|
| task-1 | プロトコル型と `-32601`（未対応は承認に化けさせない） | r1 pass |
| task-2 | `ChatApprovalBroker` の質問経路（承認とは別ストリーム） | r1 pass（partial 報告を PM が裁定して続行） |
| task-3 | フルアクセス設定を app-server の approval/sandbox 方針へ適用 | r1 pass（旧テストの契約欠陥を PM が修理） |
| task-4 | ViewModel・TranscriptView への配線、拒否＝中断 | r1・r2 needs_changes → r3 pass |
| task-5 | 伏せ字入力（`isSecret`）の UI | r1〜r3 needs_changes → r4 pass |
| task-6 | 伏せ字の回答を永続化・エクスポートに残さない | r1 pass |

決定は ADR へ蒸留した:
[0152](../adr/0152-codex-unsupported-server-request-is-not-an-approval.md)（未対応は承認に化けさせない）/
[0153](../adr/0153-codex-request-user-input-as-question-card.md)（質問カードへ合流・拒否は中断）/
[0154](../adr/0154-full-access-setting-applies-to-app-server.md)（フルアクセス設定の適用先）/
[0155](../adr/0155-secret-answers-are-not-persisted.md)（伏せ字の回答は保存しない）。
現行構成は [architecture/codex-app-server-server-requests.md](../architecture/codex-app-server-server-requests.md)、
要件・受け入れ基準は [specs/codex-full-access-and-user-input.md](../specs/codex-full-access-and-user-input.md)。

## ゲート①の決定

| # | 論点 | 決定 |
|---|---|---|
| D1 | バナーを消すだけか、質問 UI を実装するか | 質問 UI をきちんと実装する |
| D2 | フルアクセスの既定 | 既存の ON（`BypassSettings` 既定 true）をそのまま app-server にも適用 |
| D3 | 設定とコンポーザの Permission メニューの関係 | 設定は開始時の初期値。以後はメニューで上書き可 |
| D4 | 質問の Decline / Cancel | ターンを中断する（空回答で続行しない） |
| D5 | `isSecret` の扱い | 今回の run で対応する（task-5）。さらに平文の永続化も今回塞ぐ（task-6） |

## PM 裁定（契約の欠陥として処理したもの）

実装の欠陥ではなく分解（契約）の欠陥と判定し、差し戻しではなく契約側を直して再凍結した:

- **task-3**: 旧テストが変更前の仕様（`on-request` / `workspace-write` 固定）を符号化していた。
  PM が別コミットで旧テストを修理（フルアクセス OFF の `UserDefaults` スイートを渡す形へ）。
- **task-4（MUST）**: 拒否ボタンの実配線ファイル `ChatTranscriptView.swift` が `allowed_paths` に
  無く、`declineUserQuestion` を実装しても製品コードから呼ばれない状態だった。
- **task-4（HIGH）**: 事後条件が dismiss ボタンだけを名指していたため、他の中断経路が抜けていた。
  「入口ごと」ではなく「ターンが終わる時点」で塞ぐ契約へ改めた。

## 検証結果

- `verify.sh` 全数 green（exit 0）: CodexAppServerKit 49 / SessionFeature 785 / DashboardFeature 1568。
  凍結テストの改変検査も pass。
- Debug ビルド成功（`xcodebuild -scheme Phlox -configuration Debug`、derivedDataPath は
  `/tmp/phlox-dd-task6`）。**稼働中のリリース版アプリは終了させていない。**
- task-5 / task-6 はレビュアーが /tmp の複製で変異検査を実施し、マスク撤去・送信前マスク・
  エクスポータのキー退行・`isSecret` フィルタ撤去・長さ依存マスクの 5 変異すべてで
  受け入れテストが red になることを確認（テストの穴で通っている実装ではない）。

## 未検証・残課題

- **GUI の E2E は未実施**。ユーザーが実作業中のリリース版 Phlox を落とさないため、Debug 版の
  起動確認を行っていない。実際に codex から質問が飛んできたときの画面表示は**未観測**。
- 未対応のまま残る 8 種の server request は `-32601` を返すだけで、診断ログに現れない。
- 秘密の質問が選択肢を持つ場合、`options[].description` は平文で表示・保存される（ADR 0155）。
- 環境メモ: このマシンには Homebrew / XcodeGen が無く、`.xcodeproj` の生成に
  XcodeGen をソースからビルドして使った（`/tmp/XcodeGen`）。
