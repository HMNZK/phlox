---
status: completed
last-verified: 2026-08-04
---

# 0034: ADR 0116 の修正後 再計測（`.appServer` グリッドのカクつき）

## 何をしたか

ADR 0116 の対処1・2・4 を実装した 2026-07-24 以降、**修正後の性能が一度も計測されていなかった**ため、実測して現況値を確定した。結果、対処1・2・4 に測定可能な改善はなく、因果の特定自体が誤っていたと判明したので [ADR-0161](../adr/0161-appserver-grid-jank-root-cause-is-full-transcript-grouping.md) を起こし、[ADR-0116](../adr/0116-agent-grid-swiftui-jank-live-resize-width-freeze.md) を `superseded` にした。

起点は、修正前ベースラインの値（470〜643ms）を現況として引用した誤り。

## 計測環境（再現手順）

課金セッションを使わずに「9 セッションが活発に出力している」条件を作った。

1. **合成ストリーム生成器**を `claude` という名前で用意する。`.appServer` + `claudeCode` は `claude -p --input-format stream-json --output-format stream-json ...` を起動し、stdin/stdout の NDJSON で通信するので、同じ形式を喋るスクリプトで代替できる。
   - 受け口: `ClaudeChatClient+EventParsing.swift`（`type` ディスパッチ）／`ClaudeChatClient+SubAgentContent.swift`（`assistant` → `agentMessageDelta`）／`ChatSessionViewModel` の `enqueueStreamDeltaIfNeeded`（delta はターン未開始でも coalescer へ入る＝ユーザー入力を送らずに負荷をかけられる）
   - 出力: 同一 `message.id` で `content[].text` に**差分だけ**を載せた `assistant` 行を約 40 回/秒。80 回ごとに `result`(success) を出して次の `message.id` へ。
2. **PATH への差し込み**は `ZDOTDIR` を使う。`BinaryPathResolver.resolvePathEnvironment()` が `/bin/zsh -l -c` の PATH を採るため、`$ZDOTDIR/.zlogin` で `PATH=<偽物のディレクトリ>:$PATH` を書き、`open -n --env ZDOTDIR=...` で起動する。`/etc/zprofile` の `path_helper` が PATH を組み直すので `.zshenv` では足りない。
3. **隔離**: `--env PHLOX_DATA_DIR=<フィクスチャ複製> --env PHLOX_DEFAULTS_SUITE=<専用 suite>` で別インスタンスとして起動する。稼働中のリリース版は終了させない。
4. **リサイズは実マウスドラッグで行う。** 対処1 は `NSWindow.willStartLiveResizeNotification` で駆動される（`GridChatColumn.swift:94`）ため、`System Events` でサイズを代入するプログラム的リサイズでは対処1 が一度も作動せず、計測にならない。CGEvent の `LeftMouseDown` → `LeftMouseDragged` 連打 → `LeftMouseUp` を使う。
5. **A/B**: 対処1（`isLiveResizing` を常に false にする）・対処2（`gridTileDefaultLimit` を 40 に戻す）・対処4（`.equatable()` を外す）だけを戻した Release ビルドを別 `derivedDataPath` で作り、同一フィクスチャ複製・同一ウィンドウ寸法で回す。

## 結果

数値は [ADR-0161](../adr/0161-appserver-grid-jank-root-cause-is-full-transcript-grouping.md) の「計測結果」節にまとめた。要点だけ:

- 定常 50 秒でハングが記録時間の **70〜81%** を占める（A: 73〜81% / B: 70〜73%）。メインスレッドは常時飽和。
- **アイドル時のリサイズは A・B とも 0 件**。ADR 0116 が主因としていた「リサイズ毎フレームの CoreText 再 typeset」は再現しなかった。
- 主因は `ChatTranscriptView.swift:336` → `:168` の**全件グルーピング**が 50ms ごと × 9 タイルで回ること。表示窓（16 件）は `:169` の後段でしか効かない。

## 途中で棄却した計測

- **プログラム的リサイズ（System Events でサイズ代入）を対照にする案**: メインスレッド稼働が 35 秒中 1.5 秒しかなく、上位フレームが CFString 操作だった。再レイアウトを起こせておらず対照として無効と判断して棄却。
- **アイドル状態での A/B**: A・B とも 0 件で差が出ず、負荷条件がベースラインを再現していないと判明。合成ストリームの導入はこの失敗から。
- **`Animation Hitches` テンプレートでの定常計測**: `Severe Hang 49.52s`（記録のほぼ全域）が出たが、同時刻のスクリーンショット比較では画面が更新され続けていた。計測器側の副作用を疑い、`Time Profiler` へ切り替えた。
- 1 度目の対照トレースは保存時に `SQLite disk I/O error` で xctrace が異常終了した。エクスポートは 0 行を返すが、これは「ハング無し」ではなく**未計測**なので取り直した。

## 積み残し

- ADR 0161 の対処1（窓をグルーピングの前段へ）・対処2（確定行 / live 行の分離）は**未実装**。
- `.pty`（端末）セッションの同条件での計測は未実施。
- 実エージェントの出力速度・内容分布と合成ストリームの差は未評価。
- ADR 0116 の対処3・5 は引き続き未着手。

## 生成・更新したもの

- 新規: [adr/0161](../adr/0161-appserver-grid-jank-root-cause-is-full-transcript-grouping.md)
- 更新: [adr/0116](../adr/0116-agent-grid-swiftui-jank-live-resize-width-freeze.md) を `superseded` へ、`adr/README.md` の索引
- コード変更なし（A/B 用の改変は計測後に戻し済み）
