# Phlox 1.14.0（build 36）リリース記録

## 状態

公開準備済み。2026-10-25にユーザーがリリースの実行と、`main` への統合・公開までの続行を指示した。
対象は 1.13.0 以降の `dev`（セッションの常駐実行、端末名の変更、Codex の質問カード、グリッドの自動整列など）。
macOS の DMG と Sparkle 更新を公開する。iOS アプリの配布は今回の対象外。

## 検証

- `macos/scripts/run-swift-tests.sh` の標準ゲートは exit 1。AgentDomain 577 件、DesignSystem 205 件、MessageStore 44 件、DashboardFeature の実 Git 41 件、SimulatorBridgeKit 20 件は成功。SessionFeature は 1296 件中 `ComposerSettingPopoverTests.clickingOutsideClosesNativePopover` の2ケースだけ失敗した。
- この2ケースは `780fc8c3` の時点から、テスト内で合成したクリックではポップアップが閉じず失敗する既知の問題。ユーザーの承認により、今回の統合検査（`gitflow.verifyCommand`）だけ `SWIFT_TEST_SKIP=clickingOutsideClosesNativePopover` で除外した。テストの修正は未実施。
- 代わりに、同じコミットの Debug 版を専用の保存先で起動し、新規チャット画面の設定ポップアップとモデル選択ポップアップを開いて、実際のマウスクリックで外側を押すと両方とも閉じることを確認した（手元で実行、テストには未登録）。プロセスへ直接送ったクリックでは閉じず、テストの失敗と同じ挙動だった。開始済みチャット側のポップアップと Release アプリでの画面操作は未実施。
- 最初の dev 統合検査では、DashboardFeature の `automaticGridFullHD`（5枚・6枚）が失敗した。タイトル付きの画面外ウィンドウが接続中の画面（内蔵 1512×982）へ縮められ、表示領域が 1235×802 になっていた。テスト用ウィンドウを画面で縮めない修正を加え、同テスト単独と DashboardFeature 全数（上記2ケースを除外した設定）が成功した。
- `verify-simulator-allowlist.py` は Xcode 17C52 / iOS 26.2 で成功。
- Release ビルド成功。Info.plist の版は 1.14.0 / build 36。
- アプリ公証 Accepted（`6894a373-e2f3-4f04-adb7-137b69aec0eb`）、DMG 公証 Accepted（`50240e3e-7a55-48ae-9857-057c021eb62a`）。双方の stapler validate と Gatekeeper `Notarized Developer ID` を確認。
- 配布アプリの署名検査4件成功。Sparkle ZIP の署名を `sign_update --verify` で照合し成功。アプリの `SUPublicEDKey` は運用手順の公開鍵と一致（手元の検査、テストには未登録）。
- 常駐実行方式の最初の版なので、appcast の項目に `phloxRuntimeProtocolMin` / `phloxRuntimeProtocolMax` = 1 を入れた。実装の `currentProtocolVersion` は 1。
- 実機 iPhone と XCUITest は実施しない。`session-runtime-lifecycle.test.py` の受入テストは今回再実行していない。独立した lint・静的解析は未設定。

## 配布物

| ファイル | バイト数 | SHA-256 |
|---|---:|---|
| Phlox.dmg | 35304962 | `68ad0782e474399c686ba1467c9fdc4225678dff7f783fe629bcffe8efc5b9a9` |
| Phlox-1.14.0.zip | 29930627 | `54d2b6ebf87287411db5e59a0f8095d3095ba74eaa774bdb0c19b668bd017018` |

## リリースノート

英日本文の正本は [`release/notes-v1.14.0.md`](../../../release/notes-v1.14.0.md)。GitHub Release と appcast に同じ内容を掲載する。
