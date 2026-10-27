# Phlox 1.14.1（build 38）配布準備

## 状態

準備中。main・verifyへは未統合。MacとiPhone向けの署名済み候補は作成済みだが、実機確認は未実施。公開・push・通常アプリの差し替えは行っていない。
既に配布した1.14.0 / build 36を別バイナリへ再利用せず、新しい版とbuildで実機確認用の候補を作る。
iPhone側は0.1.0 / build 8を実ビルド引数と実効設定で固定して生成した。既存のbuild 7の確認を新候補へ流用しない。

最初のbuild 37はビルド・署名・公証・stapleまで完了したが、producerがコンパイル用コピーをビルド前後に照合していなかったため採用しない。実際の改変は観測していない。コピーの改変を受け入れる独立否定テストが失敗し、入力照合の不足を確認した。生成project・Info.plist・lockを含むコピー全体を固定し、独立否定テストの成功後にbuild 38を新規生成した。build 37の実機合格記録は作らない。

iPhone版の最初のexportは、署名確認待ちの後に`errSecInternalComponent`で失敗した。ユーザーの再試行依頼後、同じ入力から再archive/exportして成功した。鍵のアクセス設定や署名検査は変更していない。最初の失敗記録を成功へ書き換えず、成功した再試行の来歴を別ファイルへ保存している。

## 検証の区別

- Dev `3f2efbbfe8b7b622c92a65a7df1da4c130a954d1`では共通の文書・品質・セキュリティ検査が成功した。macOS成功ID 5,585、既存の既知問題1件、許容skip23件、iOS694件、指定fake E2E13関数、ゲート56件、iOS lintとSimulator向けapp buildを確認した。これは本版の配布物・実機の合格ではない。
- 同Devのmainに対するコード・シナリオ独立レビューはpass。版/build/feed変更後の最終差分は改めて確認する。
- 必須実機5シナリオはnot_run。正本は`release/verification-scenarios.json`、実施結果は`release/verification-records.json`。人間の観測なしにpassedを作らない。PhotosPicker表示中の完了確認の扱いも確認事項として残す。
- 初回の回答読取timeoutの発生原因は未特定。Devの自動復帰修正は、timeout後の表示更新の停止を対象にしている。
- 旧1.14.0のZIPにはstaple後の`Contents/CodeResources`が不足していた。本候補ではstaple済appから最終ZIPを生成し、DMG内appとの一致と、DMGの公開鍵による実ZIP署名の検証を行う。
- Mac build 38はコンパイル・署名・公証・stapleが成功し、実配布ZIPの署名とDMG内appとの内容一致も既存の検査入口で成功した。iPhone build 8は実archive/export、appとwidgetのAd Hoc署名条件、対象端末がprofileに含まれることの検査が成功した。いずれもインストールや実機シナリオの成功ではない。

## 配布物と来歴

配布物・実効設定・外部入力・実ビルド来歴は、統合元リポジトリの`.verification/release-1.14.1/`へ保存する。
MacはDMGと最終ZIPを同じ`capture-build`工程で新規生成し、同じ実体をrelease照合へ渡す。
実ビルド記録はMacが`macos-build.json`、iPhoneが`ios-build-retry1.json`。元のsourceOIDはそれぞれ`2f5198fc644ab01eec4b0aa9788a2c2ff931987a`と`23602f0a71a43e13eeff27436e3971fcd0094724`で、コンパイル入力manifestは一致する。両記録の成果物と外部入力のSHA-256を照合した。`release/verification-records.json`には実ビルド来歴への参照だけを追加し、端末へのインストールと実機結果は未記録のままにする。

## リリースノート

英日本文の正本は[`release/notes-v1.14.1.md`](../../../release/notes-v1.14.1.md)。公開する場合はGitHub Releaseとappcastへ同じ内容を使う。
