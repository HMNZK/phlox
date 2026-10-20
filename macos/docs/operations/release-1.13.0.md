# Phlox 1.13.0（build 35）リリース記録

## 状態

公開済み：[GitHub Release v1.13.0](https://github.com/HMNZK/phlox/releases/tag/v1.13.0)。タグは `816b99ac`。2026-10-20にユーザーが今回の変更のマージとリリースを指示した。
対象は 1.12.0 以降の `dev` と、Codex 版 pstack・エージェント別スキル候補の変更。
macOS の DMG と Sparkle 更新を公開する。iOS アプリの配布は今回の対象外。

## 検証

- `macos/scripts/run-swift-tests.sh` の標準ゲートは exit 0。AgentDomain 573 件、DesignSystem 205 件、MessageStore 44 件、SessionFeature 1226 件、DashboardFeature 本体と実 Git 41 件、SimulatorBridgeKit 20 件が成功。CodexAppServerKit の全体 102 件も成功。pstack 生成器テストとシミュレーター許可リスト検査も成功。
- Release ビルド成功。Info.plist の版は 1.13.0 / build 35。既存の PTYKit 非推奨 API、TerminalUI Sendable、AppIntents 依存なし、SwiftTerm 資源バンドルの警告が残る。
- アプリ公証 Accepted（`a534929e-27e9-42f2-88e0-1c6fde1b1dcb`）、DMG 公証 Accepted（`6b55896d-c9a1-4d85-a4a4-899bcfc776b7`）。双方の stapler validate と Gatekeeper `Notarized Developer ID` を確認。
- 配布アプリの署名検査4件成功。Sparkle ZIP の署名をアプリ内公開鍵で照合し成功（手元の検査、リポジトリのテストには未登録）。更新フィードの版・サイズ・署名・英日ノートを手元で照合し成功（テストには未登録）。
- 統合後の専用 Debug 版で新規チャットの Codex を選び、`/teto` から `$pstack-codex:poteto-help` と `$pstack-codex:poteto-mode` が出ることを AX とスクリーンショットで確認。後者を選択し、入力欄へ `$pstack-codex:poteto-mode` が入ることも確認した。Release アプリの画面操作は未実施。
- 実機 iPhone と XCUITest は実施しない。独立した lint・静的解析は未設定。

## 配布物

| ファイル | バイト数 | SHA-256 |
|---|---:|---|
| Phlox.dmg | 32823904 | `75f2ef3bc9aa273a59fe9e26619c67cdfbb30a635376c4948903dfe66fe39ac6` |
| Phlox-1.13.0.zip | 27734719 | `07ac82450939d91852750ffa52c228f29b651336d5accf09350c60cf5bf92b8d` |

## 公開後の確認

- `feature/pstack-codex` → `dev` → `verify` → `main` を fast-forward し、3 ブランチを origin へ atomic push。`dev` に元からあった未コミットの iOS 資料は退避後に復元され、変更内容と未追跡ファイルは残した。
- Sparkle ZIP を `HMNZK/phlox-dist` の `updates` Release、DMG を `HMNZK/phlox` の v1.13.0 Release に公開。GitHub の最新版表示は v1.13.0、DMG 添付サイズは 32823904 バイト。
- [Pages run 39404598989](https://github.com/HMNZK/phlox/actions/runs/39404598989) 成功。公開フィードは HTTP 200、先頭は 1.13.0 / build 35。英日ノート、ZIP サイズと署名が手元の記録と一致。
- 最新版 DMG と更新 ZIP の公開 URL は HTTP 200。GitHub から再ダウンロードした両ファイルの SHA-256 は上表と一致。これらは手元で実行した検査で、リポジトリのテストには未登録。
- Web 取得ツールは GitHub Release を cache miss、appcast URL を非対応として取得できなかった。OS の CA バンドルを指定した Python HTTPS 検査で証明書検証を有効にしたまま確認した。

## リリースノート

英日本文の正本は [`release/notes-v1.13.0.md`](../../../release/notes-v1.13.0.md)。GitHub Release と appcast に同じ内容を掲載する。
