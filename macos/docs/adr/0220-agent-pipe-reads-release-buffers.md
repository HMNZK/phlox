# ADR 0220: エージェントの出力パイプは届いたときだけ読み、読んだ分をすぐ解放する

日付: 2026-10-25。状態: 採用。ADR 0015 の「長命プロセス用トランスポート」を更新する。

## 文脈

チャット形式のセッション（Claude・Codex）は、子プロセスの stdout/stderr を `FileHandle.availableData` の無限ループで読んでいた。`availableData` は読んだ `NSData` を autorelease プールへ入れる。ループは 1 つの実行単位のままプロセス終了まで続くので、プールが一度も空にならず、読んだ量がそのままメモリに残る。2026-10-25 に Debug 版の常駐プロセス（約 24 セッション、約 44 時間稼働）が約 7.3GB に達した。小さな再現では約 286MB を読ませると同じ量だけ増え、1 回の読み取りごとにプールを空にすると約 1MB で止まった。

加えて、stderr の末尾 64KiB だけを残す処理が `Data.removeFirst` を使っていた。これは切り出しになるだけで先頭の領域を解放せず、追記のたびに裏の領域が伸び続けた。実際のトランスポートで 256MiB を流すと、修正前は stdout 経路で約 259MB、stderr 経路で約 517MB 増えた。修正後はどちらも約 1MB だった（テストプロセスの phys_footprint の増分。手元で計測し、テストには登録していない）。

同じループが `LineDelimitedProcessTransport`（Claude）と、ほぼ同じ内容の `CodexAppServerKit.ProcessTransport`（Codex）に重複していた。パイプ 1 本につき 1 本のスレッドが読み取りで待ち続ける作りでもあった。

## 決定

1. **長命のトランスポートは `DispatchSourceRead` で読む。** データが届いたときだけ `read(2)` で読み、イベントごとに処理を終える。待機中にスレッドを占有せず、Foundation の autorelease を経由しない。fd を閉じるのは従来どおり `finish()` だけにする。PTY 側（`PTYManager`）と同じ形。
2. **1 行の長さに上限を置く（既定 64MiB）。** 改行が来ないまま上限を超えたら、理由を stderr の末尾に追記して子プロセスを止め、以後の出力は捨てる。Claude は既存の「プロセスが終了した」エラーに stderr の末尾を付けるので理由が表示される。Codex は stderr を表示しないため、既存の「app-server が終了した」エラーだけになる。Claude Agent SDK（Python）も同様の上限（既定 1MiB）を持つ。正常な出力が引っかからないよう大きめにした。
3. **Codex 専用の `ProcessTransport` を削除し、`LineDelimitedProcessTransport` に一本化する。** `AppServerTransport` への準拠は CodexAppServerKit 側の拡張で与える。
4. **stderr の末尾保持は `removeSubrange` で先頭を詰める。**
5. **短命の読み取り（`OneShotProcessRunner`、Codex のモデル一覧取得）は、1 回の読み取りごとに `autoreleasepool` で包むだけにする。** プロセスの終了で読み取りも終わるため、読み方そのものは変えない。

## 見送ったこと

- **受け手が追いつかないときに読み取りを止める仕組み（背圧）。** `receivedLines` は `.unbounded` のまま。今回の溜め込みの原因ではなく、必要性を測ってから判断する。
- **表示用の会話一覧をメモリから外す。** 「24 時間動いていない・実行中でない・返事待ちでない・表示中でない」セッションを対象にする方針は合意済み。量を測ってから別に決める。

## 影響

- 上限を超える 1 行（巨大なツール結果など）を受け取ったセッションは、エラーで止まる。
- Codex の stderr は捨てずに末尾 64KiB を保持するようになる（Claude と同じ）。ただし Codex 側はまだ表示に使っていない。
