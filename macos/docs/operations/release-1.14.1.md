# Phlox 1.14.1（build 40）配布準備

## 状態

準備中。main・verifyへは未統合。版番号を直したMac39/iPhone9の生成と、iPhone1.0/build9の更新・起動は成功した。その後の共通qualityでテスト用Git候補IDの隔離不足を検出し、Dev未反映で停止した。隔離を直した最終入力でqualityを先に実行し、Mac40/iPhone10を生成する。実機5シナリオ・公開・push・通常Macアプリの差し替えは未実施。
既に配布した1.14.0 / build 36を別バイナリへ再利用せず、新しい版とbuildで実機確認用の候補を作る。
iPhoneの表示版1.0を維持し、最終候補は1.0/build10にする。現在の実機は1.0/build9。既存buildの確認を最終候補の実機合格へ流用しない。

最初のbuild 37はビルド・署名・公証・stapleまで完了したが、producerがコンパイル用コピーをビルド前後に照合していなかったため採用しない。実際の改変は観測していない。コピーの改変を受け入れる独立否定テストが失敗し、入力照合の不足を確認した。生成project・Info.plist・lockを含むコピー全体を固定し、独立否定テストの成功後にbuild 38を新規生成した。build 37の実機合格記録は作らない。

iPhone版の最初のexportは、署名確認待ちの後に`errSecInternalComponent`で失敗した。ユーザーの再試行依頼後、同じ入力から再archive/exportして成功した。鍵のアクセス設定や署名検査は変更していない。最初の失敗記録を成功へ書き換えず、成功した再試行の来歴を別ファイルへ保存している。

インストール直前の実IPA検査で、build8の実際の表示版は1.0、記録は0.1.0という不一致を検出した。XcodeGenの生成Infoに既定値1.0が入り、配布入口・capture・releaseが実ファイルの表示版を照合していなかった。署名/hashは有効でも本候補は不採用。ユーザーは設定と検査の修正・新番号での再生成・インストールを選択した。元来歴を書き換えず、選定記録から除く。関連ソースの入力manifestが変わるためMac38も新候補へ流用しない。

## 検証の区別

- Dev `3f2efbbfe8b7b622c92a65a7df1da4c130a954d1`では共通の文書・品質・セキュリティ検査が成功した。macOS成功ID 5,585、既存の既知問題1件、許容skip23件、iOS694件、指定fake E2E13関数、ゲート56件、iOS lintとSimulator向けapp buildを確認した。これは本版の配布物・実機の合格ではない。
- 同Devのmainに対するコード・シナリオ独立レビューはpass。版/build/feed変更後の最終差分は改めて確認する。
- 必須実機5シナリオはnot_run。正本は`release/verification-scenarios.json`、実施結果は`release/verification-records.json`。人間の観測なしにpassedを作らない。PhotosPicker表示中の完了確認の扱いも確認事項として残す。
- 初回の回答読取timeoutの発生原因は未特定。Devの自動復帰修正は、timeout後の表示更新の停止を対象にしている。
- 旧1.14.0のZIPにはstaple後の`Contents/CodeResources`が不足していた。本候補ではstaple済appから最終ZIPを生成し、DMG内appとの一致と、DMGの公開鍵による実ZIP署名の検証を行う。
- 旧Mac build38の実配布ZIP署名/DMG内app一致と、旧iPhone build8のarchive/export・Ad Hoc署名・端末profileは成功した。しかしiPhoneの実表示版を未照合だったため、版情報が正しい配布候補と報告した点を訂正する。いずれもインストールや実機シナリオの成功ではない。
- 新しい版照合の回帰を含むゲート59件、Ad Hoc5件、iOS lintが成功した。まとまった修正と両ビルドの実入力/予定コマンドの独立レビューはpass、独立11検査が成功した。旧実IPA8を新しい検査が拒否することも確認した。
- Mac39は実コンパイル・署名・公証・stapleが成功し、実ZIPの署名・DMG内appとの内容一致も成功。iPhone9は実archive/exportと実Infoの識別子・表示版・buildの照合が成功。これらは新候補の共通quality全体・実機5シナリオの合格ではない。

## 配布物と来歴

旧記録は統合元リポジトリの`.verification/release-1.14.1/`と`.verification/release-1.14.1-build39/`へ保持する。最終候補は`.verification/release-1.14.1-build40/`へ保存する。
MacはDMGと最終ZIPを同じ`capture-build`工程で新規生成し、同じ実体をrelease照合へ渡す。
旧実ビルド記録はMacが`macos-build.json`、iPhoneが`ios-build-retry1.json`。元のsourceOIDはそれぞれ`2f5198fc644ab01eec4b0aa9788a2c2ff931987a`と`23602f0a71a43e13eeff27436e3971fcd0094724`。これらの元記録を変更せず保持する。

Mac39/iPhone9はともにsourceOID`6937d01316263f2b4db84ef79eac9e76e88160af`で、当時の入力manifestは一致する。build39用rootの`macos-build.json`/`ios-build.json`に元来歴を保持する。テスト修正で保守的な入力manifestが変わるため、この組合せは最終採用から外した。iPhone9の実インストール・起動記録は共通証拠基準の`release-evidence/1.14.1/ios-1.0-9/install-20261027/`。必須実機シナリオのpassedは作っていない。

## リリースノート

英日本文の正本は[`release/notes-v1.14.1.md`](../../../release/notes-v1.14.1.md)。公開する場合はGitHub Releaseとappcastへ同じ内容を使う。
