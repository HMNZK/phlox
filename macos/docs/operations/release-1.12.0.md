# Phlox 1.12.0（build 34）リリース記録

## 状態

署名・公証済み、公開準備完了。2026-10-20にユーザーがmainへのマージとリリースを指示した。
対象はdevの`c5ec0708`までの変更。未コミットの他作業は含めない。
macOSのDMGとSparkle更新を公開し、iOSアプリの配布は行わない。
配布物と記録は作業worktreeの`.verification/release-1.12.0/`に保管する。

## 検証と制限

- dev統合後のDebugビルド成功。DesignSystem 205件、DashboardFeature 2168件（既知問題1件）と実Git 41件成功。
- SessionFeatureは1212件中、既存の`AcceptanceFileChangeCodeViewTests.swift:59`の行番号期待値が1件失敗。今回の修正と対象テスト・分類処理に差分なし。ユーザーはこの失敗を了承してdevへのマージを指示し、続いてmainへのマージ・リリースを指示した。全テスト成功とは扱わない。
- Debug版を実際に操作し、新規・復元チャットの初回と2回目の終了表示、タブ・グリッドの表示、再フォーカス時のチェック消去を確認した。
- Xcode build 17C52とiOS 26.2のシミュレーター許可リスト照合成功。日本語入力・四方向・異常再接続などの未検証範囲は既存の互換性記録を引き継ぎ、今回の合格には含めない。
- XCUITestはユーザー指示により実行しない。独立したlint・静的解析は未設定。
- 追加の正本ゲートはAgentDomain 573件、MessageStore 44件、CodexAppServerKit 101件、ControlServer 169件、LocalHTTPServer 33件、AppBootstrap 176件、SimulatorBridgeKit 20件が成功（計1116件）。
- Releaseビルド成功。初回は検証用プロジェクトの相対参照とチーム指定不足、2回目は資源バンドルの署名方式不一致、3回目は同梱scriptsの相対参照不足で失敗。設定を修正して再実行した。PTYKit非推奨API、TerminalUI Sendable、AppIntents依存なし、SwiftTerm資源バンドルのmutated node警告が残る。
- 最初の公証はInvalid（`cb00e389-e51f-45bc-a66d-01c0d55e996d`）。同梱SparkleヘルパーのDeveloper ID署名・タイムスタンプ不足、本体とXPCの開発用get-task-allowを指摘された。内側からDeveloper IDで再署名し、本体とXPCにはソースの配布用権限を適用して解消した。
- 最終アプリの公証Accepted（`edb47a35-362d-41e1-aba5-39b7a0db5a27`）、DMGの公証Accepted（`5e9d6380-2003-4269-9e3f-0b661fb6a862`）。双方のstapler validateとGatekeeper accepted（Notarized Developer ID）を確認。
- 公証後の配布用署名検査4件成功。凍結済み権限構成検査の構造検査成功、DPK構成の実ビルドはSigning.local.xcconfigのチーム設定が無く既定でスキップ（未検証）。
- Sparkle ZIPの署名を、配布アプリ内の公開鍵とCryptoKitで照合して成功（手元の検査、リポジトリのテストには未登録）。Releaseアプリ自体の画面操作は未実施。

## 配布物

| ファイル | SHA-256 |
|---|---|
| Phlox.dmg | `8ae08acc424b1732414f2d71a0d479ec88d759390b04d08d05d1b290c8a869be` |
| Phlox-1.12.0.zip | `6c5cb49d30309f3020d7a83ee1cf07ab2109c765aebcc1f838ac181216560a2c` |

## リリースノート

英日本文の正本は[`release/notes-v1.12.0.md`](../../../release/notes-v1.12.0.md)。GitHub Releaseとappcastへ同じ内容を掲載する。
