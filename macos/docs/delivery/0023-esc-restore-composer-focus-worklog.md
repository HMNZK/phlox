---
status: completed
last-verified: 2026-07-28
---

# 0023: esc 巻き戻し後に入力欄へフォーカスとキャレットを返す 作業ログ

> **このファイルの役割**: `feature/esc-restore-input-focus` で何をしたか、どこまで検証したか、何が未検証かの記録。
> **書かないもの**: 決定の理由（→ [ADR 0135](../adr/0135-restored-draft-is-written-by-the-view-model.md)）、要件と受け入れ基準（→ [specs/esc-revert-composer-focus.md](../specs/esc-revert-composer-focus.md)）。

## 背景

ユーザー報告: 「esc を 2 回押して入力を戻したあと、入力欄をクリックしないとタイプを再開できない」。
調査の結果、履歴ピッカー（`ChatHistoryRevertPicker`）が `.focused()` で自らフォーカスを取る一方、閉じるときの返却先が定義されておらず、`macos/Packages/*/Sources/` 全体で composer に対する `makeFirstResponder` が 1 箇所も存在しなかった。加えて復元本文のキャレットは先頭に残るため、フォーカスだけ戻しても打った文字が復元本文の前に入る。

## 実装内容

agentic-loop の 2 タスク逐次チェーン（並列度 1）。契約化できる並列境界が無く、task-2 は task-1 の公開状態を読むため。

| task | 内容 | 主要変更 |
|---|---|---|
| task-1 | `ComposerFocusRequest` の発火（ViewModel 側） | `ComposerFocusRequest.swift`（新規）・`ChatSessionViewModel.swift` |
| task-2 | フォーカス要求の適用とキャレット末尾化・両 View 配線 | `ChatComposer.swift`・`ChatEscapeHandling.swift`・`GridChatColumn.swift` |

公開面（`ComposerFocusRequest` 型、ViewModel と `IMESafeTextView` のプロパティ宣言）は PM が先に凍結した。受け入れテストが型を参照するため、凍結前の実走検証（red-for-the-right-reason）がコンパイルエラーではなくアサーション失敗で取れるようにするため。

`ComposerFocusRequest` は `token`（狭義単調増加）と `movesCaretToEnd` を持つ値型。View は token の**変化**だけを見てフォーカスを動かす（同一 token の再描画では動かさない＝ NFR1）。

## 設計をやり直した経緯（重要）

当初は「復元本文が `draftRestoration → onChange → draft → text binding` で 1 更新パス遅れて届く」ことを固定の制約として受け入れ、View 側に保留フラグ（`pendingCaretToEnd`）を置いて遅れを吸収した。この設計は**独立レビュー 4 巡すべてで HIGH / MEDIUM を受けた**。

決め手は、3 巡目（保留が早く消えすぎる）と 4 巡目（保留が残りすぎる）で指摘が**逆方向に振れた**こと。同じ 1 個の Bool に両方向の欠陥が出るのは状態モデルが誤っているサインである。

作り直しでは `confirmRevert` が `draft` を直接書き、復元本文とフォーカス要求を同じ更新パスで届かせて遅れ自体を消した。View 側の保留機構は丸ごと不要になり削除した（実装 -146 / +55 行）。理由と棄却案は ADR 0135。

## レビュー経緯

いずれも Codex（別モデル）のヘッドレス独立レビュー。生ログは `docs/agent-output/review-task-1*.json`（run 作業物・破棄前提）。

| 巡 | 判定 | 指摘の要点 | 対応 |
|---|---|---|---|
| 1 | needs_changes | 古い末尾化保留が残る / 遅延実行で本当に足りるのか | 要求値を毎回代入 / 実物 overlay をホストした実測テスト追加 |
| 2 | needs_changes | IME 終了時に保留を再適用する経路が無い / overlay テストが 0.15 秒後まで待っていない | Coordinator に変換状態を持たせて再適用 / 負の対照実験を追加 |
| 3 | needs_changes | 非空の旧下書きに対して末尾化を空振り消費する | 保留を下ろす条件を本文同期時に限定 |
| 4 | needs_changes | 同期不要だった要求の保留が残り続ける / 復元前の編集で保留が落ちる | **ここで設計をやり直す判断**（ADR 0135） |
| 5 | needs_changes | IME 変換中に届いた末尾化要求が一度で消える | 実装を変えず**到達不能をテストで固定**（下記） |

5 巡目の指摘は、末尾化つき要求を出すのが `confirmRevert` だけ＝必ずピッカーを開いた後、という事実から「変換状態がピッカー表示をまたいで生き残る場合」にしか実害にならない。実物の overlay を通して測った結果、ピッカーがフォーカスを奪った時点で変換は終了していた（`compositionDoesNotSurviveThePicker`）。

## 検証スナップショット（2026-07-28・e8c30ae）

- `.claude/verify.sh` **exit 0** — SessionFeature 468 tests / DashboardFeature 1487 tests / AppBootstrap ビルド成功
- `agentic-loop-verify-task.sh task-1 / task-2` — ともに `pass:true`、スコープ違反 0
- **変異検査で新テストの判別力を実測**: `draft = restored` を外すと ViewModel テストが赤／末尾化呼び出しを外すと凍結受け入れテストと overlay テストが赤
- 負の対照 `withoutWiringFocusDoesNotReturnToComposer` が green（＝正のテストが何かを証明している）
- **実機 GUI（Debug 併存起動）**: 下書き "12" が入った状態で esc 2 連打 → 復元を選択 → **クリックせず**「99」を入力 → `AskUserQuestionを使ってリファクタリングの計画を提示して99`。復元本文の末尾に入り、旧下書きの長さ（位置 2）でクランプされていない。稼働中のリリース版（PID 37909）は 2 時間以上無停止のまま

## 未検証・残件

- IME 変換を挟んだ**実機**での操作（ヘッドレスでは `compositionDoesNotSurviveThePicker` で前提を固定したが、実機で日本語変換中に esc 2 連打する操作は未実施）
- グリッド表示での実機確認（ソース走査アサーションと単体テストのみ。複数列同時表示での取り違えは未実測）

## 途中で正した誤り（次 run への注意）

- **「Debug と Release は並走できない」と誤認した**。根拠にしたのは `specs/e2e-test-design.md` の WP-E5 の記述（並走無害は未確認）だったが、`AppFlavor` によるデータディレクトリ・Keychain・ポートの分離は実装済みで、実際に約15分並走させても Release 側は無傷だった。この誤認のため、仮定E（症状が実在するか）の検証を一度ヘッドレスの再現テストだけで済ませかけた。同 spec の該当行を実測結果で更新した。
- **凍結前の実走で受け入れテストのハーネス欠陥を 1 件見つけた**。`focusRequestMovesCaretToEndOfText` の初期キャレットが既に末尾にあり、実装後に無意味に pass する状態だった。凍結は「red-for-the-right-reason を取ってから」でなければ意味がない。
- **overlay 検証ハーネスの text binding が本番と食い違っていた**。`FocusRaceHarnessView` がローカルの `@State` に束ねていたため復元本文が composer へ届かず、既存の overlay テストは「フォーカスが戻るか」しか測れていなかった。実物の View と同じ束ね方（`viewModel.draft`）に直して初めてキャレット位置を overlay 経由で検証できた。

## 書かない判断ログ

- 2026-07-28: `architecture/` に「composer フォーカス要求プロトコル」の項を起こさない → 構造変化が値型 1 つ（`ComposerFocusRequest`）＋ ViewModel の公開プロパティ 1 つ＋ `updateNSView` の 1 分岐に収まり、機構の説明は ADR 0135 に尽きている。同内容を「なぜ抜き」で書き直すと二重管理になり、片方が先に腐る。プロトコルが第 3 の利用者（例: `SubAgentDrawerView`）へ広がったら起こす。

## 運用メモ

- Debug ビルドの併存起動手順は [guides/running-release-and-debug-together.md](../guides/running-release-and-debug-together.md)。稼働中のリリース版を終了させてはならない
- 実機確認中、初回起動の Debug ビルドに TCC 権限ダイアログ（書類フォルダ・メディアライブラリ等 6 件）が出る。検証に不要なため全て「許可しない」で進めた。Debug 版固有の許可でリリース版には影響しない
- 合成クリックで検証する場合、論理座標は `System Events` の `position`/`size` から取ること。スクリーンショットの縮小倍率から逆算すると別アプリへ誤爆する（今回 1 度誤爆した）
