# Phlox iPhone アプリ 再設計 — 盤面一式

Design キャンバス（版 241・3 回目の改訂まで）の盤面のソース一式です。

- `project/*.dc.html` … 盤面 248 枚
- `project/canvas.json` … キャンバスの配置・盤面の名前・付箋
- `logos/` … 盤面で使っている実物のロゴの画像

※ 盤面は Design キャンバスの中で表示する形式です。ファイルを単体でブラウザで開いても、そのままの見た目にはなりません。

## 盤面の一覧（キャンバスの並び順）


### 骨格 — 画面マップ・起動と外部遷移・重なり順・機能対応表

- `Main.dc.html` — 骨格 — 画面マップ
- `Launch.dc.html` — 骨格 — 起動の分岐と外部からの遷移
- `Layers.dc.html` — 骨格 — 重なり順
- `Mapping.dc.html` — 骨格 — 機能対応表

### Liquid Glass 採用案（iOS 26）と、採用案の iOS 18 での見え方 — ライト

- `Shell.dc.html` — 一覧 · Liquid Glass 採用案（iOS 26）· タブ 2 つ＋新規チャット
- `Shell18.dc.html` — 一覧 · 採用案の iOS 18 表示（新規チャットは大見出しの右）
- `Detail.dc.html` — セッション画面（会話・承認）
- `Detail18.dc.html` — セッション画面 · 採用案の iOS 18 表示

### ダーク／Dynamic Type 最大／iPhone SE

- `ShellDark.dc.html` — 一覧 · ダーク
- `DetailDark.dc.html` — セッション画面 · ダーク
- `ShellDT.dc.html` — 一覧 · Dynamic Type 最大
- `DetailDT.dc.html` — セッション画面 · Dynamic Type 最大
- `ShellSE.dc.html` — 一覧 · iPhone SE
- `DetailSE.dc.html` — セッション画面 · iPhone SE

### 対応待ちに 1〜2 タップで届く流れ・接続状態・親指の届く範囲

- `FlowUsage.dc.html` — ① 設定タブを見ていても対応待ちに気づく
- `FlowMenu.dc.html` — ② 対応待ちバーの長押しメニュー
- `FlowApprove.dc.html` — ③ セッション画面の入力欄の上で承認する（4 つのボタン）
- `FlowNext.dc.html` — ④ 許可を送った後、次の対応待ちへは自分で進む
- `ShellOffline.dc.html` — 接続状態を対応待ちバーの位置に出す
- `ShellThumb.dc.html` — 親指の届く範囲 · 一覧
- `DetailThumb.dc.html` — 親指の届く範囲 · セッション画面

### セッション一覧 — Mac 版のサイドバーと同じ構成・状態の文字（ライト）

- `List.dc.html` — 一覧 · 数件（通常・未読・実行中の光の帯・子セッション）
- `ListLoading.dc.html` — 一覧 · 読み込み中
- `ListJudging.dc.html` — 一覧 · 接続可否の判定中
- `ListEmpty.dc.html` — 一覧 · 空
- `ListMulti.dc.html` — 一覧 · 対応待ちが複数
- `ListManyTop.dc.html` — 一覧 · 25 セッション（先頭・子セッションあり）
- `ListManyScrolled.dc.html` — 一覧 · 25 セッション（スクロール中・タブは丸に縮む）
- `ListSpec.dc.html` — 一覧 — 構成・機能対応表

### オフライン 3 種・取得エラー

- `ListOffNet.dc.html` — 一覧 · オフライン（圏外）
- `ListOffHost.dc.html` — 一覧 · Mac に到達できない
- `ListOffUnknown.dc.html` — 一覧 · 判定できないまま 20 秒
- `ListError.dc.html` — 一覧 · 取得エラー（500）
- `ListError401.dc.html` — 一覧 · 取得エラー（401）

### 操作の流れ — 引っ張って更新・開閉（プロジェクト・子セッション）・行のタップ

- `ListPull.dc.html` — 一覧 · 引っ張って更新
- `ListCollapsed.dc.html` — プロジェクトと子セッションを閉じた状態（内訳を見出しに・「+3」）
- `ListAllAttention.dc.html` — 全セッションが対応待ち
- `ListPressed.dc.html` — 一覧 · 承認待ちの行をタップ
- `ListTapDetail.dc.html` — 行のタップ後 · セッション画面（承認待ち）

### ダーク／Dynamic Type 最大／iPhone SE

- `ListDark.dc.html` — 一覧 · ダーク
- `ListMultiDark.dc.html` — 一覧 · 対応待ちが複数 · ダーク
- `ListOffHostDark.dc.html` — 一覧 · Mac に到達できない · ダーク
- `ListEmptyDark.dc.html` — 一覧 · 空 · ダーク
- `ListLoadingDark.dc.html` — 一覧 · 読み込み中 · ダーク
- `ListDT.dc.html` — 一覧 · Dynamic Type 最大
- `ListSE.dc.html` — 一覧 · iPhone SE
- `ListSEDark.dc.html` — 一覧 · iPhone SE · ダーク

### セッション詳細（会話）— 状態の描き分け（ライト）

- `Chat.dc.html` — セッション詳細 · 会話
- `ChatLoading.dc.html` — 会話 · 初回読み込み中
- `ChatIdle.dc.html` — 会話 · 待機
- `ChatDone.dc.html` — 会話 · 完了
- `ChatError.dc.html` — 会話 · エラー
- `ChatLong.dc.html` — 会話 · 非常に長い
- `ChatEmpty.dc.html` — 会話 · 本文が空
- `ChatSpec.dc.html` — 会話 — 機能対応表
- `ChatFetchErr.dc.html` — 会話 · 取得に失敗
- `ChatFetchErrDark.dc.html` — 会話 · 取得に失敗（ダーク）
- `ChatUnsupported.dc.html` — 会話 · iPhone では表示できないセッション
- `ChatUnsupportedDark.dc.html` — 会話 · iPhone では表示できないセッション · ダーク
- `ChatStall.dc.html` — 会話 · 無応答
- `ChatThinking.dc.html` — 会話 · 考え中（思考を展開）

### ツールのカードの展開・長押しのメニュー・「…」メニュー・送信失敗

- `ChatExpandCmd.dc.html` — 会話 · ツール実行を展開
- `ChatExpandDiff.dc.html` — 会話 · ファイル変更を展開
- `ChatCopy.dc.html` — 会話 · 長押しのメニュー
- `ChatMenu.dc.html` — 会話 · セッションメニュー
- `ChatRename.dc.html` — 会話 · 名前変更
- `ChatDelete.dc.html` — 会話 · 削除の確認
- `ChatSendFail.dc.html` — 会話 · 送信失敗

### 質問のカード・サブエージェント詳細・ダーク・DT 最大・SE・無応答（ダーク）

- `ChatQuestion.dc.html` — 会話 · 質問カード
- `ChatSub.dc.html` — サブエージェント詳細
- `ChatDark.dc.html` — 会話 · 実行中 · ダーク
- `ChatIdleDark.dc.html` — 会話 · 待機 · ダーク
- `ChatDT.dc.html` — 会話 · Dynamic Type 最大
- `ChatSE.dc.html` — 会話 · iPhone SE
- `ChatSEDark.dc.html` — 会話 · iPhone SE · ダーク
- `ChatStallDark.dc.html` — 会話 · 無応答 · ダーク

### 返答 — 入力欄の状態（2 段・ライト）

- `ReplyEmpty.dc.html` — 入力 · 空
- `ReplyTyping.dc.html` — 入力 · 入力中（キーボード表示中）
- `ReplyAttach.dc.html` — 入力 · 添付あり
- `ReplyAttachErr.dc.html` — 入力 · 添付エラー · 5 枚目を足そうとした（最大 4 枚）
- `ReplyRunEmpty.dc.html` — 入力 · 実行中で空
- `ReplyRunText.dc.html` — 入力 · 実行中で入力あり
- `ReplySending.dc.html` — 入力 · 送信中（画像の準備中も送信ボタンは押せない）
- `ReplyDone.dc.html` — 入力 · 完了後
- `ReplyError.dc.html` — 入力 · エラー後
- `ReplyStarting.dc.html` — 入力 · 起動中
- `ReplySpec.dc.html` — 返答 — 機能対応表

### 承認のカード（4 つのボタン・差分）・Codex・キーボード表示中

- `Reply.dc.html` — 返答（承認・質問・入力）
- `ReplyApprovalFail.dc.html` — 承認 · 送信失敗（赤い 1 行・カードは残る）
- `ReplyCodex.dc.html` — 承認のカード · Codex のセッション（「承認待ち · Shell」・4 つのボタン）
- `ReplyApprovalDiff.dc.html` — 承認待ち · 差分を開いた（Edit · 2 ファイル）
- `ReplyKeyboard.dc.html` — キーボード表示中
- `ReplyKeyboardAppr.dc.html` — 承認待ちでキーボード表示中（カードを 1 行に畳む）

### 質問・回答画面の統合・モデル選択・添付エラー（サイズ・合計・寸法・読み込み）

- `ReplyQuestion.dc.html` — 質問のカード · 2 問（見出し「質問待ち · DEPLOY ほか 1 問」）
- `ReplyQuestionFail.dc.html` — 質問 · 回答の送信失敗（赤い 1 行）
- `ReplyQuestionPlain.dc.html` — 質問のカード · 選択肢なし
- `ReplyModel.dc.html` — モデルのシート · セッション画面（そのエージェントだけ）
- `ReplyAttachErrSize.dc.html` — 入力 · 添付エラー · 1 枚 20MB を超えた
- `ReplyAttachErrTotal.dc.html` — 入力 · 添付エラー · 合計 80MB を超えた
- `ReplyAttachErrDim.dc.html` — 入力 · 添付エラー · 各辺 8000 ピクセルを超えた
- `ReplyAttachErrLoad.dc.html` — 入力 · 添付エラー · 画像を読み込めない

### ダーク／Dynamic Type 最大／iPhone SE

- `ReplyApprovalDark.dc.html` — 承認待ち · ダーク
- `ReplyQuestionDark.dc.html` — 質問のカード · ダーク
- `ReplyAttachDark.dc.html` — 添付あり · ダーク
- `ReplyDT.dc.html` — 承認待ち · Dynamic Type 最大（ボタンは 1 列）
- `ReplySE.dc.html` — 承認待ち · iPhone SE
- `ReplySEDark.dc.html` — 入力中（キーボード表示中） · iPhone SE · ダーク
- `ReplyAttachErrDimDark.dc.html` — 入力 · 添付エラー · 各辺 8000 ピクセルを超えた · ダーク
- `ReplyAttachErrDimSE.dc.html` — 入力 · 添付エラー · 各辺 8000 ピクセルを超えた · iPhone SE

### 入力欄 — 思考の強さ・権限・権限の失敗・Haiku・iPhone SE の「…」（2 回目の修正 3/6）

- `ReplyEffort.dc.html` — 入力欄 · 思考の強さのメニュー
- `ReplyPerm.dc.html` — 入力欄 · 権限のメニュー
- `ReplyPermFail.dc.html` — 入力欄 · 権限を変更できなかった
- `ReplyHaiku.dc.html` — 入力欄 · Haiku（思考の強さのチップを出さない）
- `ReplyMore.dc.html` — 入力欄 · iPhone SE の「…」メニュー（思考の強さと権限）

### 新規チャット — 入口・見出し・提案チップ・メニュー・モデルのシート・作成の流れ（ライト）

- `Draft.dc.html` — 新規チャット · 下部の「新規チャット」から（前回使ったプロジェクト Phlox が選ばれている）
- `DraftFromProject.dc.html` — 新規チャット · 一覧の「SimpleBudget」の「＋」から（そのプロジェクトで始まる）
- `DraftEntryEmpty.dc.html` — 新規チャット · プロジェクト未選択で送った
- `DraftSuggest.dc.html` — 新規チャット · 提案チップ「コードレビュー」を押した
- `DraftEffort.dc.html` — 新規チャット · 思考の強さのメニュー
- `DraftPerm.dc.html` — 新規チャット · 権限のメニュー
- `DraftFailed.dc.html` — 新規チャット · 作成に失敗（本文を入力欄に戻し、キーボードを出したまま）
- `DraftSpec.dc.html` — 新規チャット — 機能対応表
- `DraftModel.dc.html` — 新規チャット · モデルのシート（3 エージェントの全モデル）
- `DraftModelNa.dc.html` — 新規チャット · モデルのシート（Cursor を取得できない）
- `DraftCreating.dc.html` — 新規チャット · 作成 → 準備待ち → 送信
- `DraftCreated.dc.html` — 新規チャット · 作成後、そのセッション画面へ

### ダーク／Dynamic Type 最大／iPhone SE

- `DraftDark.dc.html` — 新規チャット · ダーク
- `DraftModelDark.dc.html` — 新規チャット · モデルのシート · ダーク
- `DraftCreatingDark.dc.html` — 新規チャット · 作成中 · ダーク
- `DraftDT.dc.html` — 新規チャット · Dynamic Type 最大
- `DraftSE.dc.html` — 新規チャット · iPhone SE（思考の強さと権限は「…」）
- `DraftSEDark.dc.html` — 新規チャット · iPhone SE · ダーク

### 3 回目で足した盤面 — 新規チャットのプロジェクトの選択・「…」・強い権限の赤いチップ・Codex／Cursor の権限のメニュー

- `DraftProject.dc.html` — 新規チャット · プロジェクトのチップを押した（前回使った Phlox に ✓）
- `DraftProjectDark.dc.html` — 新規チャット · プロジェクトの選択 · ダーク
- `DraftProjectSE.dc.html` — 新規チャット · プロジェクトの選択 · iPhone SE
- `DraftMoreSE.dc.html` — 新規チャット · 「…」（思考の強さと権限）を開いた · iPhone SE
- `DraftMoreDT.dc.html` — 新規チャット · 「…」を開いた · Dynamic Type 最大
- `DraftPermDanger.dc.html` — 新規チャット · Bypass Permissions を選んだ後（赤いチップ）
- `DraftPermDangerCodex.dc.html` — 新規チャット · Full Access を選んだ後（Codex・赤いチップ）
- `DraftPermCodex.dc.html` — 新規チャット · 権限のメニュー · Codex
- `DraftPermCursor.dc.html` — 新規チャット · 権限のメニュー · Cursor
- `ReplyPermDanger.dc.html` — セッション画面 · Bypass Permissions を選んだ後（赤いチップ）

### 3 回目で足した盤面 — ダークの版（承認・会話の状態・サブエージェント）

- `ReplyApprovalDiffDark.dc.html` — 承認待ち · 差分を開いた · ダーク
- `ReplyApprovalFailDark.dc.html` — 承認 · 送信失敗 · ダーク
- `ReplyKeyboardApprDark.dc.html` — 承認待ちでキーボード表示中 · ダーク
- `ChatExpandDiffDark.dc.html` — 会話 · ファイル変更を展開 · ダーク
- `ChatExpandCmdDark.dc.html` — 会話 · ツール実行を展開 · ダーク
- `ChatCopyDark.dc.html` — 会話 · 長押しのメニュー · ダーク
- `ChatErrorDark.dc.html` — 会話 · エラー · ダーク
- `ChatSendFailDark.dc.html` — 会話 · 送信失敗 · ダーク
- `ChatQuestionDark.dc.html` — 会話 · 質問カード · ダーク
- `ChatThinkingDark.dc.html` — 会話 · 考え中（思考を展開） · ダーク
- `ChatSubDark.dc.html` — サブエージェント詳細 · ダーク

### 3 回目で足した盤面 — iPhone SE と Dynamic Type 最大の版（差分つきの承認・質問・無応答・ツール実行）

- `ReplyApprovalDiffSE.dc.html` — 承認待ち · 差分を開いた · iPhone SE
- `ReplyQuestionSE.dc.html` — 質問のカード · iPhone SE
- `ReplyApprovalSEDark.dc.html` — 承認待ち · iPhone SE · ダーク
- `ReplyApprovalDiffDT.dc.html` — 承認待ち · 差分を開いた · Dynamic Type 最大
- `ReplyQuestionDT.dc.html` — 質問のカード · Dynamic Type 最大
- `ChatStallDT.dc.html` — 会話 · 無応答 · Dynamic Type 最大
- `ChatExpandCmdDT.dc.html` — 会話 · ツール実行を展開 · Dynamic Type 最大

### 3 回目で足した盤面 — 思考の強さと権限のメニュー（ダーク・iPhone SE・Dynamic Type 最大）

- `ReplyEffortDark.dc.html` — 入力欄 · 思考の強さのメニュー · ダーク
- `ReplyEffortSE.dc.html` — 入力欄 · 思考の強さのメニュー · iPhone SE（「…」から）
- `ReplyEffortDT.dc.html` — 入力欄 · 思考の強さのメニュー · Dynamic Type 最大（「…」から）
- `ReplyPermDark.dc.html` — 入力欄 · 権限のメニュー · ダーク
- `ReplyPermSE.dc.html` — 入力欄 · 権限のメニュー · iPhone SE（「…」から）
- `ReplyPermDT.dc.html` — 入力欄 · 権限のメニュー · Dynamic Type 最大（「…」から）

### セッションへの操作と確認ダイアログ — 全ダイアログのカタログ（ライト／ダーク）・流れと機能対応表

- `Dialogs.dc.html` — 操作と確認ダイアログ — カタログ
- `DialogsDark.dc.html` — 操作と確認ダイアログ — カタログ · ダーク
- `DialogsSpec.dc.html` — 操作と確認ダイアログ — 流れと機能対応表

### アプリに入るまでと Mac とつながるまで — 初回起動（接続未設定）とエラー

- `Pair.dc.html` — 起動と接続
- `PairScan.dc.html` — 接続 · QR スキャン（初回）
- `PairNoCam.dc.html` — 接続 · カメラを使えない
- `PairApplying.dc.html` — 接続 · 読み取って適用中
- `PairConnecting.dc.html` — 接続 · 接続中（全画面）
- `PairConnectFail.dc.html` — 接続 · 20 秒で読めない（原因・再試行・閉じる）
- `PairParseErr.dc.html` — QR · 読み取りエラー（接続先が無い）
- `PairUnreach.dc.html` — QR · 読めたが Mac に届かない
- `PairSpec.dc.html` — 起動と接続 — 流れ・案内・機能対応表

### 起動ゲート・設定からの再ペアリング・疎通テスト

- `PairGate.dc.html` — 起動ゲート · ロック中
- `PairGateAuth.dc.html` — 起動ゲート · 認証中
- `PairGateFail.dc.html` — 起動ゲート · 認証できなかった
- `PairSettings.dc.html` — 設定 · 接続（現在の接続先）
- `PairTesting.dc.html` — 設定 · 疎通テスト中
- `PairTestOk.dc.html` — 設定 · 疎通テスト成功
- `PairTestFail.dc.html` — 設定 · 疎通テスト失敗
- `PairRescan.dc.html` — 設定 → QR で再接続
- `PairRescanDone.dc.html` — 設定 → 再接続できた（画面に留まる）

### ダーク／Dynamic Type 最大／iPhone SE

- `PairDark.dc.html` — 接続設定（初回）· ダーク
- `PairGateDark.dc.html` — 起動ゲート · 認証できなかった · ダーク
- `PairParseErrDark.dc.html` — QR · 読み取りエラー（形式に未対応）· ダーク
- `PairConnectFailDark.dc.html` — 接続 · 20 秒で読めない · ダーク
- `PairTestFailDark.dc.html` — 設定 · 疎通テスト失敗 · ダーク
- `PairDT.dc.html` — 接続設定（初回）· Dynamic Type 最大
- `PairConnectFailDT.dc.html` — 接続 · 20 秒で読めない · Dynamic Type 最大
- `PairSE.dc.html` — 接続設定（初回）· iPhone SE
- `PairSEDark.dc.html` — 接続設定（初回）· iPhone SE · ダーク
- `PairScanSE.dc.html` — QR スキャン · iPhone SE

### エラー文言 — 16.5 節の 8 種・到達不可 3 種・QR 5 種・その他を「何が起きたか＋次にどうするか」に

- `Errors.dc.html` — エラー文言 — カタログ
- `ErrorsDark.dc.html` — エラー文言 — カタログ · ダーク

### 設定 — 接続済み／未接続（ライト・ダーク・DT 最大・SE）

- `SetUse.dc.html` — 設定 · 接続済み
- `SetDisc.dc.html` — 設定 · 未接続
- `SetDark.dc.html` — 設定 · 接続済み · ダーク（外観: ダークを選択）
- `SetDiscDark.dc.html` — 設定 · 未接続 · ダーク
- `SetDT.dc.html` — 設定 · Dynamic Type 最大
- `SetSE.dc.html` — 設定 · iPhone SE（Touch ID）
- `SetSEDark.dc.html` — 設定 · iPhone SE · ダーク
- `SetUseSpec.dc.html` — 設定と使用量 — 論点・機能対応表

### 使用量 — 入力欄の下の 1 行（ライト）: 通常・残りわずか・取得できない・古い値・押して詳細・取り直しの間・キーボード表示中

- `UsageNormal.dc.html` — 使用量 · 通常
- `UsageLow.dc.html` — 使用量 · 残りわずか（20% 未満）
- `UsageNa.dc.html` — 使用量 · 取得できない・値が届かない枠
- `UsageStale.dc.html` — 使用量 · 古い値（取り直しに失敗）
- `UsagePop.dc.html` — 使用量 · 押して詳細（吹き出し）
- `UsageRefresh.dc.html` — 使用量 · 取り直しの間（表示を消さない）
- `UsageKeyboard.dc.html` — 使用量 · キーボード表示中（新規チャット）

### 使用量 — ダーク

- `UsageNormalDark.dc.html` — 使用量 · 通常 · ダーク
- `UsageLowDark.dc.html` — 使用量 · 残りわずか（20% 未満） · ダーク
- `UsageNaDark.dc.html` — 使用量 · 取得できない・値が届かない枠 · ダーク
- `UsageStaleDark.dc.html` — 使用量 · 古い値（取り直しに失敗） · ダーク
- `UsagePopDark.dc.html` — 使用量 · 押して詳細（吹き出し） · ダーク

### 使用量 — iPhone SE

- `UsageNormalSE.dc.html` — 使用量 · 通常 · iPhone SE
- `UsageLowSE.dc.html` — 使用量 · 残りわずか（20% 未満） · iPhone SE
- `UsageNaSE.dc.html` — 使用量 · 取得できない・値が届かない枠 · iPhone SE
- `UsageStaleSE.dc.html` — 使用量 · 古い値（取り直しに失敗） · iPhone SE
- `UsagePopSE.dc.html` — 使用量 · 押して詳細（吹き出し） · iPhone SE

### 使用量 — Dynamic Type 最大（2 行に折り返す）

- `UsageNormalDT.dc.html` — 使用量 · 通常 · Dynamic Type 最大
- `UsageLowDT.dc.html` — 使用量 · 残りわずか（20% 未満） · Dynamic Type 最大
- `UsageNaDT.dc.html` — 使用量 · 取得できない・値が届かない枠 · Dynamic Type 最大
- `UsageStaleDT.dc.html` — 使用量 · 古い値（取り直しに失敗） · Dynamic Type 最大
- `UsagePopDT.dc.html` — 使用量 · 押して詳細（吹き出し） · Dynamic Type 最大

### アプリ外の表示 — ロック画面・通知・ホーム画面・Dynamic Island（ライト／ダークの壁紙）

- `Glance.dc.html` — アプリ外の表示 · 画面の中で
- `GlanceLockDark.dc.html` — ロック画面 · 質問あり · ダークの壁紙
- `GlanceNotifs.dc.html` — プッシュ通知 · ロック画面 · ライトの壁紙
- `GlanceNotifsDark.dc.html` — プッシュ通知 · ロック画面 · ダークの壁紙
- `GlanceHome.dc.html` — ホーム画面 · small · 完了 · ライトの壁紙
- `GlanceHomeDark.dc.html` — ホーム画面 · small · エラー · ダークの壁紙
- `GlanceHomeEmpty.dc.html` — ホーム画面 · small · セッションが無い
- `GlanceIsland.dc.html` — Dynamic Island · compact · 承認待ち（ライト）
- `GlanceIslandExp.dc.html` — Dynamic Island · expanded · 承認待ち（ダーク）
- `GlanceSpec.dc.html` — アプリ外の表示 — 通知・遷移・配色・機能対応表

### 状態カタログ — 実行中・承認待ち・質問あり・完了・エラー・無応答・終了・セッションが無い

- `GlanceCatalog.dc.html` — アプリ外の表示 — 状態カタログ
- `GlanceCatalogDark.dc.html` — アプリ外の表示 — 状態カタログ · ダーク

### デザインシステム — 色・文字・余白・角丸・影・動き・アイコン・状態表示・共通部品・Liquid Glass（ライト／ダーク）

- `DS.dc.html` — Phlox デザインシステム
- `DSDark.dc.html` — Phlox デザインシステム · ダーク

### レビュー — 機能一覧との突き合わせ（1 置き場所／2 18.1 節の守り方／3 食い違いと直した版／4 21.2 節の解消）

- `ReviewMap.dc.html` — レビュー 1 — 機能の置き場所
- `Review181.dc.html` — レビュー 2 — 18.1 節「守る」の守り方
- `ReviewDiff.dc.html` — レビュー 3 — 画面間の食い違いと直した版
- `Review212.dc.html` — レビュー 4 — 21.2 節の解消状況

### 改訂 2026-10-17 — 1 回目（色・ロゴ・状態の文言・使用量・画像添付・新規セッション）と 2 回目（Liquid Glass・端末・状態の記号・一覧・下部のナビゲーション・新規チャット・入力欄・モデル選択・思考の強さと権限・セッション画面・使用量）

- `Revision20261017.dc.html` — 改訂 2026-10-17
