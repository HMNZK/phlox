# 段階8b cards 作業記録

## 追加作業の計画（前段差分を保持）
- 共有ChatDiffClassifierと関連回帰、DestinationとAppRootのsessionDetail連携へ所有を拡張。文脈行の旧番号を保持し、新番号・表示番号の契約を維持する。
- 完了カードは既存SessionNavigationState / SessionAttentionQueueの待ち順と4状態を使用。現在の承認・質問を先に扱い、別セッションへは手動操作時だけ再確認して移動する。取得失敗・候補消失・ポーリング復帰を回帰対象にする。
- SessionDetailViewの間隔・状態表示・無応答帯・過去ボタンと標準ナビ副題を見本ソースで照合する。DSFont+IOSと接続ゲートは変更しない。
- ビルド・テスト・描画は専任へ引継ぎ。こちらはコード確認とdiff検査まで。

## 計画と範囲
- 基点: `0c21a964`、`feature/ios-redesign-cards`。開始時の未コミット差分なし。
- 所有: SessionDetailView / ViewModel、ReplyApproval / Card、UserQuestionCard と専用テスト。
- 比較記録を一次コード・Mac・見本HTML・8a画像で照合し、質問の高さと重なり、承認の幅・ページャ・差分・完了カード、開始帯、短い会話、404の扱いを修正する。
- 共通の色・GlassSurface、入力欄・使用量、会話セル、撮影データは編集しない。Codex説明のワイヤ拡張は行わない。
- 品質設定: ios/Makefile（generate/build/test/lint/snapshot）、ios/project.yml（Swift 6、アプリと描画テスト）、ios/scripts/lint-raw-values.sh。`.github/workflows/` は pages.yml のみ。worktree内にAGENTS.mdなし。ユーザー提示の共通規則と参照karpathy文書を適用。
- 検証: この担当はコード確認と `git diff --check`。ビルド・テスト・シミュレーター描画は専任検証担当が統合後に実走する。XCUITestは実行しない。

## 調査
- 8aのReplyQuestionDT/SE実画像で、カードの無制限な高さと補足文の重なりを確認。見本ReplyQuestionDTでは入力欄と使用量が残っている。
- Mac `ChatReplyApproval.swift` は対象欄だけ高さを制限し、ボタンを外に置く。菱形を使う。
- Mac `UserQuestionCell.swift` は選択印にSF Symbolを使い、自由入力の札と複数選択の自由入力欄を持つ。

## 結果
画面側の修正を未コミット差分として保存。ビルド・テスト・修正後の描画は未実行のため、見た目の解消は未検証。

| 指摘 | 対応・一次コードの根拠 |
|---|---|
| NEW-1/2/3 | 質問と承認の内容を内部スクロールにし、送信・決定ボタンを外に残す。上限はMacと同じ25%・60〜360pt（親画面の高さから算出）。質問の選択肢本文・補足文に縦方向の自然高を要求し、選択印は既存アイコントークンで固定。`UserQuestionCard.swift:42,190`、`ReplyApprovalCard.swift:70`、`SessionDetailView.swift:479`。複数カード同時・キーボード表示中の収まりは未検証。 |
| E1/E8/NEW-5 | 菱形はMac `ChatReplyApproval.swift:358` に存在するため維持。基線を先頭行に揃える。ページ番号を折り返さず、収まる場合は1行、狭い場合は題＋ページャと経過時間の2段。44ptの押下領域は維持。`ReplyApprovalCard.swift:105`。 |
| E2/NEW-9 | ボタンを2行のHStackにし、通常文字サイズではセッション中許可の内容幅を確保。最小高46pt。DTでは既存トークンの26ptを使い、折り返しを許す。内容間隔8pt・説明文subheadline。`ReplyApprovalCard.swift:181,198`。 |
| E3 | 外側12pt、質問内側16pt（既存トークン）へ。面の色・枠はlist担当のため未変更。`SessionDetailView.swift:465,481,500`、`UserQuestionCard.swift:79`。 |
| E4 | 承認専用の単一差分枠、左右の行番号、末尾省略、最小19pt行、ファイルの個別開閉。会話用コピー操作を承認カードから除去。`ReplyApprovalCard.swift:237,297`。**一部残る**: 共有分類器が文脈行の旧行番号をnilにするため、その欄は未確定の「−」。下記の共有側修正が必要。 |
| E5/NEW-11 | 自由入力札、カプセル入力欄・送信ボタン、無効時の淡い背景、13pt系の未回答注記、通常の太さの設問、太字の設問番号・12pt系の補足へ。単一選択SF Symbolと複数選択にも自由入力を出す挙動はMac `UserQuestionCell.swift:313,375,532` に合わせ維持。タップ領域44ptは縮めない。`UserQuestionCard.swift:52,114,163,190`。 |
| E6 | 成功色見出し・区切り線・次の名前/状態・カプセルの次へ。同一セッションで残った質問も数え、クリック後に表示（自動送りをしない）。`ReplyApprovalCard.swift:344`、`ReplyApproval.swift:136`、`SessionDetailViewModel.swift:658,666`。**別セッションへの連携は範囲外で残る**。 |
| E7 | スピナー・折り返す文・カプセルの開始帯。`SessionDetailView.swift:503`。 |
| A3 | 反証・意図的差として維持。`DTOs.swift:76` のApprovalDTOに説明なし、Mac `ChatSessionSupportingTypes.swift:13` のChatApprovalRequestにもreasonなし。Claude側は `ReplyApproval.swift:115` で説明が出る。ワイヤを拡張しない。 |
| NEW-12/13 | 変更なし。待機要約は現コードの明示方針（`SessionDetailViewModel.swift:458`）と比較共通規則の対象外。実行中装飾を末尾の項目だけに付ける規則も維持。 |
| D5（短い会話） | スクロール内容の最小高を表示領域に合わせ、下寄せ。`SessionDetailView.swift:101`。新画像での確認は未実施。ナビゲーション共通部品は変更していない。 |
| C8 | 質問失敗行の余白の二重掛けを除去。共通errorLineを既存の入力エラートークン（通常13pt・DT20pt）に合わせる。`SessionDetailView.swift` の質問失敗行とerrorLine。 |
| 404 | Mac `ControlActionHandler.swift:532` は非構造化/不在をともに404にする。全量メッセージ取得が404のときだけ一覧で存在を照合し、不在ならF8案内・戻るボタン、既存の入力/承認を隠す。会話復帰で解除。`SessionDetailViewModel.swift:1094`、`SessionDetailView.swift:79,247`、見本 `Errors.dc.html:130`。 |

## テストと確認範囲
- 追加: `SessionDetailLoadingWhiteboxTests.swift:58,77`（404削除判定・会話復帰・既存会話保持）、`SessionDetailReplyApprovalTests.swift:178`（送信後に残る質問の名前・状態・件数・手動次へ）。未実行。
- 既存の非構造化404テストは、一覧に対象が存在する入力を明示。空表示のアサーションは維持。承認テストは新たな次の名前も等価比較の対象に追加。削除・skip・アサーション緩和なし。
- `git diff --check` は実行・成功。lint、型チェック、静的解析、ビルド、単体/統合/描画テストは専任検証担当への委譲指定により未実行。XcodeGen生成なし、起動した検証プロセスなし。
- 実画像を開いた範囲: 8a ReplyQuestionDT/SE、ReplyApprovalDiffSE、ReplyStarting、および見本ReplyQuestionDT、ReplyApprovalDiffSE、ReplyStarting、FlowNext。iOS18・ダーク・全盤面の再照合は未実施。比較記録の画像確認実績を自分の実績とは扱わない。

## 前段時点の統合担当への要求（1・2は今回の追加作業で対応）
1. `macos/Packages/AgentDomain/Sources/ChatRenderKit/ChatDiffClassifier.swift:67`: 文脈行にもoldLineNumberを設定する（現状はdeletionだけ）。新旧の起点が異なるハンク・追加削除後の文脈行・不正ハンク・overflowの回帰を維持/追加。承認カードはoldLineNumberを直接読むため共有側で直れば反映される。
2. `ios/App/SessionDetailDestination.swift` と `ios/App/AppRoot.swift`、一覧の待ち行管理: 別セッションの次候補・待ち件数・移動をSessionDetailへ渡す連携が必要。現担当の結果は同一セッション内だけ。別セッションのエラー/無応答を含む「対応待ち」件数をこの局所値で置き換えない。
3. fixtures: A2各項、NEW-4/6/7/8/13は比較記録どおり撮影データ/組立の担当。FlowNextは `configureReplySnapshot(.approvalResult(actionLabel: "許可", remainingCount: 1, nextSessionName: "Tulip", nextIsQuestion: true))` を利用できるよう後方互換の引数を追加した。
4. list: E3/NEW-10のGlassSurface・IOSColor。composer: C2/C5の停止色・使用量。chat: 会話セル・共有DSChatの差。各所有ファイルは未変更。

検証成果物の置き場: `.verification/ios-redesign-stage8b/`。最終報告は取りまとめ側のresult.md自動保存に渡す。使い捨てビルド/ログ/画像は作成していない。コミット・マージ・pushなし。

## 追加作業の結果

前段の未コミット差分を保持し、E4とE6の残件を実装した。上の表と要求1・2の「残る」は前段時点の記録であり、今回の状態は下記。ビルド・テスト・修正後描画の実走は専任検証担当へ引き継ぐ。

| 依頼 | 修正・反証と根拠 |
|---|---|
| 1 / E4 文脈行の旧番号 | `ChatDiffClassifier.swift:67`で文脈行にも旧番号を保持。単列のdisplayLineNumberは従来の新番号のまま。`:132`で壊れたハンクの末尾・範囲を検証し、不正なら両番号を停止。`ReplyApprovalCard.swift:323`の左右欄がこの共有値をそのまま読む。 |
| 1 回帰 | `ChatRenderKitTests.swift:10,119,128`。異なる旧新開始、追加/削除後の文脈、複数ハンク、不正範囲、両側/片側Int.max、次ハンクでの復帰を値で検査。旧番号nilの旧アサーションは依頼された契約変更に合わせ、実際の旧番号のアサーションへ置換した。新番号と単列表示の検査は維持。 |
| 2 / E6 本番連携 | `AppRoot.swift:329`→`SessionDetailDestination.swift:23`→`SessionDetailViewModel.swift:209`へ一覧の直近値と移動コールバックを配線。再取得で初めて見つかったセッションも解決するためAppRoot`:23,321,332`に遷移用保持を追加（sessionDetail連携専用）。接続ゲート/PairConnectFailは変更なし。追加引数は通常/DEBUG両初期化で既定値を持つ。 |
| 2 順番・件数・状態 | VM`:715`はSessionNavigationState経由でSessionAttentionQueueの待ち順を利用。承認・質問・エラー・無応答をセッション単位で数える。現在の承認/質問は1セッションとして先に扱い、送信済みなのに古い一覧が現在セッションを待ち扱いする重複は除く。`ReplyApproval.swift:141`とCard`:356,380`で次の名前と4状態の文言/色を表示。 |
| 2 手動移動・再取得 | VM`:678`の「次へ」で一覧・現在の承認・会話を再取得。現在に残件があればそのカードを開く。候補消失時は最新の候補を使い、0件なら送信済みカードに残る。取得失敗では移動せず再試行文言を出す。会話保持中の取得失敗はloadErrorに出ない既存方針なので、`:104,1162,1204`で空の取得成功と失敗を区別して移動を止める。 |
| 2 ポーリング | VMのrefresh/refreshCurrentStatusが最新の待ち一覧と送信済みカードを更新。送信済みIDの除外と手動送りを維持し、ポーリングから移動コールバックは呼ばない。DEBUG撮影の明示的なFlowNext値はポーリングで上書きしない。 |
| 2 回帰 | `SessionDetailReplyApprovalTests.swift:309,336,357,375,397,418,441,468`に8件追加。4状態の待ち数/順・古い一覧・候補交代/消失・取得失敗と再試行・現在の複数承認の数え方・新着質問優先・既存履歴の取得失敗で移動禁止・撮影値保持。`MockAPI.swift`に一覧取得失敗の設定だけ追加。未実行。 |
| 3 表示 | 見本`Chat.dc.html:27,31,163,185,190,205,737`を根拠に`SessionDetailView.swift:234,275,284,305,691,720,747`を修正。会話カード間隔14、状態見出し20/余白/読み込み印、無応答・中断15、過去ボタン15/最小44/カプセル。状態本文と中心位置の式は一致のため維持。 |
| 3 標準ナビ | 見本`Detail.dc.html:549`の副題上限18を受け、`DSSessionNavigationChrome.swift:46`で副題だけxxxLargeまでに制限。本文のDynamic Type・DSFont+IOS・OS標準ナビ方針は維持。最大18ptとの厳密な一致は未検証。 |

追加で実画像を照合した範囲: ChatStall/Empty/Loading/Unsupported/FetchErr/Longの見本PNGと8a PNG（表示担当が確認）。修正後画像は未撮影。読み込み印の実寸、iOS18/26・SE/DTでの収まり、標準ナビ副題の実寸は未検証。

コードの独立確認で「既存会話があると取得失敗でも次へ進む」問題を検出し、取得成功の区別と回帰検査を追加した。実走による検証ではない。lint・型チェック・静的解析・ビルド・単体/統合/描画テストは今回の分担指定により未実行。使い捨て検証物・起動プロセスなし。fixtures担当の撮影データ変更は未編集。コミット・マージ・pushなし。

最終の独立コード確認で上記の失敗時移動の指摘が解消されたことを確認。`git diff --check`は追加修正後にも実行し成功した。
