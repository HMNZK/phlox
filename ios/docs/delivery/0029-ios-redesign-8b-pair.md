# iOS 再設計 段階8b: pair

## 追加作業の計画（2026-10-18）

- 所有範囲を `App/AppRoot.swift`、`Features/LaunchGate/LaunchGateView.swift`、`Features/Settings/SettingsView.swift` と対応テストへ拡張する。前段の未コミット差分は保持する。
- 接続失敗の本文と固定操作の重なりを高さに追従する配置で解消し、NEW-18/20/21、ゲートのNEW-3/22/23、設定のNEW-11/12/15/16/28/29をコード・HTML・既存PNGで照合する。
- NEW-19は未登録の場合だけ「未設定」へ変更する。保存済み接続先の到達不能表示・認証・再試行・閉じる操作・状態保持は維持する。
- AppShellView、撮影fixture、共通記録0020/0028は編集しない。実走・コミット・マージ・pushなし。コード確認と `git diff --check` のみ行う。

## 計画・所有範囲

- セッション: ios-redesign-pair、基点 0c21a964。Features/Pairing・ConnectionSettings と対応テストを編集する。
- 比較記録 pair-settings.md と common.md、Pair.dc.html、8a/見本PNGを照合する。QR技術値の固定例を実入力の安全な表示へ直し、接続状態・撮影注入・説明用時刻を確認する。
- 初回設定の下部背景、カードの余白・角丸、QR結果カード内の再スキャン、枠と結果時の案内抑制を修正する。
- 共通トークン・Settings・AppRoot/LaunchGate・撮影テストは他担当のため編集しない。0020/0028は変更しない。
- ビルド・テスト・シミュレーター実走は専任検証担当が統合後に実施する。こちらはコード確認と git diff --check。XCUITestは禁止。
- 検証物: `.verification/ios-redesign-stage8b/`。プロセスは起動しない。

## 結果

### 実装した変更（実走前）

変更ファイルは本記録のほか、以下6ファイル。基点からの未コミット差分として残す。

- `ios/Packages/PhloxKit/Sources/Features/Pairing/QRScanScreen.swift`
- `ios/Packages/PhloxKit/Sources/Features/ConnectionSettings/ConnectionSettingsView.swift`
- `ios/Packages/PhloxKit/Sources/Features/ConnectionSettings/ConnectionSettingsViewModel.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/QRScanScreenTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/ConnectionSettingsViewModelTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/ConnectionSettingsViewTests.swift`

以下の行番号はこの作業後のコードを参照する。

| 指摘 | 対応・根拠 |
|---|---|
| 元レビュー QR固定URL/port | 修正。`QRScanScreen.swift:49,96,527` でスキャン入力を技術表示へ渡す。ペアリングURLは実際のv/host/portを採用し、tokenは常に伏せる。未知の項目・name・userinfo・fragmentは表示しない。非ペアリングHTTP(S) URLは秘密値を含みうるパス/クエリも省き、実際のオリジンだけを表示する。解釈できない入力の技術行は省く。パーサーの検証順・受け入れ条件は変更しない |
| 元レビュー 16:42 / UIScreen | 修正。`ConnectionSettingsView.swift` の `macMenuExample` は現在時刻を分単位で表示する。`ConnectionSettingsViewModel.swift:15,61,66` の撮影定数・接続先注入はDEBUG限定。本番の成功文は既存の実測時刻を使う。保存先変更時と旧疎通の遅延完了時には以前の「接続中」や結果を持ち越さない（同:99,118） |
| NEW-1 | 修正。`ConnectionSettingsView.swift` の `setupActions` は操作領域を不透明にし、24ptのグラデーションをその上へ置く |
| NEW-4 | 修正。`QRScanScreen.swift` の `statusSection` / `phaseStatusSection` / `PairingErrorCard` 内に回復操作を配置。再スキャンは高さ52pt、余分な四角い枠を削除 |
| NEW-9 | 修正。QR結果カードの内側20pt、本文subheadline、技術行は既存の等幅footnoteトークン、適用中の輪36pt。技術行の実際の字面はフォント有無に依存し、描画確認は未実施 |
| NEW-10 | 修正。`QRScanScreen.swift` の `scannerFrame` で四隅・外側暗幕を表示し、適用中/成功時は既存の成功色を使う。結果表示時はカメラ不可案内・スキャン案内を隠す。再読込エラー時に前回の成功/失敗カードが併存する経路も抑止。カメラ映像の維持/実機描画は未検証 |
| NEW-11/12 | ConnectionSettings分を修正。外20pt・行内16pt・カード16pt・準備18pt・バナー12pt。Settings分は担当外 |
| NEW-13 | 修正。初回のみ「接続」の小見出しを出さない。設定埋込み時は残す |
| NEW-14 | 修正。説明用Macメニューを右寄せ178pt・Phloxピル・影の構造へ変更。色は既存トークンのみ使用。見本固有のデスクトップ色は新設しない |
| NEW-15 | ConnectionSettings分を修正。バナー上余白を削除し、見出しsubheadline・失敗本文footnote・角丸12pt、実行中は18ptの輪を回転表示。SettingsView側の重複実装は担当外 |
| NEW-18 | ConnectionSettingsの説明文・準備手順・QRカード/カメラ不可本文へ行間を追加。AppRoot側は担当外 |
| NEW-24/25 | 修正。カメラ不可の写真操作前に10pt追加、設定案内をheadline/白/44pt領域、戻る操作は横16pt・上4pt |
| NEW-26 | 修正。準備見出しfootnote準太字、区切りを全幅、下部操作の間6pt・下16pt。初回の上余白はコンパクトな高さで12pt、通常20pt |
| NEW-19 | 判断待ち。「未接続→未設定」はデータ/文言の仕様変更に当たるため維持。共有される `ConnectionSettingsCopy.notConnectedValue` のため設定側との合意が必要 |

P5「64 桁の小文字 16 進ではない」は維持した。PairingPayloadの実装は `PhloxCore/Pairing/PairingPayload.swift` にあり、今回PhloxNetworkingや共有モデルの変更は不要だった。

### 他担当への依頼（編集していない）

- `ios/App/AppRoot.swift`: 既知PairConnectFailDTの本文/固定操作の重なり、NEW-20/21、NEW-18の接続失敗本文。NEW-32はPair盤面とErrorsの文言差で判断待ち。
- `ios/Packages/PhloxKit/Sources/Features/LaunchGate/LaunchGateView.swift`: NEW-3/22/23（再認証ボタン、配置、失敗カード）。
- `ios/App/AppShellView.swift`: NEW-6/30（DTの下部バー、開く操作・高さ）。
- `ios/Packages/PhloxKit/Sources/Features/Settings/SettingsView.swift`: NEW-11/12のSettings分、NEW-15の重複バナー、NEW-16/28/29。
- `ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift`: NEW-2/5/7/8/17/27。特にPairParseErr/P5とSetDiscの状態の撮影データを直す必要がある。今回の新カード構造・DEBUG限定の撮影定数との統合確認も依頼する。
- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Tokens/IOSColor.swift`: NEW-31のiOS26色差は原因未確認。共通GlassSurface/トークンは変更していない。

### 根拠・確認範囲

- 比較記録は自worktreeに無いため、指定元の `../ios-redesign/.verification/ios-redesign-stage8b/compare/common.md` / `pair-settings.md` と `../ios-redesign-review/.verification/ios-redesign-review/review.md` を読んだ。
- HTMLは `ios/docs/specs/ClaudeDesign/Pair.dc.html:51,55,64,78,105,143,210,312`、PairParseErr/PairApplyingの親指定を照合。PNGは見本と8aのPairSEおよびPairParseErr、計4枚を実際に開いた。29盤面の全数比較はしていない。
- 品質設定は `ios/Makefile`、`ios/project.yml`、`ios/scripts/lint-raw-values.sh`、`ios/Packages/PhloxKit/Package.swift` を確認。現worktreeの `.github/workflows` はpages.ymlのみで、iOSのCIゲートは無い。
- `git diff --check`: exit 0。コードと差分を確認した。上記回帰テストは追加/更新のみで、未実走。
- 新規の回帰検査: 実入力の版/ポート・重複値の先勝ち・秘密値除去・不正入力・P5文言、保存先変更後の疎通状態消去・同一接続先での状態維持・旧プローブの遅延完了、入力時刻に応じた成功文。
- ビルド/リンク、lint、型/静的解析、単体テスト、スナップショット、実機カメラは依頼に従い未実施。統合後に専任担当が実施する。完了したのは編集と差分の空白確認までで、描画の一致は未確認。
- コミット/マージ/pushなし。`.env*`変更なし。検証プロセス起動なし。`.verification/ios-redesign-stage8b/ownership.md`は再確認用の記録として保持。AGENTS.mdはworktree内になく、ユーザー提示ルールと `/Users/ryosuke/AGENTS.md` を確認した。参照されたkarpathy-CLAUDE.mdは当該パスに存在せず未読。

## 追加作業の結果（2026-10-18、実走前）

上の「担当外」「NEW-19 判断待ち」は初回作業時点の記録。追加指示により以下を引き取り、編集した。前段のQR/ConnectionSettings差分は保持している。

### 今回の変更ファイル

- `ios/App/AppRoot.swift`
- `ios/Packages/PhloxKit/Sources/Features/LaunchGate/LaunchGateView.swift`
- `ios/Packages/PhloxKit/Sources/Features/Settings/SettingsView.swift`
- `ios/Packages/PhloxKit/Sources/Features/ConnectionSettings/ConnectionSettingsViewModel.swift`（未登録文言のみ追加変更）
- `ios/Packages/PhloxKit/Tests/FeaturesTests/LaunchGateViewTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/ConnectionSettingsViewModelTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/ConnectionSettingsViewTests.swift`
- 本作業記録

### 各指摘の対応と根拠

行番号は追加作業後のコード。修正はいずれもコード上の対応で、修正後の描画一致は未検証。

| 指摘 | 対応・一次コードの根拠 |
|---|---|
| 既知 PairConnectFailDT | 修正。`ios/App/AppRoot.swift:674,730` の本文をScrollView、固定操作をsafeAreaInsetに分離し、操作の実高さを本文から除外する。固定180ptの下余白と本文を透かす操作背景を廃止。再試行/閉じるの既存コールバックと失敗情報は維持 |
| NEW-18/20 | 修正。`AppRoot.swift:674` の見出しを既存title2＋bold、説明を行間3pt、チェック記号を副文字色、カードを16pt角丸へ。操作間6pt・下16pt、注記をDynamic Type対応の12pt書体へ変更 |
| NEW-21 | 修正。`AppRoot.swift:634` の輪を33pt＋4pt線幅（外径37pt）、見出しtitle2＋bold、端末名subheadlineへ。各要素の間隔を別々に指定。接続先・経過秒・20秒後の回復経路は変更しない |
| NEW-3 | 修正。`LaunchGateView.swift:24,79` で認証失敗時だけ「もう一度 Face ID」。成功後のonUnlockedと認証呼出しは維持 |
| NEW-22/23 | 修正。`LaunchGateView.swift:51,64,67,93` の見出し22pt、失敗カード左右24pt、本文との間44pt、通常状態との間32pt、ゲート上40pt、操作間8pt、パスコード領域44pt、注記12pt・下16ptへ。Errors G1準拠の原因を含む本文は維持。錠前の細かな字形は変更しない |
| NEW-11/12 | Settings分を修正。`SettingsView.swift:80,124,149,157,359` のカード16pt角丸、外側左右20pt、カード行内16pt。共有DSSectionLabel自体は変更せず、設定内の小見出しを副文字色・footnote準太字・左4ptへ |
| NEW-15 | Settings分を修正。`SettingsView.swift:249` のバナー上余白を除去、角丸12pt、見出しsubheadline準太字、失敗本文footnote、技術値を既存等幅footnote書体へ。18ptの輪は視差効果を減らす設定で静止。実行中/成功/失敗の分岐は維持 |
| NEW-16/28 | 修正。`SettingsView.swift:182,221,359` の記号だけ標準Dynamic Typeサイズに固定し、30ptの枠を維持。書体は既存headlineを使用し、生の18pt指定は追加しない。トグル行は左右16pt・上下6pt・最小52ptにし、本文は引き続き拡大可能 |
| NEW-29 | iOS分を修正。`SettingsView.swift:395` で既存のApple意味色（systemGroupedBackground/secondarySystemBackground/systemBackground）を明暗を指定して解決し、システム＝明/暗カード、ライト＝明/白、ダーク＝暗カード/黒の二面を表示する。RGB生値・共通トークン変更・グローバルテーマの一時変更は追加しない。macOSホスト用の非UIKit分岐は従来表示を維持 |
| NEW-19 | 修正。`ConnectionSettingsViewModel.swift:10,76` の未登録値を「未設定」へ。保存済みでは必ず実host:portを表示し、到達不能でも「未設定」へ変えない。`SettingsView.swift:308` も未登録を先に判定し、古い到達状態で「接続中」「届きません」としない |

### 確認した根拠と未検証範囲

- HTML: `Pair.dc.html:22,35,163,175,186,210,315,389`（ゲート・接続中・失敗・操作・結果バナー）、`SetUse.dc.html:30,40,45,54,61`（カード・記号・トグル行・小見出し・外観チップ）。比較記録の寸法だけではなくソースを照合した。
- 実際に開いた画像は見本と8a iOS18の `PairConnectFailDT`、`PairGateFail`、`SetDT`、`PairConnecting`、`SetUse` 各2枚、計10枚。画像の全数再確認や修正後の撮影はしていない。見本のSetUseで接続カードが切れる点はソースに2操作があるため追従しない。
- 品質設定は今回も `ios/Makefile`、`ios/project.yml`、`ios/scripts/lint-raw-values.sh`、`ios/Packages/PhloxKit/Package.swift` を確認。現worktreeの `.github/workflows` はpages.ymlのみ。SwiftUIコアのスキル資料、`/Users/ryosuke/.agents/karpathy-CLAUDE.md` も参照した。
- 新規回帰検査は `LaunchGateViewTests.swift:33` の失敗時再認証文言、`ConnectionSettingsViewModelTests.swift:91` の未登録/保存済み表示。既存失敗プローブ検査にも実宛先と保存状態が維持されるassertを追加。文言検査は承認済みNEW-19に合わせて更新し、既存検査の削除/skipはしていない。
- コード確認と `git diff --check` を実施（exit 0）。ビルド/リンク、lint、型/静的解析、単体テスト、スナップショット、シミュレーター/実機は指示に従い未実走。重なり解消・上下位置・外観色の実描画は統合後の専任担当が検証する必要がある。
- 今回の対象に判断待ちはない。既存NEW-32のPair盤面とErrors C1本文の差は、採用済みPair盤面のチェックリスト形式を維持した。文言体系を一本化する場合は別途仕様判断が必要。
- AppShellView・撮影fixture・共通記録0020/0028は無変更。コミット/マージ/push、検証プロセス起動、新規検証用ファイルの作成、`.env*`操作なし。
