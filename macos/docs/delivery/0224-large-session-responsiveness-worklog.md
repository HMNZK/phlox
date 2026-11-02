---
status: active
last-verified: 2026-11-02
---

# 大履歴セッションの応答性改善の作業記録

読者は通信と画面を保守する開発者。既存の状態モデルを知る前提で、採否と実行した検証を確認する。要点は履歴を保持した転送削減、操作と変換の分離、効果と未確認の区別。

問題定義は[仕様](../specs/large-session-responsiveness.md)、方式は[ADR0224](../adr/0224-incremental-runtime-snapshots.md)。実装前に両方を作成した。

| 段階 | 状態 |
| --- | --- |
| 現行Releaseの調査 | 完了。稼働中のデータは変更せず、履歴量とプロセスsampleを観測。 |
| 設計 | 本文patch方式を候補に選択。別取得方式より境界と往復数が少ない。 |
| 基準の標準パッケージ検査 | AppBootstrap228件がexit 0。 |
| 実装とレビュー | 本文・子本文・rollingログの差分と厳密比較を実装。独立レビュー指摘2件を修正し、指摘範囲の再確認では再指摘なし。 |
| 大履歴の受入 | 最終ソースで合格。日本語の画面入力反映・送信・中断と保存一致を確認。 |
| 機能別回帰 | verify-phlox段1は6パッケージ、33パターンすべて一致、失敗・skip・0件一致なし。段2の最終受入と中断→再開が合格。 |
| プロジェクト品質ゲート | exit 0。Mac19パッケージ、iOS695件・lint・build、必須fake13件を実行。既知問題1件と既定の任意skipは残る。 |

コミット、マージ、Releaseへの置き換えは未承認。現在稼働中のセッションを終了させない。

## 初回の検証と修正

変更前AppBootstrap228件、初回の差分関連12件はexit 0。後続の初期化ラベルと不変配列の早期returnは、最終検査で再確認する。既存PTYKitの非推奨初期化、SwiftTermの未使用戻り値、TerminalUIの非Sendable警告が出た。ネイティブDebugの固有bundle IDと厳密署名検査は成功した。

最初の大履歴受入は送信・中断5回を通過した後、末尾更新1,686,316byteが128KiBの期待を超えてexit 1。診断用の2回目もexit 1で、全1,686,328byteのうちrawEventLogが1,682,663byteだった。本文は2,211件を共有し末尾2件のみだったため、rawログの全量再送を根本原因として修正する。期待値は緩めない。両runの所有プロセスは後片付けで終了を確認した。

独立レビューで、表示用の等価判定が時刻と正規化同値のUTF-8差を区別しない問題も見つかった。通信比較とサイズ計算を修正し、親本文・子本文の時刻と文字表現の回帰を追加する。指摘2件が未解決の間は完了としない。

管理出力の再利用は生成されたSwiftPM checkoutの`.git`保護で拒否された。元の出力は保持し、異なる絞込条件の検査は別の管理出力で実行した。ネイティブビルドは検証由来の`ibtoold`が一時的にロックを保持して拒否されたが、同プロセスの自然終了後に同じkeyで成功した。GUI確認待機を90秒で指定した試行は、既存の0〜60秒契約で起動前に拒否された。60秒へ直して再実行した。これらを製品テストの失敗と区別する。

## 最終ソースの大履歴受入

新しい`session-runtime-large-history.test.py`を手元で実行した。この実アプリ検査は標準qualityには未登録で、署名済みの固有bundle IDを持つアプリを別途必要とする。単体の差分回帰はAppBootstrapの標準テストに登録した。最終quality内では新規18件を含むAppBootstrap246件の成功を確認した。

固定fixtureは2,200件、本文3MiB超。`large-history-final/logs/large-history-metrics.json`では同じ状態の完全取得と差分取得を交互に5回実行し、各応答を完全状態と照合した。完全応答は各5,385,891byte、差分は各3,407byte。末尾更新は4,396byteだった。別の最終ソースrunである`large-history-profile`も合格した。これらは転送量の比較で、キーストロークや画面の遅延改善率ではない。計測中も同じMacの他作業は継続しており、API時間を純粋な画面性能として使わない。

大きいrawログの残留を修正した後、文字列の厳密比較も連続UTF-8領域と`memcmp`で行うようにした。共有領域なら内容走査を省く。最終ソースのnativeアプリはその後に再ビルドした。

最終runのGUIで、日本語を貼り付けて入力欄の値をAX確認し、送信ボタン、応答本文、中断ボタン、待機への復帰をAXとスクリーンショットで確認した。API検査後のGUI操作は追加送信1回・中断1回として台帳に記録され、最終2,215項目と保存JSONが一致した。実IMEとキーごとの遅延は未計測。別runのCUA `typeText`は入力へ反映せず、後続キー検査は待機終了後のapp quitとtimeout、検査コードの要素特定失敗により確認できなかった。貼り付け・画面操作の成功を物理キー入力の成功に読み替えない。

追加の`large-history-keyboard`では、2,213項目の画面で`pressKey("a")`を行い、入力欄のAX値が`a`になったことを確認した。続く消去操作はCUAの非activeエラーで実施できなかった。検査用の文字は送信しておらず、API検査後の追加送信・中断は0回、保存内容一致と所有cleanupの成功を確認した。ASCIIキーの反映確認であり、実IMEやキー単位の遅延測定とは区別する。

5秒の事後sampleは`large-history-profile/logs/post-fix-profile-summary.json`。常駐mainの3,130標本ではJSON変換0、イベント待機3,093だった。別workerにJSON変換を観測した。実ユーザー9セッションの事前sampleとは負荷が違うためCPU削減率を計算しない。

## 送信・停止・再開・復元の回帰

`verify-phlox`の段1は`unit/result.json`、段2は`lifecycle-final/ownership.json`と`stop-resume/ownership.json`に記録した。最終アプリでPTY・Codex・Claude・Cursorの受入がexit 0、中断後に同じClaude会話へ再開する検査もexit 0。段1のhelperが固定する`unit/swift`は管理ビルドの出力選択へ分離できないため、標準入口を使い自動整理対象外として保持した。

最初の通常受入では正常終了AppleEventが`replyError=-128`で拒否されexit 1。終了判定に一時ログを入れた別アプリでは確認ガードfalse・終了許可trueを観測し、受入が成功した。診断コードを原文へ戻した最終ソースのアプリでも、同じ受入がexit 0で成功した。一度の拒否の原因は未確定で、同期修正の副作用とも既存の競合とも断定しない。期待値や終了方法は緩めていない。一時ログは製品ソースに残していない。

## 最終の標準検査

正本の`macos/scripts/verification-gate.py quality`がexit 0で終了した。証拠は親リポジトリの`.verification/large-session-responsiveness-quality-20261102/quality-20261102T063902929946/result.json`。入力SHA256は`f08069ce17a4afa0db510f37c0a98aec3b2867f6b251cffc2a6f6ddbb5a1781f`。

- Macは登録された19パッケージを標準入口から実行した。新規18件を含むAppBootstrap246件、SessionFeature1,308件を含む。標準の任意skipは23 IDで、うち必須fake13件は別段階ですべて成功した。実CLIとopt-in性能試験を実行済みとしない。
- DashboardFeatureのGit履歴順序の既知問題1件は継続した。ADR0209で定義された、改名前の名前を再利用した場合の利用順の不一致であり、期待値と既知扱いは変更していない。
- iOSは695件の単体検査、既存のraw値lint、generic iOS Simulator向けbuild・linkが成功した。実機iPhoneとXCUITestは今回の品質ゲートの対象外。
- 今回はClaude実行状態機械を変更していないため、Claudeの状態モデル検査は対象外。AppBootstrap通信内の復元は専用回帰と実アプリで確認した。

各ownershipのcleanupは終了を記録したが、最終のプロセス監査で検証用GUIの再起動分（PID71989）が残っており、監査assertが1回失敗した。このPIDは通常版とは異なる`large-history-final/original/Phlox.app`の実行パスと起動時刻を確認してSIGTERMで終了し、`final-cleanup-audit.json`へ記録した。再監査は成功し、検証用GUI・常駐処理・fakeの残存なしと、品質ゲート後にソース入力が変わっていないことを確認した。通常のReleaseと常駐処理は停止していない。管理ビルドは2セッションをfinishし、最終の固有Debugアプリだけpinした。ユーザーから作業ブランチへのコミットのみ承認を得た。dev統合とRelease配布は保留する。

その後、ユーザーからリリースまでの一括承認を得た。追加診断・統合・配布の結果は[1.14.3の記録](../operations/release-1.14.3.md)へ引き継ぎ、本記録の初回失敗や未計測を成功に読み替えない。受入の原ログと保守スキルは元リポジトリの`.verification/release-1.14.3-20261102/`へ退避した。
