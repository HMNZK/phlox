# Phlox 1.14.5（build 49）

`dev` の `ec88fa8a` から作成する Mac 配布候補。レンダリング表示の Markdown をスクロールした際のフリーズと、Claude 使用量更新の不要な集計処理を修正する。未公開のbuild 48からシミュレーターで見つかったiOSの追従問題も修正したため、最終候補は一意なbuild 49とする。

日英のリリースノートは `release/notes-v1.14.5.md` を正本とする。Mac アプリと DMG を Developer ID で署名・公証・staple し、DMG に含めた同じ staple 済みアプリから Sparkle 配布 ZIP を作成する。既存の公開済み配布物は変更しない。

配布物の来歴照合用として同じソースから iOS 1.0/build 19 を作成する。iOS アプリの一般公開は今回の対象に含めない。2026-11-04、ユーザーは「全部シミュレーターで確認してよ。実機での確認はしたくない」と明示した。このリリースでは実機検査の代わりに、専用iOSシミュレーターの自動テスト・描画・操作で確認する。公開ゲートは既存の `quality` と `distribution`（署名・来歴・DMG/ZIP/フィード照合）を使い、実機の `release` 成功として扱わない。必須実機シナリオの定義・必須性は削除せず、実機結果は未実施のまま残す。

準備・ビルド・品質検査・署名と公証・独立レビュー・実機観測の記録は作業 worktree の `.verification/release-scroll-1.14.5-20261104/` に作成する。公開に必要な配布物と来歴証拠は、worktree を片付ける前に本体リポジトリの `.verification/release-evidence/1.14.5/mac49-ios19/` へ移し、`release/verification-records.json` の参照先と照合する。

すべての必須検査が成功した後、共通マージツールで作業ブランチから dev、dev から main へ統合する。履歴の秘密情報検査を経て、GitHub Releases の DMG・Sparkle ZIP・日英ノート・appcast を公開し、実際のダウンロードと更新フィードを確認する。

## 配布候補の検証結果（公開前の記録）

固定ソース `c9892288` から Mac 1.14.5/build 49 と iOS 1.0/build 19 を生成した。Mac と DMG の署名・公証・staple・Gatekeeper、更新 ZIP の署名、iOS の archive/export が成功した。最終配布物と来歴は上記の `mac49-ios19/` に保存し、元ファイルとSHA-256が一致することを確認した。本書は公開前の検証記録であり、統合・公開後の実測結果は同じ保存先の`publication-result.json`へ記録する。旧候補build 48/18は公開しない。方針変更前にiPhoneへbuild 18を導入・起動したが、ユーザーの選択回答を実機成功の証拠には採用しない。既知の Git 履歴順序の問題と状態モデルの既知の違反は今回の修正で解消したとは扱わない。

## リリース前の機能検証

送信・停止・再開・復元の4機能を別担当がソースと照合し、既存の選択テスト6パッケージと、隔離した固有IDのDebugアプリによるlifecycle・中断→同じ会話の再開を実走した。両ドライブで所有プロセスの残存は0。新規チャット画面の送信ボタン・Return・履歴再開画面・実IME・実行サービスも停止した状態からの本文復元までは、このドライブでは確認していない。

状態モデルが対象とする6ファイルは、前回の同期 `c1cfd334` から固定ソースまで変更がなかった。human/anyの前後計4実行で既知一覧との一致を確認し、client.closeを省いた破壊変種が新しい違反として検出されることも確認した。anyで残る中断通知と新しいターンの競合による一時的な表示ずれは未修正。

通常のReleaseがモバイル用8765番ポートを使用中のため、同じ署名済み候補を分離したデータで起動し、同じ製品MobileProxyパッケージを使った専用のTailscaleポートから候補のControlServerへ中継する。認証なしの応答が直接接続と一致し、認証済みAPIが候補へ到達することを確認した。通常利用のGUI・実行サービスと既存ペアリングトークンは入れ替えない。

上のiPhone向け検査は方針変更で使用終了。iPhoneには元の接続先URLを受け渡し、以後の実機検査は行わない。分離済みのMac候補と中継は、シミュレーターの接続先として準備した。hosted UI検査ではfake APIを使用し、実ネットワークの常時接続を実証するものではない。シミュレーターで確認した結果を実機のジェスチャー・VoiceOver音声・ハードウェア連携の合格へ読み替えない。

## シミュレーターで追加検出した問題

初回のスクロール追従測定は、20ptのステータスバー余白と空のUIKit contentLayoutGuideによって測定の前提を満たさなかった。生成用コピーでsafeAreaRegionsを空にし、実際のスクロール内容ビューを一意に測ると、79ptでは追従する一方、81ptでも新着に引き戻されることを再現した。診断ログでは旧PreferenceKeyの距離・高さが0のままで、新着時の追従判断も距離0を参照していた。

iOSではScrollGeometryから実際の表示領域・内容サイズ・オフセットを取得して追従距離と表示高さを更新する方針とする。80pt境界、境界外の読取位置保持、0.3秒の実フレームアニメーションという検査条件は維持する。描画テストの公開AX取得にも、実際のSimulatorのAXで同じコントロールを確認する外部操作経路を補う。これらは検証中で、現時点の配布候補build 48は最終版として公開しない。

修正後の実描画測定は79ptの追従・81ptの位置保持ともに成功し、0.3秒のアニメーションも実フレームで確認した（`simulator/scroll-fixed2.xcresult`）。内容サイズだけの変化では更新前の距離を保ち、スクロール位置または表示領域が変わったときに距離を更新する。公開AXの外部操作も、対象端末・時刻・一回限りのnonce・操作前の実ボタン・操作後の表示を照合する。

全描画suiteの26検査は成功した。公開AXでは、思考の強さ・権限メニューの名前が子のアクションにだけ付き、外側のメニューボタンは名前が空だった。メニュー本体へ既存と同じ名前を付け、実際の外側ボタンの名前と開閉を再検証する。

独立レビューで、外部AX証拠のrole判定が表示文字内の`AXButton`にも一致することを指摘された。行頭の番号に続くroleだけを読み、静的テキストがボタンを名乗る入力を拒否する否定例を追加する。実操作actorは別途AXPressの公開を要求しており、実施済み操作を偽装したとの指摘ではない。

最終ラベル修正後の描画suiteも26検査が成功し、公開AXの実操作10回の証拠を保存した（`simulator/design-final.xcresult`）。OSの文字サイズAX5でRemaining/RemainingInteractiveの両suiteも成功し、確認ダイアログの縦配置、取消前のAPI未実行、削除失敗、権限確認、使用量ポップオーバーの実際の上下端到達を測定した。79/81ptの再検証は成功した（`simulator/scroll-final.xcresult`）。同じrunで指定したrole否定例は関数名末尾の括弧が足りず0件一致だったため、成功証拠へ採用しない。正しいselectorで再実行し、実ID・1検査のstarted/passedを確認した（`simulator/parser-final.xcresult`）。実機固有の指操作・VoiceOver音声・ハードウェア認証の成功は記録しない。

## 確認した既存資料との不整合

- `ios/Makefile` と `ios/scripts/run-simulator.sh` の兄弟`../Phlox`前提は古く、現在は同じリポジトリの`macos/Packages`を参照する。Makefileコメントの`.github/workflows/ci.yml`も存在しない。
- `ios/scripts/run-interactive-verification.py` はwindowTitle付き`awaitingCUA`を要求するが、Remaining/GateのreadyにはwindowTitleがなく、Remainingのスクロールは`awaitingScroll`を使う。今回の専用actorは実端末・公開AXウィンドウ・nonce・時刻を照合して操作し、テスト自身が実UIKitの結果を検査した。
- `merge-verification-gates.md` の既存Makefileの`xcpretty`パイプに関する記述は、直接xcodebuildを実行する現在のコードと一致しない。
- `site-deploy-and-release.md` のdev→verify→mainは、現在のユーザー指示によるdev→mainと異なる。今回の実機を使わない公開方針は本書の明示例外で、実機成功には読み替えない。
- delivery 0042の`completed`と本文の`in_progress`・NFR-9未達が混在する。今回のフリーズ修正を全性能要件の達成とは扱わない。
- ADR 0045とRichMarkdownView・表テストのコメントは、存在しないdelivery 0024を参照する。

最終sourceの通常hosted回帰7suite・21検査もすべて成功した。公開AX・描画・境界測定・正しいparser実走・通常回帰のログと必要な画像/実測JSONは、正本の`mac49-ios19/simulator-qa/`へSHA-256照合付きで保存した。hostedアプリはbuild 18で最終製品ソースと一致することを照合し、配布用iphoneosのbuild 19をSimulatorへ導入したとは扱わない。追加の任意Root指ドラッグ・FaceID/Gate suiteと、実回線のTailscale切断/再接続は未実施。
