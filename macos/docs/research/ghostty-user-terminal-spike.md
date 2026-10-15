---
status: archived
last-verified: 2026-10-15
---

# Ghostty ユーザー用端末の試作評価

> **見送り（[ADR 0211](../adr/0211-decline-ghostty-user-terminal-engine.md)）。コードは dev に入っていない。** 2026-10-15 のユーザー判断により SwiftTerm の改善を優先する。

調査日: 2026-10-15。以下は `feature/ghostty-spike` の同名文書から転記した試作の記録であり、この資料整理でテスト・ビルド・手入力・計測を再実施したものではない。試作ツリーは読み取りだけにした。

試作時の ADR 0211〜0216 は **dev には無い**。この文書で「採用」「実装」「維持」「現行」と書かれた箇所は試作ツリー内の当時の判断・コードを指す。本ツリーの見送り ADR 0211 とは別物である。試作パッケージ・設定・テスト・診断コードは持ち込まず、過去の実行コマンドも dev の実行手順には使えない。`.build` のログ・画像・行番号は試作ツリー内の当時の参照先で、本作業では存在や内容を再確認していない。

## 見送り時に残す計測と判断（2026-10-15）

性能は 2026-10-15 の実機計測（各エンジン 3 回の中央値［最小–最大］。条件は ADR 0211 の「性能の計測」）。

| 計測 | エンジン | 生成側の時間 s | アプリの CPU 時間 s | 最大 CPU % | 落ち着くまで s（開始から） | 最大メモリ MB | 終了 12 秒後のメモリ MB |
|---|---|---|---|---|---|---|---|
| seq | ghostty | 0.64 [0.63–0.94] | 2.64 [2.59–3.58] | 297 [256–383] | 1.4 [1.4–1.9] | 173 [159–182] | 172 [158–182] |
| seq | swiftTerm | 0.65 [0.64–0.67] | 1.83 [1.54–2.32] | 183 [179–200] | 1.8 [1.5–2.6] | 184 [171–186] | 180 [171–184] |
| cat | ghostty | 0.98 [0.98–1.06] | 3.77 [3.74–4.04] | 370 [370–375] | 2.1 [2.0–2.1] | 230 [208–237] | 185 [178–237] |
| cat | swiftTerm | 0.72 [0.71–0.75] | 2.66 [2.13–2.69] | 174 [154–176] | 2.7 [2.1–2.9] | 175 [171–187] | 171 [171–186] |
| yes | ghostty | 1.07 [1.01–1.07] | 3.96 [3.88–3.96] | 366 [366–380] | 1.8 [1.7–1.8] | 175 [172–182] | 173 [172–182] |
| yes | swiftTerm | 1.03 [1.03–1.06] | 3.30 [2.75–3.38] | 200 [200–200] | 2.8 [2.2–3.0] | 171 [171–186] | 171 [171–186] |

Ghostty は大量出力後に落ち着くまでが0.4〜1.0秒短い一方、アプリの CPU 時間は約1.2〜1.4倍だった。待機中の CPU は同等、Option+← が効き、色付き出力後の余計な文字が出ないという点はユーザー提供の要約による。待機時の数値の原記録は本資料に無い。

日本語入力を理由とした途中の見送りは、試験方法の誤りとして訂正する。`CGEvent.postToPid` の合成キー試験は SwiftTerm でも同じ形で失敗した。入力の流れの記録では Phlox の取りこぼし・二重送信は0回、実キーボードのライブ変換・Space 候補選択は計8回とも確定文字が1回届き、Ghostty も合格した。以下の過去の失敗を実 IME の不適合の証拠には使わない。

最終的には、利点が小さい一方、可視テキストの VoiceOver 読み上げ未対応、有志の `libghostty-spm` と本家に無い `HOST_MANAGED` 改造への依存、日本語入力受付の自作・保守が残るため見送った。代わりに SwiftTerm の Metal 描画の試行、Option+←、色付き出力後の余計な文字を改善する（本作業では実装しない）。

公式の埋め込み用の部品と IME 対応が出た場合、または SwiftTerm の限界が明確になった場合に再検討する。`feature/ghostty-spike` のコードは dev に取り込まず、製品コードとして残さない。ブランチの削除は本作業では行わない。

## 以下は試作ツリー内の過去の記録

試作時の ADR は次の6本で、いずれも dev には無い。同じ番号の本ツリーの ADR と混同しない。

| 試作時の番号 | 試作で扱った内容 |
|---|---|
| 0211 | ユーザー端末の Ghostty 評価と途中の見送り・再判定 |
| 0212 | IME 評価用の表示エンジン設定 |
| 0213 | キー処理外の日本語確定の接続 |
| 0214 | Phlox 所有の入力ビュー |
| 0215 | 手入力の結果を受けた試作内の採用 |
| 0216 | 通知駆動 tick と出力経路の変更・取り消し |

## Phlox 所有の入力ビューによる最後の試行（2026-10-15）

### 実現性と参照版

固定版は `libghostty-spm 2.2.2026101301`、チェックアウトは `d403978c66870baa422709d1dde385730a4bdaef`。同版の `Ghostty.ref:1` は Ghostty `1e9e14af5df14211892f5fc15fd21a49c7d94868` を指定している。

下記は `macos/Packages/GhosttyTerminalUI/.build/` 内の実ファイルで確認した。

- `checkouts/libghostty-spm/Package.swift:27–29,40–43`：GhosttyKit はライブラリ製品として利用でき、バイナリ libghostty に依存する。
- `checkouts/libghostty-spm/Sources/GhosttyKit/GhosttyKit.swift:9`：`@_exported import libghostty`。
- `artifacts/libghostty-spm/libghostty/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/libghostty/module.modulemap:1–4`：ghostty.h を公開する。
- 同ディレクトリ `ghostty.h:503–550`：任意の `nsview`、`HOST_MANAGED`、ホストへの入力・リサイズコールバック。
- 同ヘッダ `1210–1255`：surface の生成、出力の write_buffer、描画、キー・text・preedit・IME座標。
- `checkouts/libghostty-spm/Sources/GhosttyTerminal/Controller/TerminalController+Surface.swift:81–97,168–187`：既存ラッパーもホスト管理 I/O とプラットフォーム設定を同じ surface に設定する。
- `checkouts/libghostty-spm/Sources/GhosttyTerminal/Platform/AppKit/AppTerminalView.swift:70–114`：CAMetalLayer の設定と NSView の引き渡し。Phlox 所有ビューでも同じ描画 API を利用できる。

したがって AppTerminalView は必須ではなく、Phlox が PTY を持ったまま直接 C API を利用できる。試作時の ADR 0213（dev には無い） の「C API はホストへ公開されていない」という記述は不正確だった。非公開なのはラッパーが保持する既存 surface であり、C API 自体は GhosttyKit から公開されている。

入力の参照元は [Ghostty SurfaceView_AppKit.swift（固定コミット）](https://github.com/ghostty-org/ghostty/blob/1e9e14af5df14211892f5fc15fd21a49c7d94868/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift)。`1101–1269` の keyDown / interpretKeyEvents、`1511–1529` の確定文字専用キー、`1920–2163` の NSTextInputClient / preedit 同期を読んだ。MIT の出典・著作権・許諾文は実装コメントに記載した。Web取得ツールでは Cache miss となったため、同じ raw URL を Python の urllib で読み取った。

### 実装と確認範囲

`UserTerminalView` は NSView を直接継承し、入力状態、文字収集、preedit、候補窓座標を所有する。TerminalController は初期化と設定生成に再利用するが、ビューの surface とその app は C API で生成する。出力は専用キューで直列化し、解放前に出力完了を待つ。入力コールバックは main queue へ順序を保って渡す。

Space で何度も選択範囲を変えた後の Return について、insertText が keyDown 内・外で来る双方を実 PTY の `/bin/cat` と照合した。各ケース4回連続し、偶数回は空の setMarkedText も挟む。確定文字だけが1回ずつ届き、CR・貼り付けの囲みが入らず、未確定状態が次の入力に残らないことを Swift Testing に追加した。既存の入力・実zsh/vim・リサイズ・配色・文字サイズ・ビュー載せ替え検査も新ビューに接続した。実 IME の呼び出しを計測した試験ではなく、呼び出し順を台本化した試験である。

作業中の絞り込みは、指定の `SWIFT_TEST_FILTER=… ~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh <パッケージ名>` だけを使った。最初の実行はコンパイルエラーで終了コード1（NSTextInputClient の actor 隔離指定と CGFloat→Double 変換）。修正後は通常確定1件、候補・既存操作など3件、Ghostty関連7件、候補1件、Dashboardの載せ替え等4件、最終変更後の候補・操作2件がそれぞれ終了コード0。テストの skip・期待値の弱体化はしていない。

### 最終検証（全件・画像・アプリビルドは各1回）

作業場所は指定の ghostty-spike。直下の AGENTS.md は存在せず読み取りは終了コード1だったため、提示された共通指示と macos/docs/README.md を適用した。

| コマンド | 終了コード・結果 |
|---|---|
| `SWIFT_TEST_FILTER='GhosttyEmbeddingTests/compositionThroughKeyDown' ~/.agents/scripts/compact-test ghostty-owned-input macos/scripts/run-swift-tests.sh GhosttyTerminalUI` | 初回1（上記コンパイルエラー）、修正後0・1件成功 |
| `SWIFT_TEST_FILTER='GhosttyEmbeddingTests/candidateCommitToPTY GhosttyEmbeddingTests/controls GhosttyEmbeddingTests/commitOutsideKeyDown' ~/.agents/scripts/compact-test ghostty-candidates macos/scripts/run-swift-tests.sh GhosttyTerminalUI` | 0・3件成功 |
| `SWIFT_TEST_FILTER='GhosttyEmbeddingTests' ~/.agents/scripts/compact-test ghostty-related macos/scripts/run-swift-tests.sh GhosttyTerminalUI` | 0・7件成功 |
| `SWIFT_TEST_FILTER='GhosttyEmbeddingTests/candidateCommitToPTY' ~/.agents/scripts/compact-test ghostty-final-related macos/scripts/run-swift-tests.sh GhosttyTerminalUI` | 0・1件成功 |
| `SWIFT_TEST_FILTER='UserTerminalEngineSettingsTests TerminalPanelViewWhiteboxTests' ~/.agents/scripts/compact-test ghostty-mount macos/scripts/run-swift-tests.sh DashboardFeature` | 0・4件成功 |
| `SWIFT_TEST_FILTER='GhosttyEmbeddingTests/controls GhosttyEmbeddingTests/candidateCommitToPTY' ~/.agents/scripts/compact-test ghostty-before-final macos/scripts/run-swift-tests.sh GhosttyTerminalUI` | 0・2件成功 |
| `env -u SWIFT_TEST_FILTER SWIFT_TEST_OUTPUT=full GHOSTTY_EVIDENCE_DIR="$PWD/macos/Packages/GhosttyTerminalUI/.build/owned-ime-evidence" ~/.agents/scripts/compact-test --full ghostty-final macos/scripts/run-swift-tests.sh GhosttyTerminalUI TerminalUI DashboardFeature` | 0・Ghostty 7件、TerminalUI 92件、DashboardFeature 2,073+35=2,108件の Swift Testing 成功。DashboardFeature の XCTest は3件成功・1件スキップ |
| macos で `/opt/homebrew/bin/xcodegen generate` | 0・生成成功 |
| macos で `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGhosttyBuild build` | 0・`BUILD SUCCEEDED` |
| `git diff --check` | 0 |

全件ログは `macos/Packages/GhosttyTerminalUI/.build/owned-ime-final-tests.log`、ビルドログは同ディレクトリの `owned-ime-debug-build.log` に保存した。

画像は同ディレクトリの `owned-ime-evidence/` に13枚保存した。そのうち `ime-marked-round-1.png`、`ime-marked-round-2.png` では「日本語」と下線が同じ位置に1組だけ表示され、`ime-committed-event-false-empty-false.png` では未確定文字・下線が消えたことを目視確認した。`controls-light.png` では配色と文字サイズの反映を目視確認した。13枚すべてを目視検査したという意味ではない。

スキップは既存 `MarkdownScrollPerformanceTests.testScrollFrames` の「PHLOX_SCROLL_PERFORMANCE=1 のRelease実行時だけ計測」。今回の変更で skip は追加していない。ビルドの警告は2件とも `Metadata extraction skipped. No AppIntents.framework dependency found.`。全件ログには復元失敗（unsupportedBackend、resume、threadIDMismatch、binaryNotFound）と後始末失敗（権限不足・dirty worktree・未マージブランチ）の出力がある。該当テストはいずれも成功している。`xcrun: error: unable to find utility "simctl"` はエラーメッセージを引数にしたテストの文字列で、今回の simctl 実行失敗ではない。

独立した lint・静的解析の専用ゲートは対象パッケージに未設定。型検査・コンパイル・リンクは SwiftPM と指定の xcodebuild で実施した。実アプリは起動せず、XCUITest・入力ソース設定変更・PTYKit変更・Ghostty改造・Zigビルド・commit等のGit変更は行っていない。

実 IME の呼び出し順・候補ウィンドウ・実アプリの Space 選択後の欠落解消は未検証。統括役の最終判定待ちで、失敗すれば 試作時の ADR 0211（dev には無い） を declined として打ち切る。

## 日本語確定の欠落と蓄積の修正（2026-10-15）

### 観測と原因の範囲

統括役の実アプリ確認で未確定文字・候補窓の位置は合格したが、最初の確定で文字がシェルへ届かず、次の変換では「日本語日本語」と重複して行が崩れた。提供画像 `/tmp/phlox-ime-shots/` の `04-japanese-preedit.png`、`06b-confirmed-again.png`、`07-before-return.png`、`09-retry-preedit.png`、`10-retry-committed.png`、`12-final-state.png` を読み、下線残留・重複・プロンプトの重なりを確認した。

固定版 `2.2.2026101301`（commit `d403978c66870baa422709d1dde385730a4bdaef`）の実ソースから、以下の経路を確認した。行番号は同版の `Sources/GhosttyTerminal/` 以下。

| 箇所 | 動作と問題 |
|---|---|
| `Platform/AppKit/AppTerminalView+NSTextInputClient.swift:12–28` | `insertText`・`setMarkedText`・`unmarkText` を内部ハンドラへ委任する。replacementRange は元から未使用 |
| `Platform/AppKit/TerminalTextInputHandler@AppKit.swift:45–63` | `NSApp.currentEvent == nil` なら解除より前に戻る。イベントがあり文字収集中なら収集、それ以外は `surface.paste` へ送る |
| 同 `:66–89,145–153` | 未確定更新は置換。解除は状態を消し `preedit("")` を送る。文字収集中の更新はキー処理末尾で同期する |
| `Platform/AppKit/TerminalKeyEventHandler@AppKit.swift:46–70` | 収集開始→`interpretKeyEvents`→preedit 同期→収集した確定文字のキー送信 |
| `Surface/TerminalSurface.swift:61–71,151–159` | `paste` は `ghostty_surface_text`、preedit は UTF-8 のポインタとバイト数で `ghostty_surface_preedit` を呼ぶ。空は長さ0 |
| `Controller/TerminalController+Surface.swift:87–102` | host-managed backend と `receive_buffer` を接続 |
| `InMemory/InMemoryTerminalSession.swift:219–229,249–260` | 公開 `sendInput` と C の受信コールバックは同じ `writeHandler(Data)` へ渡す |

Phlox は `GhosttyTerminalCoordinator` の `write` → MainActor の `onInput` → `TerminalPanelSession` → `UserTerminalController.send` → `PTYManager.write` と渡す。未確定状態の管理や再確定処理はこの後段にない。したがって送信0バイトは PTY 到達前のライブラリ側の取り落としとして再現できる。

### 再現と呼び出し順の計測

製品コードの修正前に `GhosttyEmbeddingTests.commitOutsideKeyDown` を追加した。`setMarkedText("n")` → `"に"` → `"にほんご"` → `"日本語"` → 必要なら `setMarkedText("")` → `insertText("日本語", replacementRange: {0,3})` → `unmarkText` を2回繰り返す。1回目は String、2回目は NSAttributedString。イベントの有無×空の更新の有無の4ケースを、bracketed paste 有効の実 surface で検査した。

- 修正前・イベントなし：各確定後の送信は0バイト。空の更新を挟まない場合、`insertText` 直後も `hasMarkedText == true`・markedRange `{0,3}`。再現テストは終了コード1、1テスト（4ケース）、18個の検査失敗。
- 修正前・イベントあり：`ESC[200~日本語ESC[201~`（21バイト）を1回ずつ送った。確定文字を貼り付けにしていることも検出した。
- 修正後：一時的に上流の公開 `TerminalDebugLog` の `.ime` / `.input` とテストの呼び出しログを有効化。`preedit="n"` → `"に"` → `"にほんご"` → `"日本語"` → `preedit=""` → `host <- direct input bytes=9 utf8="日本語"` の順を4ケースとも観測した。各確定は9バイトを1回、2回合計18バイト。空の更新を先に受けるケースでも同じ。計測を有効化するコード・一時ログは最終ソースから削除した。
- キー処理内：`interpretKeyEvents` の応答だけを台本化し、実際の `UserTerminalView` のキー処理を通す。Return で確定し、空の更新の有無の2ケースとも2回分の「日本」だけが届き、余分な Return やホスト直送は発生しなかった。
- 実 PTY：画面外の同じ coordinator を PTYKit の実 zsh / vim と接続。イベントなしの確定を2回行い、各回の日本語送信が1回であることと、シェルの結果 `IME1:日本語` / `IME2:日本語` を確認した。2回目は空の更新を先に送った。

この計測は入力メソッドの応答を台本化したテストであり、**実アプリの入力メソッドのコールバック順序を採取したものではない**。実アプリの起動禁止に従い、実入力メソッドのトレースと修正後の下部パネルでの再確認は未実施。今回再現できた欠落・未確定状態の残留が実機の重複・行崩れも説明するかは、再確認まで未確定とする。

### 修正と検証範囲

試作時の ADR 0213（dev には無い: `0213-ghostty-ime-commit-outside-keydown.md`） に従い、キー処理外の `insertText` を公開 `unmarkText` → `InMemoryTerminalSession.sendInput` へ接続した。キー処理内は既存の文字収集に委任し二重送信を防ぐ。キー処理外の確定は Ghostty のキー符号化を通さず、UTF-8 をそのままホストへ渡す。この範囲は公開 API で修正でき、依存ソース・Ghostty/Zig・PTYKit は変更していない。操作部品・文言の追加はないため DesignSystem と日英文言の追加は対象外。

作業中のコマンド（いずれも `SWIFT_TEST_OUTPUT=full`、指定ラッパー経由）：

| label | SWIFT_TEST_FILTER / package | 終了コード・結果 |
|---|---|---|
| `ghostty-ime-reproduce` | `GhosttyEmbeddingTests.commitOutsideKeyDown` / GhosttyTerminalUI | 1、1テスト（4ケース）、18個の検査失敗。修正前の欠落・状態残留・貼り付け化を検出 |
| `ghostty-ime-fixed` | `GhosttyEmbeddingTests.commitOutsideKeyDown\|GhosttyEmbeddingTests.compositionThroughKeyDown\|GhosttyEmbeddingTests.realPTY` / GhosttyTerminalUI | 0、3テスト成功（パラメータ付きは各4・2ケース）。API呼び出し順・実PTYの2回の確定を計測 |

独立した lint・型チェック・静的解析は、対象の Package.swift・project.yml・macos/scripts・設定ファイル検索で該当設定が見つからず未設定。コンパイル・リンクは SwiftPM と指定のアプリビルドで検査する。XCUITest と実アプリの起動・終了は行わない。

### 最後の全件検査と失敗の切り分け

全件と画像取得は同じ1回のバッチで行った。GhosttyTerminalUI は6テスト中1件失敗、TerminalUI は92件成功、DashboardFeature は本体2,073件＋実git35件成功。コマンド全体の終了コードは1であり、全件成功とは扱わない。

失敗は既存 `realPTY` の vim 終了時。ログで `Ghostty → PTY: ":q!\\r"` → `Ghostty → PTY: "\\u{1B}"` の順を観測し、文字列が挿入されたままプロンプト待ちで `GhosttyTimeout()` になった。`sendKey(.escape)` は Ghostty のI/O、`session.sendInput` はホスト直送であり、呼び出し順が到着順になる保証はない。Escape後、同じ5秒上限の既存 `waitUntil` で `-- INSERT --` の消失を確認してから終了コマンドを送るよう試験の同期を修正した。期待値や検査対象を減らす変更ではない。

その後は失敗した `realPTY` だけを再実行し、終了コード0、1件成功。日本語の確定は各回1回、`IME1:日本語` / `IME2:日本語` の結果を再確認した。全件と画像取得は繰り返していない。製品コードは全件検査後に変更していない。

```sh
# 修正前の再現（終了コード1、1テスト・4ケース、18個の検査失敗）
SWIFT_TEST_FILTER='GhosttyEmbeddingTests.commitOutsideKeyDown' SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-ime-reproduce \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI

# 修正後の関連検査（終了コード0、3テスト成功）
SWIFT_TEST_FILTER='GhosttyEmbeddingTests.commitOutsideKeyDown|GhosttyEmbeddingTests.compositionThroughKeyDown|GhosttyEmbeddingTests.realPTY' SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-ime-fixed \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI

# 全件＋画像はこの1回（終了コード1、上記のvim終了順序で1件失敗）
GHOSTTY_EVIDENCE_DIR="$PWD/macos/.build/ghostty-ime-fix" SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-ime-final \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI TerminalUI DashboardFeature \
  > macos/.build/ghostty-ime-fix/final-tests.log 2>&1

# vimのモード遷移を待つよう試験を修正後、失敗した検査だけ再実行（終了コード0、1件成功）
SWIFT_TEST_FILTER='GhosttyEmbeddingTests.realPTY' SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-ime-pty-order \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI \
  > macos/.build/ghostty-ime-fix/pty-order-tests.log 2>&1
```

画像は12枚保存し、そのうち以下の3枚を目視確認した。1・2回目の未確定表示はいずれも「日本語」1組で下線あり。確定後は文字と下線が消えている。この試験はシェルのエコーを返さず未確定表示だけを分離しており、確定後の画像が空でもシェルへの送信欠落を意味しない（送信は各回9バイトを検査）。実PTYの最後の画像は、上記の失敗で取得箇所に到達しなかった。画像取得は再実行していない。

- 1回目の未確定表示（試作時: `macos/.build/ghostty-ime-fix/ime-marked-round-1.png`）
- 2回目の未確定表示（試作時: `macos/.build/ghostty-ime-fix/ime-marked-round-2.png`）
- 確定後（イベントなし・空の更新なし）（試作時: `macos/.build/ghostty-ime-fix/ime-committed-event-false-empty-false.png`）
- 全件ログ（試作時: `macos/.build/ghostty-ime-fix/final-tests.log`）、失敗した検査の再実行ログ（試作時: `macos/.build/ghostty-ime-fix/pty-order-tests.log`）

全件検査の診断：色空間の `Unrecognized colorspace number -1` / `Unknown number of components for colorspace model -1` が各4件。既存の削除失敗・保護の試験から、workspace削除の `Permission denied` 1件と、未コミットworktree・未マージbranchを削除しない `Failed to cleanup` が各1件出た。該当テストは成功しており、製品の正常動作時に警告が出ないと主張するものではない。

### Debug ビルド

macos を作業ディレクトリにして、以下を順番に各1回実行した。双方とも終了コード0、`BUILD SUCCEEDED`。アプリは起動・終了していない。

```sh
/opt/homebrew/bin/xcodegen generate > .build/ghostty-ime-fix/xcodegen.log 2>&1
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGhosttyBuild build \
  > .build/ghostty-ime-fix/debug-build.log 2>&1
```

xcodegenログ（試作時: `macos/.build/ghostty-ime-fix/xcodegen.log`）、Debugビルドログ（試作時: `macos/.build/ghostty-ime-fix/debug-build.log`）。AppIntents.framework 依存がないためメタデータ抽出を省く警告が2件。ad-hoc署名でhardened runtimeを無効にするnoteと、LaunchServices再登録フェーズを毎回実行するnoteも出た。今回のビルドログに Swift のコンパイル警告はなかった。

残る未確認範囲は実アプリのIMEコールバック順序と、修正後の実入力メソッドでの確定・全角幅・プロンプトの表示。条件3全体の成立と本採用は宣言しない。

## 実アプリ評価への接続（2026-10-15）

以下の再計測は過去の記録。設定を追加しないという判断は 試作時の ADR 0212（dev には無い: `0212-ghostty-engine-setting-for-ime-evaluation.md`） で置き換え、一般設定の「ターミナルの表示エンジン」から選択する。新しく作る下部パネル・ターミナル子タブだけに反映し、既存端末はアプリ再起動が必要。パネルの開閉とシェルの再起動は表示器を保持する。

接続対象は出力、キー入力・貼り付け、リサイズ、入力先の取得解除と移動、文字サイズ、背景・前景・ANSI 16色。未接続は Ghostty の VoiceOver 可視テキスト、エージェントの画面抽出・自動応答・モバイル転送。後続の統括役の実機確認では未確定文字・候補窓の位置は合格し、確定の欠落と重複が発生した。修正と未確認範囲は上記の日本語確定の節を参照。表示器の識別子は `ghostty-user-terminal`、設定は `settings-terminal-engine`。

Ghostty が確認を求めるクリップボード操作（保護対象の貼り付けや OSC 52 など）の確認画面は未接続。`TerminalSurfaceClipboardConfirmationDelegate` を実装しないホストでは、固定版はその操作を拒否する（`TerminalController+Callbacks.swift` と delegate 定義をソースで確認）。通常の貼り付け経路と、公開 `paste(text:)` による bracketed paste は利用する。保護を無効化する設定は足さない。システムのクリップボードを使った実アプリ操作は未検証。

### 設定接続後の最終検証

変更した3パッケージの全件は最後に1回実行し、終了コード0。GhosttyTerminalUI 5件、TerminalUI 92件、DashboardFeature 本体2,073件＋実git35件（合計2,108件）が成功した。XCUITest と実アプリの起動・終了は実行していない。PTYKit のソースは今回変更していない。独立した lint・型チェック・静的解析の設定は対象の Package.swift・project.yml・検証スクリプトに見当たらず未設定。Swift のコンパイル・リンクはテストとアプリビルドで確認した。

全件と同じ1回のバッチで画像6枚を取得した。`controls-light.png` の背景・文字、`shell-color.png` の暗い背景・ANSI文字色、`composition-marked.png` の「にほん」と下線を目視確認した。**今回は直接の `setMarkedText` による未確定文字が画面外画像に描画された。** 前回との差が生じた理由は未特定で、実入力メソッドの通常経路・候補選択の成功は依然未検証。この結果を実アプリでの条件3の成立と読み替えない。追加の画像取得はしていない。

- 今回の未確定文字（試作時: `macos/.build/ghostty-engine-setting/composition-marked.png`）：SHA-256 `a4706e55640cf2008c438085b1c752b65d612081fca34a00f8e75e59c06db173`
- 未確定設定前（試作時: `macos/.build/ghostty-engine-setting/composition-before.png`）：SHA-256 `9d2be8f9177adbd772f46660303e0d54a86645647d41e129a0df22ed4f82af0c`
- 文字サイズ・明るい配色（試作時: `macos/.build/ghostty-engine-setting/controls-light.png`）
- 最終テストログ（試作時: `macos/.build/ghostty-engine-setting/final-tests.log`）、Debugビルドログ（試作時: `macos/.build/ghostty-engine-setting/debug-build.log`）

テストコマンドの共通形は `SWIFT_TEST_FILTER='<filter>' SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full <label> macos/scripts/run-swift-tests.sh <packages>`。最初の2回だけは `SWIFT_TEST_OUTPUT` と `--full` を付けずに実行した。下表はこの設定接続作業の履歴で、以前の評価履歴とは別。

| label | packages / filter | 終了コード・件数・結果 |
|---|---|---|
| `ghostty-engine-controls` | GhosttyTerminalUI / `GhosttyUserTerminalTests` | 0、1件成功。後に既存の直列スイートへ移し、テスト間の配色変更の干渉を防止 |
| `ghostty-dashboard-connection` | DashboardFeature / `UserTerminalEngineSettingsTests\|TerminalPanelViewWhiteboxTests\|BottomPanelTests\|SimulatorHubTests` | 1、コンパイル失敗で0件。既存画像テストの変数を型確認付きに変えた際、別のスコープの参照まで変えていたため訂正 |
| `ghostty-dashboard-diagnostics` | DashboardFeature / **指定漏れ** | 1、同じコンパイル失敗で0件。診断用の再実行で絞り込みを漏らした。全件テストは実行に至っていない |
| `ghostty-dashboard-connection-fixed` | DashboardFeature / 上記と同じ | 1、30件中2件失敗。検査用の表示先を先に作ったための所有権競合と、実ビューと検査用サイズ通知の競合 |
| `ghostty-dashboard-failures` | DashboardFeature / `TerminalPanelViewWhiteboxTests\|UserTerminalEngineSettingsTests` | 1、4件中1件失敗。表示先の生成順は訂正し成功。失敗位置を付けてサイズ通知の競合を特定 |
| `ghostty-engine-precheck` | GhosttyTerminalUI DashboardFeature / `TerminalPanelViewWhiteboxTests\|UserTerminalEngineSettingsTests\|GhosttyEmbeddingTests.controls` | 1、Ghostty は画像保存コードの入れ子の `#require` マクロでコンパイル失敗、0件。Dashboard は4件成功。マクロを2文に分離して修正 |
| `ghostty-engine-ready` | GhosttyTerminalUI TerminalUI DashboardFeature / `GhosttyEmbeddingTests.controls\|TerminalMount\|BottomPanel\|UserTerminalEngineSettingsTests\|TerminalPanelViewWhiteboxTests\|SimulatorHubTests` | 0、順に1件・22件・30件成功 |
| `ghostty-engine-final` | GhosttyTerminalUI TerminalUI DashboardFeature / filterなし | 0、5件・92件・2,073件＋実git35件成功。画像6枚もこの回だけ取得 |

サイズ通知の検査は mount 前に行い、同じ58列40行の期待を維持した。実ビューのサイズ通知は Ghostty の controls で別に検査する。待機時間の延長、skip、期待値の実出力への追従は行っていない。

```sh
GHOSTTY_EVIDENCE_DIR="$PWD/macos/.build/ghostty-engine-setting" SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-engine-final \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI TerminalUI DashboardFeature

# macos を作業ディレクトリにして、各1回だけ実行（双方とも終了コード0）
/opt/homebrew/bin/xcodegen generate
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGhosttyBuild build

git diff --check
```

警告：最終テストでは色空間の診断 `Unrecognized colorspace number -1` と `Unknown number of components for colorspace model -1` が各4件。実gitの既存2テストは、未コミット・未マージの状態を安全に削除しない検査として `Failed to cleanup` を各1件出した（両件成功）。アプリビルドは既存の非Sendableクロージャ警告2件、`String(cString:)` 非推奨1件、AppIntents依存がなくメタデータ抽出を省く警告2件。途中の失敗したコンパイルでは既存テストのAX API非推奨、戻り値未使用、不要な `try` の警告も観測した。警告なしとは報告しない。

### 統括役の実アプリ確認手順

1. この変更を含むアプリの「設定 → 一般 → ターミナル → ターミナルの表示エンジン」で Ghostty を選ぶ（設定の識別子 `settings-terminal-engine`）。
2. 初めて開くプロジェクトの下部パネル、または新しいターミナル子タブで確認する。既に作成済みの下部パネルは開閉や見出しの「再起動」では切り替わらないため、アプリを再起動してから開く。表示器の識別子は `ghostty-user-terminal`。
3. 既存の日本語入力メソッドで未確定文字の表示・変換候補・確定文字の到達・全角幅を確認する。入力ソースの追加は不要。⌘Jでの入力先移動、見出しの強調、⌘+／⌘−、設定の文字サイズと配色、貼り付け、vimのリサイズも確認対象。これらの実アプリ操作は今回未実施。

## 再計測（2026-10-15）

**当初の推定は誤りだった。** 「PTYKit では制御端末がないため SIGWINCH が届かない」と一律には言えない。同じ `.interactive` の既存起動経路で bash と zsh の結果が異なることを、Ghostty を介さない前景 probe で確認した。

| 計測 | 修正前の結果 | 修正後の結果 |
|---|---|---|
| 対話 bash → 前景の別 bash | PID=54100、PGID=TPGID=54100、`PROBE_WINCH 17 74` を受信 | 縮小 `17 74`・拡大 `31 98` の受信、Ctrl-C の `PROBE_INT` を確認 |
| 対話 zsh → 同じ前景 probe | PID=54116、PGID=54115、TPGID=0、5秒以内に WINCH 出力なし。master は74列17行 | PID=66302、PGID=TPGID=66302、`PROBE_WINCH 17 74`・`PROBE_WINCH 31 98`・`PROBE_INT` を確認 |
| Ghostty の resize callback → PTY | 93列26行 → 74列17行は届いていた | 同じ値を維持 |
| Ghostty 内部の行列 | 初回は直接照合せず | 公開 `TerminalSurfaceGridResizeDelegate` で74列17行、master の `TIOCGWINSZ` と一致 |
| vim の縮小後の出力 | 本文の再描画出力なし、5秒で失敗 | 1,299 bytes の再描画出力に本文を含み、約47〜52 msで画面の本文が復帰。拡大後も新しい出力と本文を確認 |

probe は前景の別プロセスで `trap 'printf "PROBE_WINCH "; stty size' WINCH` を登録し、`read` 待ちをする。シェル PID へだけ送った信号ではこの期待を満たせない。PTY master の winsize と、受信側の `stty size`（slave の ioctl）が一致する。修正後は `.interactive` からの明示 `kill(SIGWINCH)` を外しても受信した。これにより kernel の前景への通知を、shell の明示通知と区別できた。

根本原因は Phlox の起動が `SETSID` と fd の複製だけで、制御端末の取得をシェルに依存させていたこと。zsh の観測結果を bash を含む対話シェル一般へ拡大した初回説明を撤回する。slave を spawn の file action で再 open する試験は、bash 成功・zsh 失敗のまま改善しなかったため採用していない。採用する修正は [ADR 0201](../adr/0201-interactive-pty-controlling-terminal.md) の `.interactive` 限定の C 起動処理。`.raw` の `posix_spawn` と明示 SIGWINCH は残し、その受信も回帰テストで確認した。Ghostty の改造と Zig ビルドは行っていない。

待機は、PTY のサイズだけでなく、Ghostty の行列、新たな PTY 出力に本文が含まれること、`waitForPendingOutput` による解析完了、可視本文の復帰を確認する。待ち時間の延長で成功させたものではない（上限5秒を維持）。さらに初回テストの vim 終了処理に、`paste(":q!")` が bracketed paste として normal mode から挿入に戻す問題があった。コマンドは公開 `sendInput` でキー相当のバイトを送り、シェルのプロンプトへの復帰を待つように直した。本文保持・日本語の期待は緩めていない。

### 条件1〜3の再判定

| 条件 | 再計測の状態 |
|---|---|
| 1 組み込み | `project.yml` にローカルパッケージを追加し、xcodegen・Debug ビルド成功（各1回、終了コード0）。Phlox の LinkFileList に `GhosttyTerminalUI.o`・`GhosttyKit.o` を確認。最低 macOS・MIT 表記の初回検査は下記参照、同梱第三者資産の全件ライセンス監査は未実施 |
| 2 入出力 | プロンプト、実 PTY の入力、赤色文字、vim の縮小・拡大後の本文保持を確認。縮小後の画面外画像でも本文と挿入状態を確認 |
| 3 日本語 | 未確定状態・確定「日本」の実 PTY 出力、全角4文字の8列占有を確認。**未確定文字の描画は確認できず**。前後の画面外画像の SHA-256 が一致し、画像には「にほん」がない |

全角幅は `Ａ日本Ｂ` の後の DSR 返信が `ESC[1;9R` であることをテストし、画像でも確認した。未確定画像とその直前の画像の SHA-256 は共に `a32df5b53bec6cfb1bf321a0f52dbdf9b6f2250d4c4d372670769e71760d874c`。API の状態検査が通ることを、描画成功へ読み替えない。直接の `setMarkedText` は `syncPreedit` を呼び、通常の `keyDown` は `interpretKeyEvents` の後に同じ処理を呼ぶことまで固定版ソースで確認した。画像取得の制約内では、描画不達と画面外キャプチャの制約をまだ区別できていない。OS の日本語入力ソースや候補選択の実操作は未検証。

証拠： 信号とリサイズのログ（試作時: `macos/.build/ghostty-spike-preflight/signal-resize-proof.log`）、縮小後の vim（試作時: `macos/.build/ghostty-spike-preflight/vim-shrunk.png`）、赤色の出力（試作時: `macos/.build/ghostty-spike-preflight/shell-color.png`）、未確定状態の画像（試作時: `macos/.build/ghostty-spike-preflight/composition-marked.png`）、その直前（試作時: `macos/.build/ghostty-spike-preflight/composition-before.png`）、全角幅（試作時: `macos/.build/ghostty-spike-preflight/full-width.png`）。

**再判定は declined。条件2による打ち切りは撤回し、条件3の描画を実証できないため本実装を保留する。** 固定版の `setMarkedText` は直接呼び出しても `syncPreedit` へ到達する。さらに通常の公開 `keyDown` → `interpretKeyEvents` 経路を通す `compositionThroughKeyDown` を追加し、未確定の間は PTY 向けバイトを出さず、確定後に「日本」を送ることを検査した（終了コード0、1件成功）。入力メソッドからの応答だけをテスト用ビューで台本化し、Ghostty のキー処理自体は実物を使う。この追加テストでは画像を取得しておらず、描画の成功とは数えない。追加画像の取得はユーザーの「最後に1回だけ」という制約により承認待ち。設定・アプリ切り替え・ja/en 文言は条件1〜3がそろわないため追加しない。

### 再計測のコマンドと結果

すべて指定作業ツリーで実行。テストは `SWIFT_TEST_FILTER="<filter>" ~/.agents/scripts/compact-test <label> macos/scripts/run-swift-tests.sh <package>` の形で実行した。詳細ログを残す回は `SWIFT_TEST_OUTPUT=full` とラッパーの `--full` を使用した。以下は初回評価と分けた、この再計測分の履歴。

| label | package / filter | 終了コード・件数・結果 |
|---|---|---|
| `ghostty-foreground-signal` | GhosttyTerminalUI / `GhosttyEmbeddingTests.foregroundResizeSignal` | 1、1テスト2ケース中 bash 成功・zsh 失敗（受信待ち5秒） |
| `ghostty-foreground-reopen` | 同上 | 1、同じ失敗。slave 再 open の試験は採用せず |
| `ghostty-foreground-ctty` | 同上 | 0、1テスト2ケース成功。制御端末の確立で改善 |
| `ghostty-vim-ctty` | GhosttyTerminalUI / `GhosttyEmbeddingTests.realPTY` | 1、1件失敗。リサイズは成功、終了コマンドの bracketed paste で挿入状態へ戻っていた |
| `ghostty-resize-ime` | GhosttyTerminalUI / `GhosttyEmbeddingTests.realPTY\|GhosttyEmbeddingTests.outputAndComposition` | 0、2件成功 |
| `ghostty-pty-contract` | PTYKit / `InteractiveSpawnTests\|PTYTerminalModeTests\|PosixSpawnCloexecTests\|PTYManagerResize` | 1、新規テストの spawn 引数 `id`・`initialSize` 不足でコンパイル失敗。実行件数0 |
| `ghostty-pty-contract-fixed` | 同上 | 0、8件成功。必要な引数を明示して修正 |
| `ghostty-signal-resize-proof` | GhosttyTerminalUI / `GhosttyEmbeddingTests.foregroundResizeSignal\|GhosttyEmbeddingTests.realPTY` | 0、2件成功。縮小・拡大・Ctrl-C・新出力待機を検査 |
| `ghostty-width-final-precheck` | GhosttyTerminalUI / `GhosttyEmbeddingTests.outputAndComposition` | 0、1件成功 |
| `ghostty-pty-raw-regression` | PTYKit / `InteractiveSpawnTests` | 0、3テスト（5ケース）成功。raw の SIGWINCH 受信を追加 |
| `ghostty-reassessment-final` | GhosttyTerminalUI PTYKit DashboardFeature / filter なし | 0、Ghostty 3件・PTY 41件・Dashboard 本体2,070件＋実git35件成功。全件の呼び出しはこの1回。画像5枚もこの回だけで取得 |
| `ghostty-keydown-composition` | GhosttyTerminalUI / `GhosttyEmbeddingTests.compositionThroughKeyDown` | 0、追加テスト1件成功（全件実行後のテスト追加に対する絞り込み）。画像は未取得 |

```sh
GHOSTTY_EVIDENCE_DIR="$PWD/macos/.build/ghostty-spike-preflight" SWIFT_TEST_OUTPUT=full \
  ~/.agents/scripts/compact-test --full ghostty-reassessment-final \
  macos/scripts/run-swift-tests.sh GhosttyTerminalUI PTYKit DashboardFeature

# macos を作業ディレクトリにして各1回実行
/opt/homebrew/bin/xcodegen generate
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGhosttyBuild build

# 手元だけの C 静的解析（テストには未登録）
xcrun clang --analyze -Wall -Wextra -I macos/Packages/PTYKit/Sources/CPTYHelpers/include \
  macos/Packages/PTYKit/Sources/CPTYHelpers/interactive_spawn.c \
  -o macos/.build/ghostty-spike-preflight/interactive-spawn-analysis.plist
git diff --check
```

xcodegen・xcodebuild・C 静的解析・diff 検査はいずれも終了コード0。C の診断は0件。独立した lint・型チェック設定は見つからず未設定（Swift のコンパイルはテストとアプリビルドで実行）。Dashboard の正本スクリプトは実gitの3スイートを本体から外して別パスで実行するため、上記の2,105件は両パスの合計であり、テストを省略して green にしたものではない。

警告も残す。Debug ビルドでは既存 `TerminalView.swift:209` の non-Sendable クロージャ警告2件、既存 `Posix.executablePath` の `String(cString:)` 非推奨警告1件、AppIntents 依存がないためメタデータ抽出を省いた警告2件を記録。Dashboard のテストでは `Unrecognized colorspace number -1` / `Unknown number of components for colorspace model -1` が各4件。また、変更済み worktree と未マージブランチを削除しないことを検査する既存の2テストが、意図した `Failed to cleanup` 警告を各1件出した（両テスト成功）。対象ソースとログを照合しており、これらを警告なしとは報告しない。

追加・変更したテストは `GhosttyEmbeddingTests`（前景信号、内部行列との照合、縮小・拡大後の新出力と本文、全角DSR、通常keyDown）と `InteractiveSpawnTests`（raw通知、cwd・環境・fd非継承、exec/cwd失敗）。製品コードの動作変更は全件実行前に完了し、その後は追加のkeyDownテストと、古いコメント・資料の訂正だけを行った。XCUITest、アプリ起動、動作中のアプリ終了、入力ソース変更、`.env*` の操作、Git の commit/stash/reset/checkout/merge/rebase は行っていない。

- 最終全件ログ（試作時: `macos/.build/ghostty-spike-preflight/reassessment-final-tests.log`）
- 追加keyDown検査ログ（試作時: `macos/.build/ghostty-spike-preflight/keydown-composition.log`）
- Debugビルドログ（試作時: `macos/.build/ghostty-spike-preflight/reassessment-debug-build.log`）
- C静的解析（試作時: `macos/.build/ghostty-spike-preflight/interactive-spawn-analysis.plist`）

## 初回評価の記録（以下の原因推定は撤回済み）

試作時の ADR 0211（dev には無い） の条件2で打ち切り。現行の PTYKit と実 zsh の子として起動した vim を接続すると、縮小後に本文が表示範囲から消え、再描画されない。Ghostty 本体の不具合と断定する結果ではない。アプリ・設定への統合はしていない。

## 固定版と配布物

- パッケージ：`2.2.2026101301`、リビジョン `d403978c66870baa422709d1dde385730a4bdaef`。DisplayLink `3.0.1` も `Package.resolved` に記録。
- [README](https://github.com/Lakr233/libghostty-spm/blob/d403978c66870baa422709d1dde385730a4bdaef/README.md)、[Package.swift](https://github.com/Lakr233/libghostty-spm/blob/d403978c66870baa422709d1dde385730a4bdaef/Package.swift)、[LICENSE](https://github.com/Lakr233/libghostty-spm/blob/d403978c66870baa422709d1dde385730a4bdaef/LICENSE)を確認。Swift 6.2、宣言上 macOS 13以上、MIT。README はバイナリ本体・独自シェル連携も MIT と説明している。同梱する第三者資産のライセンス全件監査までは未実施。
- バイナリ：[upstream.1e9e14af5df1-2](https://github.com/Lakr233/libghostty-spm/releases/tag/upstream.1e9e14af5df1-2) の `GhosttyKit.xcframework.zip`（77,433,219 bytes）。SHA-256 `188b21d3c3f4f0a19fd71d7f3e6c6edc0e8e30fe04e09181d3db44810e21bf5f` が manifest と一致。
- `xcrun otool -l` で macOS universal 静的ライブラリを検査：`platform 1` / `minos 13.0` が各332件。コマンドの終了コード0。macOS 14 実機での起動は未検証。
- Zig はインストールも実行もしていない。取得と展開は作業ツリー内の `macos/.build/ghostty-spike-preflight` に限定した。

## 打ち切り条件

| 条件 | 判定 | 実行・観測した範囲 |
|---|---|---|
| 1 組み込み | 未確認 | SwiftPM テストのビルド・リンク・実行は成功。最低 macOS 13.0 と MIT 表記を確認。条件2で停止したため xcodegen とアプリ Debug ビルドは未実行 |
| 2 入出力 | 満たさない | 実 zsh のプロンプト、ANSI 色付き printf の文字、vim の初期画面・挿入文字、入力バイト・サイズ通知は取得。縮小後の vim 本文保持で失敗。色の画素検査と `ls -G` は未実施 |
| 3 日本語入力 | 未確認 | `setMarkedText` / `attributedSubstring` で「にほん」の未確定状態、`insertText` で「日本」のホストへの送出を検査。描画、実 PTY 到達、全角幅は未検証 |

## 再現と原因の範囲

`GhosttyTerminalCoordinator` は `InMemoryTerminalSession` の `write` / `resize` をホストへ返し、`receive(Data)` で外部出力を受けるだけ。実 PTY はテスト側の `PTYManager(terminalMode: .interactive)` が所有する。アプリの `UserTerminalController` は変更していない。

画面外ウィンドウに `AppTerminalView` を置き、zsh を `-f -i`、vim を `-N -u NONE -i NONE -n` で起動する。vim の挿入モードへの遷移を待って `VIM_FULL_SCREEN` を貼り付け、API の表示文字に含まれることを確認してからビューを800×500から640×320へ縮小する。

最終ログは `Ghostty → PTY resize: 93x26` → `74x17` と `PTY size: Optional((cols: 74, rows: 17))` を記録。サイズ変更後には vim の再描画出力が届かず、Ghostty の表示文字は `~` の行と `-- INSERT --` になり、本文の再出現待ちが5秒で失敗した。画面外画像でも同じ欠落を確認した。

現行 `PTYKit/PTYManager.swift` の `resize` は `Posix.resize` の後に `Darwin.kill(session.pid, SIGWINCH)` を呼ぶ。`Posix.swift` の spawn は制御端末を確立せず、OSによる前景プロセスグループへの自動通知は働かない。zsh の子である vim に通知が届かない構造が観測と一致する。信号受信のトレースは行っておらず、原因の判断はこのコードと入出力ログからの推定である。PTYKit の修正・信号の追加送信などの回避は行っていない。

初期の診断では vi 互換モードとモード遷移待機不足も検出した。vim の非互換モードを明示し、挿入状態と実 PTY のサイズを待つ形に修正した後も、上記のリサイズ失敗を再現した。期待値の緩和・テストの削除・skip はしていない。

## API の対応表

API の存在確認と、Phlox への実装を区別する。下記のうち設定・操作部品は追加していない。

| 既存の用途 | Ghostty 側 | 今回の到達点 |
|---|---|---|
| 出力 feed | `InMemoryTerminalSession.receive(Data)` | 実装・表示文字の読み取り検査済み |
| キー入力・貼り付け | `AppTerminalView.sendKey` / `paste` → `write` | 実 PTY で Return・挿入開始・貼り付けを検査済み |
| リサイズ | `InMemoryTerminalSession` の `resize` | 通知・PTY サイズ変更まで検査済み、vim 再描画は失敗 |
| 入力先通知 | `TerminalSurfaceFocusDelegate` | API 確認のみ、Phlox へ未接続 |
| 入力先の移動 | `acquireProgrammaticFocus` | API 確認のみ。テストでは NSWindow の `makeFirstResponder` を使用 |
| 文字サイズ | `TerminalController.setTerminalConfiguration` / `set_font_size` | API 確認のみ、共通の文字サイズ設定へ未接続 |
| 配色 | `TerminalController.setTheme` / `TerminalConfiguration.palette` | API 確認のみ、Phlox 配色へ未接続 |
| 可視テキストのアクセシビリティ | `readViewportText` | 表示文字の取得は検査済み。VoiceOver の値への公開は未実装 |
| 単一表示器の再アタッチ | AppKit ビューの再配置 | Phlox の mount 所有権への接続・再アタッチ検査は未実装 |

固定版の公開 API に上記の基本機能が明らかに欠けているものは見つからなかった。ただし Phlox と同じ動作を用意できると実証した範囲は表の検査済み項目だけ。`snapshotImage` は AppKit の Metal キャプチャを best-effort と明記しているが、今回の失敗画像は取得できた。

## 検証コマンドと証拠

作業場所は `feature/ghostty-spike` の指定ツリー。リポジトリ直下の `AGENTS.md` は存在せず、提示された規約と `macos/docs/README.md` に従った。

```sh
SWIFT_TEST_FILTER="GhosttyEmbeddingTests" ~/.agents/scripts/compact-test ghostty-embedding macos/scripts/run-swift-tests.sh GhosttyTerminalUI
SWIFT_TEST_FILTER="GhosttyEmbeddingTests.realPTY" ~/.agents/scripts/compact-test <診断ラベル> macos/scripts/run-swift-tests.sh GhosttyTerminalUI
GHOSTTY_FAILURE_IMAGE="$PWD/macos/.build/ghostty-spike-preflight/vim-resize-failure.png" ~/.agents/scripts/compact-test ghostty-final macos/scripts/run-swift-tests.sh GhosttyTerminalUI
```

| 実行 | 結果 |
|---|---|
| 初回絞り込み `ghostty-embedding` | 終了コード0、1件成功（実 PTY テスト追加前） |
| 実 PTY 絞り込み7回 | 各終了コード1、各1件失敗。ラベルは `ghostty-real-pty`、`ghostty-real-pty-diagnosis`、`ghostty-pty-bytes`、`ghostty-vim-diagnosis`、`ghostty-vim-insert-mode`、`ghostty-pty-state-transitions`、`ghostty-resize-diagnosis` |
| 最後の全件 `ghostty-final`（1回） | 終了コード1、2件中1件成功・1件失敗。Swift Testing の失敗は `GhosttyTimeout()`。XCTest の「0件成功」は Swift Testing の合格を意味しない |
| `git diff --check` | 終了コード0（資料の最終更新後にも再実行） |
| lint・独立した型チェック／静的解析 | 新パッケージ向け設定は見つからず未設定。テストの Swift コンパイルは実行済み |
| xcodegen / アプリ Debug ビルド | 打ち切りにより未実行 |

`run-swift-tests.sh` は任意のパッケージ名を引数で扱えるため変更不要。XCUITest・アプリ起動・既存アプリの終了・入力ソース設定変更は行っていない。テスト自身が作った PTY の終了処理は成功・失敗の両方で `terminateAllAndWait` を呼ぶ。

- 最終テストログ（試作時: `macos/.build/ghostty-spike-preflight/final-tests.log`）
- リサイズ失敗時の画面外画像（試作時: `macos/.build/ghostty-spike-preflight/vim-resize-failure.png`）
- 配布バイナリのロードコマンド（試作時: `macos/.build/ghostty-spike-preflight/load-commands.txt`）

証拠ファイルは作業ツリーの無視対象の `.build` にあり、Git の追跡対象ではない。再現テストはパッケージ内に残してある。設定・ja/en 文言・アプリ側接続・表示器の切り替え・UserTerminalController 経由の統合は打ち切りにより未実装。PTY の通知経路、未確認の条件1・3は未解決。

## 診断用の記録の取り方

2026-10-15: 原因の調査が終わったため、PHLOX_IME_TRACE と Logger の Phlox.IME による診断記録はコードから外した。以前の有効化手順は利用できない。入力処理は変更していない。

## 試作時の採用と日本語入力試験の訂正（2026-10-15）

ユーザー提供の調査結果：CGEvent.postToPid による合成キー試験は SwiftTerm に当てても同じ形で確定文字の消失・重複となった。Phlox の境界記録で取りこぼし・二重送信は0回。人が実キーボードで打ったライブ変換・Spaceによる候補選択の確定は、計8回すべて1回ずつ届いた。従来の合成キー試験の失敗を Ghostty 固有の不具合とする評価を訂正する。

記録の生データは残していない。以下はその要点。本文の過去の「実機未確認」「打ち切り」「未実装」は各試行時点の記録で、当時の採用判断は試作時の ADR 0215（dev には無い）と、試作ツリーの architecture/terminal-editor-panels.md に記録されていた。最終の見送り判断は本資料冒頭を参照する。

外部調査報告によれば本家も確定文字を keycode 0・PRESS のみで送る。RELEASE は追加しない。入力ソースが keyDown 内で変わったときの収集文字破棄は理論上あり得る取りこぼしだが、実測0回で上流にもあるため今回は維持する。

試作内での採用は試作時の ADR 0211・0215（いずれも dev には無い）で記録し、既定は SwiftTerm としていた。有志の libghostty-spm と本家に無い HOST_MANAGED 改造への依存は残る。破損時は設定を SwiftTerm に戻し、既存端末はアプリ再起動で反映する。設定のja/en文言と標準Pickerの操作名、識別子、作成時固定の寿命をコードで確認した。画面の見た目は変更していない。

## 試作時の採用仕上げの検証（2026-10-15）

本作業で変更したコードは UserTerminalView の診断記録除去だけ。入力アルゴリズム、設定画面、共通起動経路は維持した。追加テストは DashboardFeature の UserTerminalEngineSettingsTests.ghosttyInteractiveEnvironment：zsh/bash × LANG既定/指定の4ケースで、GhosttyのNSTextInputClientから入力し、実シェルのLANG出力と `/dev/tty` を開けることを表示器の出力で照合した。入力エコーでは成功しない形にしている。

作業場所の直下に AGENTS.md と karpathy-CLAUDE.md は見つからず、依頼に提示された規約と docs/README.md に従った。

実行コマンド（リポジトリ直下。ただし xcodegen と xcodebuild は macos 内）：

```sh
SWIFT_TEST_FILTER=UserTerminalEngineSettingsTests ~/.agents/scripts/compact-test ghostty-settings-targeted macos/scripts/run-swift-tests.sh DashboardFeature
# package を GhosttyTerminalUI / TerminalUI / PTYKit / DashboardFeature として各1回
SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full "ghostty-adoption-$package" macos/scripts/run-swift-tests.sh "$package"
/opt/homebrew/bin/xcodegen generate
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGhosttyBuild build
git diff --check
```

| 検査 | 終了コード | ランナーの報告件数・結果 |
|---|---|---|
| DashboardFeature 絞り込み | 0 | 4テスト成功（新規の1テストは4ケース） |
| GhosttyTerminalUI 全件・1回 | 0 | Swift Testing 7件 |
| TerminalUI 全件・1回 | 0 | Swift Testing 92件 |
| PTYKit 全件・1回 | 0 | Swift Testing 46件 |
| DashboardFeature 全件・1回 | 0 | Swift Testing 本体2,076件＋実git35件の成功報告。既存条件付きスキップ17件を含む。XCTestは4件中成功3件・既存スキップ1件 |
| xcodegen・1回 | 0 | プロジェクト生成成功 |
| Debugビルド・1回 | 0 | BUILD SUCCEEDED |
| git diff --check | 0 | 差分の空白エラーなし |

Swift Testingの既存スキップは性能測定のフラグ・試料ファイル、PHLOX_E2Eや実CLI等の実行条件による17件。XCTestの1件はPHLOX_SCROLL_PERFORMANCE=1のRelease専用測定。スキップの追加・変更は行っていない。各名称は DashboardFeatureログ（試作時: `macos/.build/ghostty-adoption/DashboardFeature.log`） を参照。

ビルドの警告は5件：TerminalView.swift:209の非Sendableクロージャ引き渡し2件、Posix.swift:198のString(cString:)非推奨1件、AppIntents.framework依存が無いためメタデータ抽出をスキップする警告2件。今回変更していない行であり残存する。テストログの復元失敗（binaryNotFound / unsupportedBackend）とworktree/branch削除拒否は、異常系テストで観測された出力で、該当テストは成功した。

全件検査を起動する直前、zshの読み取り専用変数statusを使ったループ準備が終了コード1で失敗した。テスト開始前の失敗であり、変数名を修正してから上記の各1回を実行した。

対象のローカルMarkdown参照の存在、旧番号の参照・競合マーカー・Swiftコード内の診断記録の残存なしを手元の検索で確認した（テストには未登録）。専用lint・独立した型チェック・静的解析は対象の設定が見つからず未設定。コンパイルとリンクは上記検査で確認した。

設定画面はコード上でja/en・識別子・標準Pickerの操作名と既定値を確認した。見た目を変更していないため画像取得は対象外。VoiceOverの音声操作は未検証。アプリ起動・XCUITest・入力ソースの設定変更は行っていない。手入力8回の検査はユーザー提供の調査結果を採用し、再実施していない。

実行ログは `macos/.build/ghostty-adoption/`（Git管理外）。上記の依存リスク、入力ソース変更時の理論上の取りこぼし、Ghosttyの可視テキストのVoiceOver読み上げ未接続、既存警告は残る。依頼の6項目は、改番と資料更新・起動経路の照合と統合テスト追加・診断記録除去・採用と判断の追記・設定の確認・指定検証を実施した。起動経路と設定UIのコード変更は、既に要件を満たしていたため追加していない。

## 出力経路の取り消し（2026-10-15）

上限・直接配送・配送ゲートは、停止や再起動競合を招いたため取り消した（試作時の ADR 0216（dev には無い））。
実コードを確認すると、SwiftTerm と `.raw` の経路も PTYManager と controller の `.bufferingNewest(2048)` を経由し、超過時は古い要素を破棄する。Ghostty も同じ経路を使い、PTYKit は変更しない。
Ghostty の表示前 Data・処理キューには上限を設けない。30万行で181→最大245MB、応答ありというユーザー提示の過去の実測を受け入れる。今回の再計測ではない。通知駆動 tick・左右修飾キー・全選択・VoiceOver の制限表示・実シェル入力試験は維持する。

取り消し後の検証結果と画像保存の準備漏れによる失敗・再実行は 試作時の ADR 0216（dev には無い: `0216-ghostty-output-backpressure-and-event-driven-tick.md#今回の検証出力経路の取り消し後`） に記録した。実アプリの起動はしていない。
