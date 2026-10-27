# Phlox 1.14.1（build 42）配布準備

## 状態

準備中。非同期質問の表示修正と後続の実行状態改善を含め、Mac42/iPhone12を新規生成する。Mac41/iPhone11はこれらの変更前の入力で生成されたため採用しない。verify・mainへの統合、必須実機5シナリオ、公開、pushは未実施。
既に配布した1.14.0 / build 36を別バイナリへ再利用せず、新しい版とbuildで実機確認用の候補を作る。
iPhoneの表示版1.0を維持し、次の候補は1.0/build12。既存buildの確認を最終候補の実機合格へ流用しない。

ユーザーはbuild9とbuild10の更新後に既存の会話一覧が見えるとそれぞれ報告した。これは基本的な画面/接続の観測であり、最終候補の必須5シナリオの合格ではない。外出中は所有を照合したiPhone10のexportとcodesignだけを停止し、中断記録を保存した。帰宅後の再署名は確認待ちにならず成功した。本体/Widgetの実版と署名、有効な端末profileを照合し、アンインストールせず9から10へ更新した。最初の起動は端末ロックで拒否されたが、ユーザーの解除後に起動とプロセス照会が成功した。build10の一覧表示の人間による観測は同ビルドのインストール記録へ保存した。

最初のbuild 37はビルド・署名・公証・stapleまで完了したが、producerがコンパイル用コピーをビルド前後に照合していなかったため採用しない。実際の改変は観測していない。コピーの改変を受け入れる独立否定テストが失敗し、入力照合の不足を確認した。生成project・Info.plist・lockを含むコピー全体を固定し、独立否定テストの成功後にbuild 38を新規生成した。build 37の実機合格記録は作らない。

iPhone版の最初のexportは、署名確認待ちの後に`errSecInternalComponent`で失敗した。ユーザーの再試行依頼後、同じ入力から再archive/exportして成功した。鍵のアクセス設定や署名検査は変更していない。最初の失敗記録を成功へ書き換えず、成功した再試行の来歴を別ファイルへ保存している。

インストール直前の実IPA検査で、build8の実際の表示版は1.0、記録は0.1.0という不一致を検出した。XcodeGenの生成Infoに既定値1.0が入り、配布入口・capture・releaseが実ファイルの表示版を照合していなかった。署名/hashは有効でも本候補は不採用。ユーザーは設定と検査の修正・新番号での再生成・インストールを選択した。元来歴を書き換えず、選定記録から除く。関連ソースの入力manifestが変わるためMac38も新候補へ流用しない。

## 検証の区別

- Devへの統合は`9978c6254519c8a7e7188eac403b9719b9277e0f`で成功した。共通検査はmacOS成功ID 5,585、既存の未解決の既知問題1件、許容skip23件、iOS694件、指定fake E2E13関数、ゲート59件、Ad Hoc5件、標準入口回帰、iOS lint/Simulator app buildが成功。文書変更0、security exit0、例外承認は未使用。記録は`gitflow-merge.BbLjuiBV/quality-20261027T043217489113/`。これは実機5シナリオの合格ではない。
- 後続のverify統合は`gitflow-merge.82qqy7WJ`でquality exit1となり反映されていない。MobileProxyの`slotReleasedWhenUpstreamConnectFails`がEOF（read結果0）を期待したが-1で失敗した。元検査ではerrnoを取得しておらず原因は未特定。診断ログだけを加えたコピーで10回の実行は成功したが、正式検査の失敗解消とは扱わない。iOS/fake E2E/統合時securityは未到達。ゲート59件、Ad Hoc5件、標準入口回帰は成功した。
- 手元の制御実験では、解放した動的ポートを別の待受サーバーへ再割当すると、同じEOF期待がread=-1/errno=35で失敗した。接続先0を使う比較実験では、同じ競合相手を置いても3接続ともEOFとなった。元失敗の直接原因は引き続き未確定。テストの接続失敗入力を0へ変更して再割当競合を除き、EOF・3回の逐次接続・スロット解放の検査と500ミリ秒の期限は維持する。制御実験は手元の一回の確認で、リポジトリのテストには未登録。製品コードは変更しない。テストも含む入力manifestが変わるため、修正後の最終候補はMac41/iPhone11を新規生成する予定で、40/10の実機観測は流用しない。
- 修正後は標準入口でMobileProxyの67件が成功した。既存のSendable警告2件（非Sendableのclient参照と可変request参照の並列capture）は残る。これは限定したパッケージ検査で、後続の共通quality全体や実機検証の合格ではない。
- 製品コード・テストとシナリオの独立レビューはpass。Mac40の配布メタデータは`edaafbf9ec219a331275da23cc621cea07e87021`まで、今回の接続失敗テスト修正は`5467c93116f4c8ffa2482980e73382a403c89892`までを対象とする。正規化差分SHAに対応するDev向け1シナリオとmain向け6シナリオのpassを`release/verification-reviews.json`へ記録した。以降の配布メタデータは生成後に照合し、実機合格とは区別する。
- 必須実機5シナリオはnot_run。正本は`release/verification-scenarios.json`、実施結果は`release/verification-records.json`。人間の観測なしにpassedを作らない。PhotosPicker表示中の完了確認の扱いも確認事項として残す。
- 初回の回答読取timeoutの発生原因は未特定。Devの自動復帰修正は、timeout後の表示更新の停止を対象にしている。
- 旧1.14.0のZIPにはstaple後の`Contents/CodeResources`が不足していた。本候補ではstaple済appから最終ZIPを生成し、DMG内appとの一致と、DMGの公開鍵による実ZIP署名の検証を行う。
- 旧Mac build38の実配布ZIP署名/DMG内app一致と、旧iPhone build8のarchive/export・Ad Hoc署名・端末profileは成功した。しかしiPhoneの実表示版を未照合だったため、版情報が正しい配布候補と報告した点を訂正する。いずれもインストールや実機シナリオの成功ではない。
- 新しい版照合の回帰を含むゲート59件、Ad Hoc5件、iOS lintが成功した。まとまった修正と両ビルドの実入力/予定コマンドの独立レビューはpass、独立11検査が成功した。旧実IPA8を新しい検査が拒否することも確認した。
- Mac39は実コンパイル・署名・公証・stapleが成功し、実ZIPの署名・DMG内appとの内容一致も成功。iPhone9は実archive/exportと実Infoの識別子・表示版・buildの照合が成功。これらは新候補の共通quality全体・実機5シナリオの合格ではない。

## 配布物と来歴

旧記録は統合元リポジトリの`.verification/release-1.14.1/`、`.verification/release-1.14.1-build39/`、`.verification/release-1.14.1-build40/`、`.verification/release-1.14.1-build41/`へ保持する。次の候補は`.verification/release-1.14.1-build42/`へ保存する。正式recordsとappcastの旧参照は新しい実配布物の生成・照合後に更新する。現在のソース入力とは一致しないため、旧参照のままでrelease検査が成功する状態ではない。
MacはDMGと最終ZIPを同じ`capture-build`工程で新規生成し、同じ実体をrelease照合へ渡す。
旧実ビルド記録はMacが`macos-build.json`、iPhoneが`ios-build-retry1.json`。元のsourceOIDはそれぞれ`2f5198fc644ab01eec4b0aa9788a2c2ff931987a`と`23602f0a71a43e13eeff27436e3971fcd0094724`。これらの元記録を変更せず保持する。

Mac39/iPhone9はともにsourceOID`6937d01316263f2b4db84ef79eac9e76e88160af`で、当時の入力manifestは一致する。build39用rootの`macos-build.json`/`ios-build.json`に元来歴を保持する。テスト修正で保守的な入力manifestが変わるため、この組合せは最終採用から外した。iPhone9の実インストール・起動記録は共通証拠基準の`release-evidence/1.14.1/ios-1.0-9/install-20261027/`。必須実機シナリオのpassedは作っていない。

Mac40のsourceOIDは`9978c6254519c8a7e7188eac403b9719b9277e0f`、iPhone10は`ef8a67f210a0d5e15bc7604ab66d13c5eb14427b`。両者の入力SHAは`83b3da3422dcbd8d32ea2e289cde94b567a7b4aaeb81a06980890430bd3293c2`で一致する。最終rootの`macos-build.json`と`ios-build-retry1.json`が正式来歴で、`release/verification-records.json`へ実測後の参照を追加した。元の中断は`ios-export-deferral.json`、原ログは`ios-export-deferred-20261027/`へ保存する。iPhone10の更新・起動記録は`release-evidence/1.14.1/ios-1.0-10/install-20261027/`。実機5シナリオのpassedは作っていない。

## リリースノート

英日本文の正本は[`release/notes-v1.14.1.md`](../../../release/notes-v1.14.1.md)。公開する場合はGitHub Releaseとappcastへ同じ内容を使う。
