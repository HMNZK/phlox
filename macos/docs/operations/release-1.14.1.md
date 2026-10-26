# Phlox 1.14.1（build 37）配布準備

## 状態

準備中。main・verifyへは未統合で、配布物は未作成。公開・push・通常アプリの差し替えは行っていない。
既に配布した1.14.0 / build 36を別バイナリへ再利用せず、新しい版とbuildで実機確認用の候補を作る。
iPhone側は0.1.0 / build 8を実ビルド引数と実効設定で固定する予定。既存のbuild 7の確認を新候補へ流用しない。

## 検証の区別

- Dev `3f2efbbfe8b7b622c92a65a7df1da4c130a954d1`では共通の文書・品質・セキュリティ検査が成功した。macOS成功ID 5,585、既存の既知問題1件、許容skip23件、iOS694件、指定fake E2E13関数、ゲート56件、iOS lintとSimulator向けapp buildを確認した。これは本版の配布物・実機の合格ではない。
- 同Devのmainに対するコード・シナリオ独立レビューはpass。版/build/feed変更後の最終差分は改めて確認する。
- 必須実機5シナリオはnot_run。正本は`release/verification-scenarios.json`、実施結果は`release/verification-records.json`。人間の観測なしにpassedを作らない。PhotosPicker表示中の完了確認の扱いも確認事項として残す。
- 初回の回答読取timeoutの発生原因は未特定。Devの自動復帰修正は、timeout後の表示更新の停止を対象にしている。
- 旧1.14.0のZIPにはstaple後の`Contents/CodeResources`が不足していた。本候補ではstaple済appから最終ZIPを生成し、DMG内appとの一致と、DMGの公開鍵による実ZIP署名の検証を行う。

## 配布物と来歴

配布物・実効設定・外部入力・実ビルド来歴は、統合元リポジトリの`.verification/release-1.14.1/`へ保存する。
MacはDMGと最終ZIPを同じ`capture-build`工程で新規生成し、同じ実体をrelease照合へ渡す。
成果物のSHA-256、公証結果、署名検査結果、端末・インストール証拠は、実測した後に記録する。

## リリースノート

英日本文の正本は[`release/notes-v1.14.1.md`](../../../release/notes-v1.14.1.md)。公開する場合はGitHub Releaseとappcastへ同じ内容を使う。
