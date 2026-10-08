# Phlox 1.9.0（build 30）リリース記録

## 状態

準備中・未公開。対象は `dev` の開発変更と Haiku 5.5 対応。追加修正を含む `ed062bd3` をdev・verifyに統合しpush済み。新配布物は `.build/release-artifacts-1.9.0-manual/` に保持し、GitHub Releaseは下書き。mainは1.8.3のまま。以下の先行公証記録は旧 `c21a4472` 配布物の履歴であり、新配布物の記録は「最終配布物」に記載する。
2026-10-08 の公証認証確認で Apple が HTTP 403（必要な契約が未署名または失効）を返した。ユーザーの契約同意後、本体（`e43557eb-960c-4dca-a038-5dda9aebddcd`）とDMG（`fb2b3bb3-766d-487d-9f7b-1e0043e18570`）が Accepted。本体・DMGのstapler検証とGatekeeper検証が成功し、Sparkle署名も取得済み。未公開。

## 検証

- Haiku の設定・切替：対象5テスト成功。
- モデル一覧・API：ControlServer 152テスト成功。
- AgentDomain：579テスト成功。
- パッケージ検査：正本 `macos/scripts/run-swift-tests.sh` の初回実行では SessionFeature の旧 Haiku 前提の1テストが3問題で失敗。入力を Haiku 4.5 の明示 ID に変更し、Haiku 5.5 の切替検査を追加した後、SessionFeature 全数1,127件が成功。他は AgentDomain 579件、DesignSystem 193件、MessageStore 42件、DashboardFeature 本体1,981件＋実git26件、SimulatorBridgeKit Swift Testing 16件が成功。初回ゲート自体の終了コードは1であり、修正後は SessionFeature を個別に再検証した。
- Release：1.9.0 / build 30 のビルド成功。Developer ID による内側からの署名と `codesign --verify --deep --strict` 成功。本体とXPCの署名・権限・混入検査4件成功。
- シミュレーター：専用品質ゲート `verify-simulator-display.sh` 成功。前提のDebugビルドを作る前の補助検査は4失敗・4エラーとなったが、ゲートで所定のビルドを作成した後、補助検査・許可リスト・署名検査が成功。
- 画面外の画像：`PHLOX_DESIGN_SNAPSHOTS=1` の DesignSnapshotRenderTests 2件成功。ブラウザのURLポリシーがローカル見本HTML（file URL）の表示を拒否し、見本との画像比較は未確認。
- GUI：初回16件中14成功・2失敗。日本語合成入力を貼り付けに変更し、保存後のUndoをアプリへキー送信する形に修正。修正後の MarkdownBlockInteractionTests は6件成功・失敗0・スキップ0。初回16件の一括再実行はしていない。
- 公証・DMG：成功。配布用ZIP・DMG・公証記録は `.build/release-artifacts-1.9.0/` に保持。公開後確認は未実施。
- lint・独立した静的解析：未設定。

旧 `.claude/verify.sh` での DashboardFeature 並列実行は画像配信テストの差分計算で停滞し、中断（終了コード1）。その画像テスト単独は0.175秒で成功。正本の直列実行の結果とは分けて記録する。

GUI 初回検査は16件中14件成功・2件失敗（Markdown 編集・大きいHTMLのUndo）。失敗時のAX記録では `typeText` の日本語入力が「編集した本文」ではなく「編汣ճ׶狆」となり、別の失敗には XCUITest の `InputSource` 選択処理のエラーが残った。日本語のテスト入力はクリップボードを保存・復元した貼り付けに変更し、閲覧専用のキー入力拒否検査はASCII入力で検査した。期待する保存バイト列・Undo・表示・入力拒否のアサーションは維持した。実際のIME操作の検証とは区別する。

## 公開前に残る確認

- 公開後確認。
- デザイン見本との比較。ローカルHTML表示の拒否を別手段で迂回しない。
- 最終修正を含む配布物の再ビルド・署名・公証。
- ビルドには既存の非推奨API・Sendable・ViewBuilder・AppIntentsメタデータに関する警告がある。

上記の確認を終えるまで main への統合・公開は保留する。

## 配布前の追加検証

専用端末 `4EDDCC61-682B-4645-A470-B50DB27880C1` を作成し、通常データと別の保存先・defaultsでDebugを起動した。Phlox経由の `abc` 入力はiOS観測記録で確認した。観測用入力欄の `.asciiCapable` が日本語かな入力を制限していたため、検証用アプリを `.default` に変更する。変更対象はテスト用観測アプリだけであり、配布用本体のバイナリには含まれない。日本語変換・回転・異常接続の結果は検証後に記録する。

- 日本語変換：Phlox画面でフリック入力した `に` → `にほ` → `にほん` → `日本` を iOS の `events.json` と画面で確認。記録は `.build/release-simulator-runtime/debug-japanese-events.json`。手元で実行、テストには未登録。
- 回転：失敗。Simulator.appの横向き表示に対してPhloxは縦枠のまま横映像を表示した。補助側の `orientation: .portrait` と空の `propertiesChangedCallback` が原因。回転を描画・入力に伝える修正案を作成したが、Xcode 17C52の実表示ポートでは `screenProperties.uiOrientation` が0となり、画面情報を返せず接続が期限切れになる。標準の設定アプリへ切り替えても、検証用プローブで向き情報が得られない。四方向の合格とは扱わず、修正案は未完成。
- 接続エラー：実起動で `SimulatorXPCTransport.service` のエラークロージャーが配送キューからMainActorの実行時検査に入り、Debug本体がSIGTRAPで終了した。XPCのコールバックを `@Sendable` に変更して入口を配送キューで受ける修正後、実接続の期限切れで本体が継続し、タブ切替・ターミナル入力・実行中→待機の更新を画面で確認した。チャット出力とターミナルの子プロセス出力の継続は未検証。
- 追加検査：補助側の向き通知と入力解放を含む7検査成功。SimulatorBridgeKitはSwift Testing20件成功（別にXCTest3件成功）。`verify-simulator-display.sh`は回転修正案のビルド・パッケージ・補助検査を通過したが、その後の実接続は上記のとおり失敗した。XPCエラー通知修正後の対象1テストは成功。最終変更に対する全体ゲート・配布ビルド・公証は未実施。
- 参考：[devicetermの検証記録](https://github.com/sethdeckard/deviceterm/blob/main/Sources/CoreSimulatorBridge/as-tested.md)はXcode26.6で `uiOrientation` による向き取得を実測している。今回のXcode26.2の合格根拠としては使わない。

ユーザーの「進めて」を受けて回転の修正を継続する。制限付き公開の承認とは扱わない。ローカルAPIの `uiOrientation` は unsigned int であり、NSInteger宣言を修正する。型修正で0が解消するかと、回転通知の引数に向き情報があるかを実端末で調べる。検査の削除・固定向きでの成功扱い・公開は行わない。

型修正後も主・副画面の向き情報は0だった。診断用ビルドで45秒ずつSettingsとObserverの回転を監視したが、propertiesChangedCallbackは届かなかった。Observerの画面とかなキーボードが横向きへ再配置されたことをSimulator.appで確認した。したがって、回転が発生していない説明やcallback引数を捨てたことによる説明では解消しない。Xcode26.2／iOS26.2の画面取得経路に向き情報が供給されない内部原因は未確定。別の外部購読可能な取得APIは限定調査で確認できなかった。診断プログラムは手元で実行、リポジトリのテストには未登録。

型修正後の補助7検査は成功。最終ゲートの初回実行はPATHにxcodegenがなくexit127で失敗したため、既存の/opt/homebrew/binをPATHに含めて再実行した。実表示の回転修正は未完了。

PATH修正後の最終 `verify-simulator-display.sh` はexit0。Debugビルド、DashboardFeature／SimulatorBridgeKit、補助回帰・許可リスト・署名検査を実行した。これは実表示の回転失敗を解消した根拠にはならない。Phlox内で向きを指定する方式への変更についてユーザーへ承認を依頼中。main統合と公開は未実施。

ユーザーの「承認」により、Phlox内の「表示を回転」で表示と入力の方向を指定する方式を採用する。自動向き取得の未完成な補助側変更を撤去し、未回転surfaceは従来どおり取得する。Simulator.appで端末を回した際はPhlox側の表示方向を手動で合わせる。実際の端末姿勢変更や自動追従とは説明しない。新方式の実画面・入力検証と配布物の再生成はこれから行う。

### 承認後の方式と検証

- 自動取得案の補助側変更と向き通知用の検査を撤去した。向き情報なしで接続が期限切れになる変更は配布対象に含まれない。
- 「表示を回転」により四方向の描画・枠寸法を実画面で確認した。ゲストUIは横向きのまま、Phlox表示方向ごとの四隅で16回の押下・解放を記録し、iOS側座標を874×402ポイントに正規化して各期待位置との差が1.5%未満であることを検査した。記録は `.build/release-simulator-runtime/manual-corners-events.json`。キーボード表示中の初回確認ではOSの別ウィンドウに届いた接触が観測アプリに残らなかったため、観測アプリを再起動してキーボードなしで計測した。手元で実行、テストには未登録。
- 通常の横表示でタップを数えるボタンへの入力とカウンター更新を観測記録で確認した。
- 所有するDebug補助プロセスPID19910はTERMで終了しなかった。障害注入として同じ所有PIDをKILLで終了した後、本体PID19541が継続し、新補助PID26853が生成された。実画面が復旧し、表示方向が仕様どおり縦に戻ることを確認した。通常利用中の本体PID14065は保持した。チャット出力・ターミナル子プロセス出力の継続は未検証。
- 最終方式の `verify-simulator-display.sh` はexit0。接続の表示方向・入力解放・再接続での初期化と実XPCエラーの検査を含むDashboardFeature、SimulatorBridgeKit Swift Testing20件、Debugビルド、補助回帰・許可リスト・署名検査が成功。
- 変更をひとまとまりでレビューした。表示の回転と逆座標変換、スクロール差分、入力解放、接続世代、XPC配送キューとMainActorの境界を確認した。見本画像との比較は依然未確認。
- 最終UI検査はFileTreeInteractionTests・HTMLPreviewInteractionTests・BrowserTabInteractionTests・MarkdownBlockInteractionTests・PhloxLaunchSmokeTestsの13件成功、失敗0。結果は `.build/release-1.9.0-ui-final.xcresult`。最終の画面外画像検査は2件成功。配布用の新しいDerivedDataでの初回ビルドは署名チーム未指定によりexit65。既存のDeveloper ID署名を指定して再実行する。

### 最終配布物（未公開）

- Developer IDを指定した再ビルドは成功。既存警告に加え、SwiftTerm resource bundleに `warning: missing creator for mutated node` が出た。Releaseの起動検証は実施せず、DebugのUI検証と配布物の署名・公証検査を区別する。
- 本体・同梱コードを内側から署名し、深い署名検査成功。本体公証 `59bf550d-b336-4e7e-b3ca-b9d3213f9568` Accepted。staple後のvalidateとGatekeeper `accepted, source=Notarized Developer ID` を確認した。本体・XPC署名検査は4件成功。
- 背景・アイコン配置を含むDMGを生成・署名した。DMG公証 `0b6f5e50-36b4-4cb1-aa5a-f99c10b5caee` Accepted。staple後のvalidateとGatekeeper `accepted, source=Notarized Developer ID` を確認した。
- ZIPは24,483,697バイト、SHA256 `d005643af37383196a04634cefbb9150500a0ef8fa3da5556f058652974c33c9`。DMGは29,091,078バイト、SHA256 `ea5dfc69772df8ee1c698c490d41fecbfc3748e9c755f13a503201a6751db8dc`。DMGをGitHub Release v1.9.0の下書きへ添付し、GitHubのdigestとサイズが一致した。
- verifyをcheckoutして実行した起動・描画検査2件成功。結果は `.build/release-1.9.0-verify-final.xcresult`。その後featureブランチへ戻した。
- Sparkleの署名ツールはキーチェーン許可で待機した。SecurityAgentはComputer Useの安全制限により操作を拒否されたため、ユーザーに画面操作を依頼した。「許可した」の回答後、署名が得られた。別手段で迂回しなかった。
- ローカルHTMLのデザイン見本比較は未確認。main統合・公開する例外を明示して確認し、ユーザーの「許可した」を受けて比較未確認を記録したまま公開を進める。main統合・公開後疎通確認はこれから行う。
- 新ZIPの署名と長さを `site/appcast.xml` の1.9.0 / build30に記載した。en・jaの説明は下書きReleaseと同じ内容を使用する。
- Sparkle署名の実検証と、appcast・配布アプリの版/build・en/jaノート・添付DMG digest/サイズの整合検査が成功。手元で実行、リポジトリのテストには未登録。

今回起動したDebugは正常終了し、稼働中の `/Applications/Phlox.app`（PID14065）の継続を確認した。専用端末のshutdownはPreToolUseフックが「不可逆・高リスクの可能性」で拒否したため未実施。拒否後に実状態を確認し、既存5端末はShutdownで不変、専用端末はBooted。専用端末は削除せず保持し、Simulator.appも保持した。拒否を別手段で迂回しない。

## Release notes

### New

- Select Haiku 5.5 in Claude sessions and adjust its reasoning effort.
- Browse your working folder in the side panel. Open Markdown, source code, and HTML in tabs, and edit Markdown directly.
- Open web pages in an in-app browser with page search, zoom, and a shortcut to share the current page with an agent.
- Open an iOS Simulator in a session tab and interact with supported simulator configurations. After rotating a device in Simulator.app, use Rotate Display in Phlox to match its orientation; automatic rotation tracking is not available.
- GPT-6.1 Sol is available in the built-in Codex model list.

### Fixed

- Codex sessions show their current permission setting correctly.
- Copying messages and reading model and reasoning settings in the composer are easier.
- Page search focuses the search field and clears outdated results.
- Simulator connection errors no longer crash the app.

### 新機能

- Claude セッションで Haiku 5.5 を選択し、思考強度を変更できるようにしました。
- 作業フォルダのファイルをサイドパネルで参照し、Markdown・ソースコード・HTML をタブで開けます。Markdown は直接編集できます。
- アプリ内ブラウザにページ内検索・表示倍率・表示中のページをエージェントに伝える操作を追加しました。
- セッションのタブで iOS シミュレーターを開き、対応する構成で操作できるようにしました。Simulator.app で端末を回した後は、Phlox の「表示を回転」で向きを合わせます。回転への自動追従には対応していません。
- Codex の内蔵モデル一覧に GPT-6.1 Sol を追加しました。

### 修正

- Codex セッションの現在の権限設定を正しく表示するようにしました。
- メッセージのコピーと、入力欄のモデル・思考強度の表示を使いやすくしました。
- ページ内検索を開いた際の入力先と、古い検索結果の扱いを修正しました。
- シミュレーターの接続エラーでアプリが終了する問題を修正しました。
