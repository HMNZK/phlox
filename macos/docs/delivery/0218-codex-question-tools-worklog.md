---
status: active
last-verified: 2026-10-23
---

# Codexの質問ツール必須化の検証記録

仕様は [Codexの質問ツール必須化](../specs/codex-question-tools.md)。変更は `dev` の `e36b2342` から分けた `feature/require-question-tools` に置く。元の作業ブランチの未コミット変更は変更していない。

## 実装

- 有効な既存の開発者指示を取得し、質問ツールを必須とする方針を新規開始・復元・リセットへ適用する。
- 非同期質問を既存カードへ表示する。回答は実行中なら `turn/steer`、完了後なら `turn/start` で届ける。
- 回答送信の成功後に回答済みを保存する。拒否と終了時の失効も保存し、復元で未回答に戻さない。
- 回答送信中のEscを中断へ流さず、単一・グリッド・入力欄の共有経路を質問の共通処理へ接続する。
- MacとiOSの回答キーを `id ?? question` に揃える。従来のIDなしデータも保持する。

配送元を一つの型にまとめる設計（Model the Domain）を採用し、既存カードとワイヤを再利用した。実際の応答と描画で確かめる原則（Prove It Works）に従い、模擬ワイヤのテストに加えて実Codexと画面外描画を検証する。

## 実行結果

| 対象 | 結果 |
|---|---|
| CodexAppServerKit | 109テスト成功 |
| AppBootstrap | 208テスト成功 |
| SessionFeature | 最終実装で1,289テスト実行。変更前から再現する下記2ケースのみ失敗 |
| 質問カードのUI | 9テスト成功。送信中Escと送信後の別カードを閉じる対照、実行中・完了後のボタン、重複タイトルの入力欄を実走 |
| DashboardFeature | 最終実装で2,183テスト成功、既知の問題1件を含む。実Gitの別パス41テスト成功 |
| iOS PhloxKit | XCTest 400件、Swift Testing 668件成功。合計1,068件 |
| iOSの既存raw-value lint | 成功 |
| iOSのシミュレーター向けDebugビルド | 成功。起動・実機確認は行っていない |
| macOSのDebugアプリ | `xcodebuild`成功。分離した実アプリを起動し、実Codexによる同期・非同期の質問カード、回答送信、回答後の最終返答をCUAのAXと画面画像で確認 |
| 実Codex 0.164.0、gpt-6.1-sol | 一時会話で同期質問と回答、非同期質問と実行中の `turn/steer`、回答後の返答を確認。ツール名を指定しない承認確認の模擬依頼でも、非同期質問ツールの使用と回答後の返答を確認。手元実行であり、リポジトリの自動テストには未登録 |

標準テストは `compact-test` と共通の `managed-build` を経由する。Macの正本は `macos/scripts/run-swift-tests.sh`。作業出力はworktree内の `.verification/question-tools-20261023/`。

Macの標準ゲート全体の終了コードは1。原因は変更前にも確認したSessionFeatureの2ケースであり、全体greenとは判定していない。最終ログは `macos-regression.log`。既存不具合を今回の差分でスキップ・既知問題化していない。

Macの独立したLint・型チェッカーは未設定。Swiftコンパイラによる型検査とパッケージのビルド・リンクは標準テストの事前ビルドで実行した。

実際に生成した `question-snapshots/async-running-duplicate-titles.png` と `async-completed-duplicate-titles.png` を目視した。二つの同文質問と独立した入力欄が表示され、実行中は中断ボタン、完了後は通常の送信ボタンが表示された。質問カード固有の旧見本 `PhloxReply.dc.html` は現行の `ClaudeDesign` 配下に見つからず、見本との比較は未実施。

### macOS Debug実アプリでの操作

追加検証の出力は `.verification/question-tools-runtime/`。正本 `macos/project.yml` から生成した検証専用projectでDebugアプリをビルドした。生成物の参照先とbundle IDのみ分離し、正本設定は変更していない。標準Debugのad-hoc署名でビルド・リンクに成功し、コピー後の `codesign --verify --deep --strict` も成功した。データ、Defaults suite、アプリID、モバイルポートを分離し、既存のRelease・Debugを起動したまま確認した。

- Defaultモードの実Codex `gpt-6.1-sol` に、ツール名を指定せず承認確認を依頼した。非同期質問カードと、回答を待ちながら続く説明を確認した。「中止」を選択して送信し、送信中の操作無効化、回答済み表示、最終返答「検証結果: 中止」と完了状態を確認した。
- 同じ会話をPlanモードに切り替え、計画に必要な構成の好みを質問させた。同期質問カードと待機状態を確認し、「箇条書き中心」を送信した。回答済み表示と最終返答「同期検証結果: 箇条書き中心」を確認した。
- 操作と画像確認にはCUAを使用し、XCUITestや入力ソースの変更は行っていない。画像はCUAの会話記録にあり、ローカル画像ファイルは保存していない。この実アプリ操作は手元検証であり、リポジトリの自動E2Eテストには未登録。
- 保存済みの会話データでも両質問の `answered` と回答文字列、両最終返答を確認し、`runtime-transcript.json` に保存した。検証GUIと専用runtime、その子Codex・Claudeの終了をPIDで確認した。使用済みのコピーアプリとデータは所有を確認してゴミ箱へ移し、ログと会話記録は保持した。共通ビルド管理の終了記録は1件。

## 失敗・警告と扱い

- 設定メニューの外側クリックは `ComposerSettingPopoverTests.swift:115` の `closedByOutsideClick` が `legacy=false` と `true` で失敗する。変更前の `dev e36b2342` でも同じ13テストを実行して同じ2ケースの失敗を確認した。テストはスキップせず、本件では変更していない。
- DashboardFeatureの既知の問題は `GitHistoryWorkflowTests.swift:112` の改名前のブランチ使用順。既存のXCTestには4件中1件のスキップもある。本作業でスキップや既知問題化を追加していない。
- SwiftPMのスキーマ素材29ファイルの未指定resource警告、既存の非推奨API・actor隔離・Sendable関連警告が出る。追加のAX描画テストでも `AXEnhancedUserInterface` 用の非推奨API警告が残る。同等の型付きAPIをSDKヘッダーで確認できず、警告を抑制していない。
- 新しいテストがアダプターと同じ `AsyncStream` を直接読んで停止したため、配信先の `adapter.threadEvents` を観測するよう修正した。Swiftコンパイラの異常終了は、動的AX呼び出しをマクロへ直接渡さず、結果をローカル値へ分けて同じ検査を維持することで解消した。
- 初回の画像出力先の準備漏れと、スキル一覧の模擬応答の形式不備を修正した。エラー表示を隠す処理は追加していない。
- 共通ビルド管理のロックが `actool` から常駐 `ibtoold` へ継承され、次の検証を開始できないことがある。共有プロセスの停止、ロック削除、ラッパーの迂回は行わず、自然解放を待って正規の入口で続行する。
- Debug実アプリの初回ビルドは、移設した生成projectの `scripts` resource参照が相対パスのままでexit65となった。生成物の参照を正本の絶対パスへ補正して再ビルドに成功した。resourceの除外は行っていない。成功時にもAppIntents依存がないためmetadata extractionを省略した警告が出た。

## 制約

自然文の質問をアプリが完全に識別して阻止する保証はしない。外部由来threadの過去固有の開発者指示は、現在の有効設定と明示パラメーター以外を取得できず、保持を保証しない。

XCUITest、iOS実機操作、公開、mainへのマージ、日常利用中のPhloxへの反映は行っていない。
