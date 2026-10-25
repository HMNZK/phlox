---
status: active
last-verified: 2026-10-25
---

# Mac と iOS の表示・操作の統一

[承認仕様](../specs/session-activity-parity.md) に基づく実装記録。専用worktree `mobile-desktop-parity-20261025` で実装。元の作業場所の未コミット変更には触れていない。

この文書は実行時の結果を保存する。下記のログ名・画像名は検査の識別用であり、セッション後片付けでは使用済みの生ログ・画像・専用ビルドを削除対象とする。検査失敗と未検証範囲は本文に残し、成果はGitへ保存してから作業用worktreeを整理する。

## 分担と契約

| 担当範囲 | 入力・出力と不変条件 |
|---|---|
| 状態表示 | 共有 `SessionDisplayState` → 共有 `SessionActivityIndicator`。一覧と会話ヘッダー。未読の強調・状態語・読み上げを維持 |
| 使用量 | 共有表示形式を使い棒を既定、数値切替保存。前面・online・認証済みだけ60秒取得。キャンセル後の再取得なし、期限切れ値を残さない |
| 新規チャット | 登録プロジェクトから起点・履歴を解決して既存のControl起動経路へ渡す。認可・親子・起動制限を維持。再開時send0回 |
| 完了確認 | 実行IDと正常完了連番のtokenを確認要求に含め、runtime適用時まで一致確認。前面閲覧中だけ送信し失敗を隠さない |
| 履歴展開 | 引く→離すで1回展開、戻すと取消。Mac共通リング、展開前のメッセージIDアンカー維持 |

使用量・新規チャット・状態表示は独立に実装し、APIファイルの共有追記は局所パッチで調整する。完了確認と新規起動のAPI検証後に統合検証へ進む。最大並列幅は4、依存の長さは「仕様→実装/受入テスト→統合検証→独立レビュー」の4段。

## 検証方針

- 受入テストは製品実装者と別担当が作成。既存の期待値を現出力へ合わせる変更やスキップは行わない。
- iOS標準のパッケージテスト・raw値lint、変更対象Macパッケージの標準テスト入口、両アプリのビルド／リンクを実行する。
- XCUITestを使わず、専用シミュレーター上のホスト付き単体描画テストで画面を確認する。
- 出力はこのworktreeの `.verification/mobile-parity-20261025/` に保存。既存アプリ・他作業のシミュレーターは停止しない。

## 実装内容

- 一覧と会話ヘッダーでMac共通の実行中・未確認完了表示を使用。会話末尾は既存の共有表示を維持。
- 上端を引いて離すと履歴を1段階展開。引き戻し・履歴なしでは展開せず、表示済み本文の先頭IDをアンカーにする。既存の読み上げ用ボタンも維持。
- 完了確認APIを追加。前面で本文を取得できた会話だけ確認し、要求時とruntime適用時の両方で完了tokenを照合する。通信失敗は表示・再試行対象とする。
- 使用量は共通の横棒と数値切替、設定保存、前面接続中の60秒更新、期限切れ枠の除外に対応。詳細を読み上げ操作でも開けるようにした。
- 新規チャットに作業場所・worktree起点・Claude/Codex履歴再開を追加。Macの既存起動処理・認可・制限を再利用。履歴再開で初回sendを行わない。
- 両側のAPI契約、再設計仕様の競合箇所、描画fixtureと受入テストを更新。

## 独立レビュー

作業全体を1回レビューし、指摘された4件を修正した。履歴アンカーから保留中質問を除外、コピー選択モード中も会話閲覧と判定、削除確認など別画面の背後では完了確認しない、起動直前にもプロジェクト登録を再確認する。後者2件は修正後の限定再レビューでも確認。

## 検証記録（2026-10-25）

以下は手元での実行結果。ログは `.verification/mobile-parity-20261025/` に保存し、受入テスト自体は各パッケージの `Tests/` に追加した。

| 対象 | 実行結果・範囲 |
|---|---|
| iOSパッケージ | 最終変更後も686テスト・115 suite成功、exit 0（`ios-package-final.log`、11.481秒） |
| Mac標準パッケージ検査 | AgentDomain 577、DesignSystem 205、AppBootstrap 209テスト成功。全体はexit 1（`mac-packages.log`） |
| Mac限定再検査 | ControlServer 6、SessionFeature 1、DashboardFeature 20テスト成功（`mac-regression.log`）。起動認可・完了token競合・使用量描画・エディター削除時undoを含む |
| iOS lint | `ios/scripts/lint-raw-values.sh` 成功 |
| 差分検査 | `git diff --check` 成功 |
| Macアプリ | Debugのコンパイル・リンク・既定のad-hoc署名成功、exit 0（`mac-app-build.log`）。アプリは起動していない |
| iOSアプリ | 専用シミュレーター向けのコンパイル・リンク成功。ホスト付き単体テストを実行したが、描画suite全体は下記の外部操作待ちで失敗 |

Mac全体の失敗は隠さず保持した。SessionFeatureの既存 `ComposerSettingPopoverTests.clickingOutsideClosesNativePopover` が2条件で失敗し、変更前の元リポジトリでも同じ失敗を再現した（元リポジトリ `.verification/mobile-parity-baseline-20261025/result.log`）。DashboardFeatureは素材準備中のテストソース変更により素材8件と、全数実行時の `undoRoutingAfterRemoval` が失敗した。素材を標準入口で再準備した限定再検査は成功したが、Macの全数検査が成功したとは扱わない。既知のGitHistoryテスト1件は既存の `withKnownIssue` として報告された。起動テストfixtureのbackend省略による失敗はfixtureで明示して再検査し、製品側の拒否条件や期待値は変更していない。

描画検査では、最初のメソッド指定が0件実行だったため検証に数えていない。以後はsuite指定を使用。新規チャットの実際のボタンから起点・履歴シートを開き、通常・ダーク・AX5の画像を確認した。使用量詳細はテスト内のAX取得で実際のポップオーバー内部を読めなかったため、既存の外部操作runnerを使用した。`usage-external-v1` では通常・AX5の実操作と読み上げ項目を確認したが、小画面ステップで応答期限を超過しexit 65。期限延長や自動ACKは行っていない。最終再検査は下に記載する。

既存の非推奨API・不要なtry等のコンパイル警告、描画テストのUIKit appearance不整合・launch metric警告はログに保存。テストfixtureの意図的な不正復元入力に対するエラー出力も保持した。

Macアプリビルドでは既存のTerminalUIのSendable警告、PTYKitの非推奨String初期化、AppIntents未依存によるメタデータ抽出省略の警告があった。iOS最終パッケージ再検査にはコンパイル警告・エラーの出力なし。

最終描画再検査（`render-external-final.log`）は14テスト中、外部操作待ちの描画テスト1件が失敗、残り13件は成功。193枚のPNGを保存した。使用量詳細ステップでCUAが別の端末 `Phlox IME Placeholder 20261025` のウィンドウを返し、対象ウィンドウを選ぶ操作も `The element ID is no longer valid`、スクリーンショットも `Screenshot unavailable` となった。対象不一致のAXを証拠に流用せず、ACKなしの期限切れを失敗として記録した。小画面・ダークの使用量詳細の外部AX検査と、描画suite全体の成功確認は未完了。通常・AX5での先行確認結果は `usage-external-v1` にnonce・PID・UDID・生AXとともに保存している。

## 未検証・配布条件

- 実機iPhone、実際のCLI履歴を使った端末間連携、音声出力を伴うVoiceOver、実指での履歴pullは未検証。状態方針とAPIは単体・連携テスト、画面は専用シミュレーターで確認する。
- 新APIを利用する履歴再開・起点選択・完了確認は、今回のMac側更新も必要。古いMacは完了tokenを返さないため、iOSから完了確認要求を送らない。
- mainへの統合・push・リリースは行っていない。

## 後片付け

専用端末 `Phlox Mobile Parity Verification 20261025` / `B1833276-13CA-4E41-8702-97817F5C56FC` の一致を確認し、具体的なUDIDでshutdown、deleteをそれぞれ単独実行して成功。端末一覧から消えたことを確認した。他の端末・既存アプリは終了していない。ログ・画像・外部AX証跡は再確認用に保持し、ビルド出力は共通managed-buildの保持規則に従う。

## 再開検証

2026-10-25の再開指示に基づき、残る画面検査とMac全数検査を続行する。新しい専用端末 `Phlox Mobile Parity Resume 20261025` / `89338701-7E5C-462C-98EB-52398F8103DB` を作成し、CUAの対象ウィンドウ一致を確認した。描画は条件を緩めず、同じ外部操作runnerで新規の `render-resume-v1` へ保存する。

Macの外側クリック失敗は、新旧とも共通のSwiftUI標準popoverを使うため、独自dismiss処理の追加を先に行わない。テストが時刻0のmouseDownのみを直接配送している点を、既存のネイティブ入力配送方法と比較して調査する。時刻・currentEvent・activationのどれが原因かは実測前のため未確定。可視性の期待値は維持し、製品側とテスト側の原因を切り分けてから修正する。

時刻だけの変更では2条件とも失敗した（`mac-popover-clock.log`）。診断では、クリック位置は実popoverの外にありイベントのwindowも一致したが、アプリはinactive、activationPolicyはprohibited、key windowはnil、currentEventも送ったイベントではなかった（`mac-popover-diagnostic.log`）。外側クリック検査では対象テストプロセスを一時的に入力可能な状態にし、前面・key windowを実測してから当該PIDへdown/upを配送する。終了後はactivation状態・policyを復元する。製品へdismiss用処理は追加せず、閉じたことの期待値を維持する。

使用量の通常・AX5・小画面・ダークの4ステップは、今回は実操作とfresh AXで確認できた。後続の `UsageStaleDTSE` で空入力欄高さ48.333ptに対しプレースホルダー自然高95.667ptとなり、既存assertが失敗したため、描画suite全体はまだexit65。このassertと入力欄実装は今回変更していない。このシーンでは使用量取得失敗時の行自体は非表示である。変更前の6eb5e9f1を隔離したworktreeで同じシーンを実走し、今回の変更との関係を切り分ける。

Mac側の試行では、最初のactivation設定が `NSApplication.shared` 初期化より先だったためnil参照でテストプロセスが終了した（`mac-popover-native.log`）。初期化後、さらに既存の `finishLaunching()` 手順も試したが、active条件を満たさず、次条件でSwiftUIのフォーカス解除中に `NSInternalInconsistencyException` が発生した（`mac-popover-native-ready.log`、`mac-popover-launched.log`）。各試行は失敗として保存した。試行パッチは採用せず、このテストファイルは変更前と差分なしに戻した。製品の外側クリック処理や可視性assertは変更していない。Macの別機能の検査ハーネス修正まで今回に含めるかは、再開後の確認事項として提示した。

変更前6eb5e9f1の隔離worktreeでも `UsageStaleDTSE` の同じassert失敗を再現した。13テスト・1 suite・1 issue、exit65。入力欄48.333pt、プレースホルダー95.667ptで今回と一致した。入力欄の問題を今回の変更に起因するものとは扱わず、既存の問題として分離する。ログと画像は `baseline-composer-record/` に保存する。

`render-resume-v1` の使用量4ステップでは、対象端末一致を確認してCUAで操作し、nonce・PID・UDID・windowTitle・取得時刻・full AXを保存した。小画面・ダークの画像も直接確認。前回の「小画面・ダークの詳細は未確認」は解消したが、既存入力欄の失敗があるため描画suite全体の成功とは扱わない。

スクロール追従の追加実走（`scroll-runtime-resume.log`）は79pt/81ptの2条件とも、動作assertより前のzero-inset前提で失敗した（exit65）。上余白62pt、下余白34pt、native表示領域874ptに対しrootGeometryは778pt、contentLayoutFrameはゼロ。変更前6eb5e9f1でも同じ前提・数値で失敗を再現した（`baseline-composer-record/scroll-runtime.log`）。この追加検査は追従動作の確認済み件数に数えず、検査ハーネスの座標対応が未成立として残す。前提や期待値を弱める変更は行っていない。

比較用detached worktreeはソースcleanと関連プロセス終了を確認し、ログ・画像・寸法記録を `baseline-composer-record/` へ確保後、通常の `git worktree remove` で削除した。再開用端末も名前・UDIDを確認し、shutdownとdeleteを具体的UDIDで個別実行して成功した。

### Mac標準入口の再検査結果

`mac-packages-resume.log` に記録。追加の除外指定や期待値変更は行わず、標準入口を最後まで実行した。全体exit1、失敗したパッケージはSessionFeatureのみ。

| パッケージ | 再検査結果 |
|---|---|
| AgentDomain | 577テスト成功 |
| DesignSystem | 205テスト成功 |
| ControlServer | 175テスト成功 |
| SessionFeature | 1297テスト、既存の外側クリックの新旧2条件が失敗。他の失敗は観測なし |
| DashboardFeature | 本体exit0、実Gitの別パス41テスト成功。素材8条件の失敗は再現せず、`undoRoutingAfterRemoval` もpassを観測 |
| AppBootstrap | 209テスト成功 |

Dashboard本体は標準要約が末尾のXCTest結果（6件、1 skip、0 failures）を採用したため、Swift Testingの総件数が最終ログに残らなかった。件数を推定して加算しない。実行中のログではSwift側14 skipと既存のGitHistoryWorkflowのknown issue1件を観測した。スキップやknown issueを成功件数へ読み替えない。Mac全体成功とは報告しない。

スキップ条件をソースでも照合した。`PHLOX_E2E=1` が必要なSwiftテスト14件と任意性能測定3テストがあり、これらの有効化条件は今回は未設定。「14 skip」は途中ログの観測数なので、最終スキップ総数とは断定しない。XCTestの1 skipは `MarkdownScrollPerformanceTests.testScrollFrames` で、`PHLOX_SCROLL_PERFORMANCE=1` かつRelease向けの任意測定。これらはGit3suiteを別パスで実走する仕組みとは別であり、E2E・任意性能測定を今回実行済みと扱わない。今回追加したスキップはない。

今回の実装項目（状態表示・完了確認・上端履歴・使用量・作業場所/起点・履歴再開）は実装済み。再開後に製品コードの追加変更はなく、未確認だった使用量詳細の小画面・ダークを確認できた。残るMac既存popover、既存iOS入力欄、スクロール計測前提の失敗を分離して記録した。実機連携・実指のpullは引き続き未検証で、main統合・配布は未実施。

## dev統合の準備

ユーザーのdev統合指示後、成果を4e00df58へコミットした。共通マージツールはdevのスキル候補・写真取り込み修正との4ファイルの競合を検出し、devを更新せず停止した。作業ブランチ内の履歴整理として最新devへ載せ直し、APIのスキル取得と本件の完了確認/起点/履歴の既定実装、両方のGETルート、写真取り込みの描画テストと使用量のAXテストを残す。AX待機ヘルパーはidentifier・label・hintを併用できる形へ統合し、スキル候補テストからの呼び出しも維持する。devの更新は引き続き共通マージツールだけで行う。

競合整理後、iOSパッケージ694テスト・117 suite成功、iOSのホスト付きテストを含むビルド成功、MacのControlServer 178テストとAppBootstrap 213テスト成功、MacアプリDebugのビルド・リンク成功。関連ログは `ios-after-dev.log`、`ios-after-dev-build.log`、`mac-api-after-dev.log`、`mac-after-dev-build.log`。独立した静的レビューでも両側の機能の取り落としは検出されなかった。これらは統合準備の確認であり、共通マージツールの候補に対する必須検査の代替にはしない。
