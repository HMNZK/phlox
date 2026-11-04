# Phlox 1.14.5（build 48）

`dev` の `ec88fa8a` から作成する Mac 配布候補。レンダリング表示の Markdown をスクロールした際のフリーズと、Claude 使用量更新の不要な集計処理を修正する。先に作られた未公開の build 47 にはフリーズ修正が含まれないため、今回は一意な build 48 を用いる。

日英のリリースノートは `release/notes-v1.14.5.md` を正本とする。Mac アプリと DMG を Developer ID で署名・公証・staple し、DMG に含めた同じ staple 済みアプリから Sparkle 配布 ZIP を作成する。既存の公開済み配布物は変更しない。

実機確認用として同じソースから iOS 1.0/build 18 を作成する。iOS アプリの一般公開は今回の対象に含めない。Mac/iPhone の識別済みの候補で `release/verification-scenarios.json` の必須実機5シナリオを観測し、未実施項目を成功として扱わない。

準備・ビルド・品質検査・署名と公証・独立レビュー・実機観測の記録は作業 worktree の `.verification/release-scroll-1.14.5-20261104/` に作成する。公開に必要な配布物と実機証拠は、worktree を片付ける前に本体リポジトリの `.verification/release-evidence/1.14.5/mac48-ios18/` へ移し、`release/verification-records.json` の参照先と照合する。

すべての必須検査が成功した後、共通マージツールで作業ブランチから dev、dev から main へ統合する。履歴の秘密情報検査を経て、GitHub Releases の DMG・Sparkle ZIP・日英ノート・appcast を公開し、実際のダウンロードと更新フィードを確認する。

## 現在の状態

準備中。最新版のビルド、実機検証、main 統合、公開はいずれも未完了。既知の Git 履歴順序の問題と状態モデルの既知の違反は今回の修正で解消したとは扱わない。利用中のアプリと常駐サービスは終了させない。
