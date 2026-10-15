---
status: accepted
last-verified: 2026-10-15
---

# ADR 0212: Option＋左右矢印を限定して割り当て、端末応答の要求を区別する

## 文脈

TerminalCoordinator は日本語入力を守るため `optionAsMetaKey = false` としている。その結果、SwiftTerm の Option＋左右矢印の ESC b／f 変換にも入らない。大量の色付き出力後に `1!~000065;4;1;2;6;21;22;17;28c` に似た入力が一度観測されたが、元ファイル・生成スクリプトは残っていない。

## 決定

- 共通の IMETerminalView で、Kitty キーボードプロトコルが無効（`keyboardEnhancementFlags.isEmpty`）のときだけ Option 単独＋左右矢印を ESC b／f に変換する。通常／アプリケーションカーソルモードの両方に適用する。Shift・Control・Command の組合せや IME 未確定中は既存処理を維持する。全 Option 文字をメタキーにする設定は採用しない。
- Kitty が有効なときは、左右矢印の Option 修飾を保持して既存の Kitty 符号化に渡す。`>1u` では押下とリピートを送り、解放は要求されない。`>3u`・`>7u` では押下・リピート・解放を送る。変換の押下記録と解放の消費は行わない。
- 端末応答をシェルの状態で捨てない。問い合わせへの正当な応答と誤応答を、入力バイトを固定した Swift Testing で区別する。元ファイルがないため、元の事故を再現・解決したとは報告しない。
- SwiftTerm の `cmdDECRQCRA` は中間文字を検査せず、問い合わせでない `CSI 1y` にもチェックサム応答を返す。失敗する回帰テストを先に作り、必要な `*` を確認する局所修正を行う。SGR の解析は再現なしに変更しない。

要求に `*` が必要なことは [xterm の制御シーケンス仕様](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)の DECRQCRA と一致する。問い合わせを含まない合成40万行の試験では応答は発生せず、元の観測がこの検査漏れによるものかは未確定である。

## 理由と結果

SwiftTerm の keyDown は外部からオーバーライドできない。公開APIを増やさず、共通ビューが継承する既存の keyDown に限定割り当てを置く。

下部端末とエージェント端末で同じキー操作となり、Option での文字入力を保つ。操作部品・文言・PTYKit の変更は不要。

2026-10-15 に [SwiftTerm 上流 main の Terminal.swift](https://github.com/migueldeicaza/SwiftTerm/blob/main/Sources/SwiftTerm/Terminal.swift) の `cmdDECRQCRA` を確認し、同じ中間文字の検査欠落が残っていた。上流修正の移植ではなく手元の局所修正として TerminalUI/Package.swift に記録する。上流 EscapeSequenceParser はパラメータの表現も異なり、一括更新は行わない。

Ghostty の [現行の既定設定](https://github.com/ghostty-org/ghostty/blob/main/src/config/Config.zig)（Keybinds.init の macOS natural text editing）を参照する。Shift などの追加修飾を単語移動に拡張せず、Option 単独の既定割り当てに範囲を限定する。

検証結果・未確認範囲は architecture/terminal-editor-panels.md に記録する。

上流の MacTerminalView には `optionAsMetaKeyForFunctionalKeys` と AppKit の単語移動セレクタへの対応がある。ただし機能キー全般と Kitty の入力経路も変わっているため、左右矢印だけを要求する本件では一括移植せず、既存の ESC b／f 定数を再利用する。

## 2026-10-15 レビュー後の補足

上流を再照合したコミットは [`8230eb751ec124bd8c2a7d7643566c51cd5ea763`](https://github.com/migueldeicaza/SwiftTerm/blob/8230eb751ec124bd8c2a7d7643566c51cd5ea763/Sources/SwiftTerm/Terminal.swift)。この固定版の `cmdDECRQCRA` にも中間文字の検査がないことを確認した。先の main 参照の確認対象を、再照合できる SHA として記録する。

レビューで、押下記録がフォーカス移動で残る経路と、通常矢印の長押し途中で Option を加えると Kitty の解放を消費する経路が判明した。記録の補修は採用せず、従来モードの各イベントだけで変換を判断する方針へ改稿する。従来モードは解放を送らないため、記録も解放の消費も不要となる。Kitty では各イベントの現在の修飾キーをそのまま符号化する。ADR 0213 の描画方式と端末応答の修正は変更しない。

正当な応答の期待値は手元の `cmdSendDeviceAttributes`・`cmdDeviceStatus` と [xterm 仕様](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)を照合する。DA2 は手元が識別する VT525／版20／PCキーボードの `CSI >65;20;1c`、DSR は正常状態 `CSI 0n` と初期カーソル位置 `CSI 1;1R`、DECCKSR は要求ID 7 を保持する `DCS 7!~0000 ST`。DA2 の版番号は xterm 自身の値ではなく SwiftTerm の値であり、DECCKSR のゼロは手元の未実装マクロの応答である。各問い合わせの全バイト境界での分割受信も回帰テストに追加する。

## 2026-10-15 DA1 誤応答の追加調査

実機で使用した生成スクリプトと記録が提供された。入力は 52,428,835 バイト・409,782 行で、制御は SGR のみ、DA 問い合わせ・C1 CSI・非ASCIIを含まない。従来の合成40万行とは内容が異なるため、同じ入力を最大約4KBで分割して再検証する。修正前の再現・最小化・原因の確認を先行し、その証拠に基づく局所修正を採る。調査開始時点では原因未確定。上記のチェックサム修正と正当な問い合わせへの応答を維持し、PTYKit は変更しない。

### 再現結果と境界の切り分け

- 元スクリプトとテストの生成物は SHA-256 `b943e35898a07e505f3d39b159453a8f2be4a517e0ee16e036773547f27a39a7` で一致した。4093・4095・4096バイトごとに欠落なくfeedする試験でDA1は発生しなかった。
- 修正前の `PTYManager`（読み取り4096バイト）と `UserTerminalController.makeOutputStream()` は、ともに `.bufferingNewest(2048)` を使い、滞留時に古い要素を破棄していた。パーサーには欠落の通知がない。
- 同じ破棄方針の再現テストで、ファイルの先頭49,152バイトをfeedした後、2103チャンクを2048要素のストリームへ積み、55チャンク（225,280バイト）を破棄した。欠落前の末尾は `ESC [`、274,432バイト目から再開する通常の文字列は `ces ...`。接続後は `ESC [ c` となり、DA1応答 `ESC[?65;4;1;2;6;21;22;17;28c` を1回観測した。
- 最小の意味上の再現は `ESC [` ＋（SGRの完了を含む部分が欠落）＋ `c`。受信後の3バイトは正当なDA1問い合わせと同一であり、SwiftTermでは元ファイルの問い合わせと区別できない。この入力に応答しない変更は、維持すべき正当な問い合わせのテストを壊す。

これはチャンク破棄で同じ応答が作られることの証明であり、実機の読み取り履歴の採取ではない。実機での破棄箇所・破棄件数は未確認。今回の入力にはASCII以外も巨大なSGR引数もなく、それらを根拠なく原因とはしない。

### 実PTYKitによる追加の単発調査

Phloxアプリを起動せず、変更していない `PTYManager(terminalMode: .interactive)` で `/bin/cat` に同じファイルを渡し、出力ストリームを順にSwiftTermへfeedした。ONLCR後の期待サイズは52,838,617バイト、受信は4,848,676バイト・4,741チャンクで、DA1を1回観測した。受信データのSHA-256は `175011659fb03fba929b6339644eb10760112fe59e601d574812e4c9789df18d`。

応答は受信580チャンク目。直前までの原出力は9,619,453バイト目（SGR0の `ESC [ 0` まで）、次に届いたチャンクの原出力位置は9,638,909バイト目で `ces ...` から始まる。途中19,456バイト（終端 `m` を含む）が欠落し、実際の受信列に `ESC [ 0 c` ができていた。正当な問い合わせに変化した後でSwiftTermがDA1を返すことを、人工的な破棄だけでなく実PTYKitの経路でも確認した。解析警告（`Unknown SGR attribute`、未知のCSI/ESC、`Parsing error`）も発生し、欠落で他の制御列も破壊されていた。

この単発調査は手元で実行、リポジトリのテストには未登録。実測の末尾と先頭だけを `TerminalDA1RegressionTests.recordedTransportGap` に固定し、`CSI 0 c` と同じ応答になることを登録済みテストで検査する。元のPhloxアプリ内の実機記録を採取し直したものではなく、その読み取り境界は依然未確認。

### 上流照合と修正範囲

GitHub APIの `commits/main` を2026-10-15に取得し、最新SHAが前回記録した `8230eb751ec124bd8c2a7d7643566c51cd5ea763` と同一であることを確認した。この固定版の [EscapeSequenceParser.swift](https://github.com/migueldeicaza/SwiftTerm/blob/8230eb751ec124bd8c2a7d7643566c51cd5ea763/Sources/SwiftTerm/EscapeSequenceParser.swift) はSGR引数の上限と数値処理が手元と異なるが、欠落したバイト列の復元は行わない。[Terminal.swift の cmdSendDeviceAttributes](https://github.com/migueldeicaza/SwiftTerm/blob/8230eb751ec124bd8c2a7d7643566c51cd5ea763/Sources/SwiftTerm/Terminal.swift) も `CSI c` に応答する。手元の配送ストリームはPhlox固有であり、今回の欠落を解消する上流修正は、この照合した2ファイルにはない。上流版自体のビルド・実行はしていない。

SwiftTermへの推測修正、DA1応答の抑制、ストリーム容量だけの拡大は採用しない。正当な問い合わせの期待値は維持する。調査時点では PTYKit を変更禁止としていたため、配送の修正は下の「出力を捨てない配送」で行う。

### 出力を捨てない配送（2026-10-16 決定）

表示が追いつかないときは、出力を捨てずに PTY からの読み取りを止め、子プロセスを書き込みで待たせる（普通の端末と同じ流量制御）。仕組みとテストは architecture/terminal-editor-panels.md の「出力の配送と流量制御」。

- spawn ごとに出力ゲートを持つ。未消費バイトが 1MiB に達したら read source を停止し、feed 後の消費通知（`PTYManagerProtocol.acknowledgeOutput`）で 256KiB 以下になったら再開する。
- ユーザー端末の購読者は AsyncStream をやめて同期コールバックにする。中継が全コールバックを呼び終えてから通知するので、2 段目に溜まらない。
- 停止中も 100ms ごとに 1 回（最大 4KB）だけ読む。macOS の PTY は slave の最後の close で未読出力を待ってから捨てる。実測では約 0.603 秒で、1000 バイト＋`TAIL` を出す子は、読み始めが 0.55 秒以内なら全量取れ、0.7 秒以降なら 0 バイトだった。根拠のソースは XNU の [`ptsclose`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty_dev.c#L306-L353)（`t_timeout = 60` で line discipline の close を呼ぶ）、[`ttywait`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c#L1683-L1729)、[`ttylclose`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c#L1906-L1923)（待ちに失敗すると flush する）。公開 main と実行中のカーネルが同じかは未確認。この読み取りの分だけ、消費が止まっている間は約 40KiB/s 増える。停止のたびに世代を進め、古い予約は無視する。
- 取り消しは 1 か所にまとめ、停止中なら再開してから取り消す（停止中の DispatchSource は取り消しハンドラが走らず、fd が閉じないため）。読み手のタスクが取り消されたら停止をやめ、以後は捨てる。同じ ID で置き換えるときは、旧ストリームを終えてから旧ゲートを放棄する。read ハンドラの中では待たない（同じキューで終了処理が動くため）。
- 終了時の読み切りもゲートに計上し、未消費量が上限を超えたら打ち切る。親の終了後も子孫が書き続け、表示も遅れている場合は残りを捨てる（dev ではこの場合、読み切りが終わらなかった）。

実アプリ（Debug）での結果は次のとおり。
- 色付き 52MB の cat の後に残り文字は出ず、表示は cat の終了から約 0.45 秒で終わった。
- `yes` を 30 秒流しても RSS は横ばいで、Ctrl-C から約 1 秒で画面が止まった。
- 大量出力の直後に最後の行を出して終了するスタブでは、最後の行が 3 回とも表示された。

#### 却下した案

- `.unbounded` だけにする: 残り文字は 3 回とも消えた。しかし実アプリで `yes` を 30 秒流すと、メモリが約 75MB/s で増え続け、Physical footprint は最大 2.4GB になった。Ctrl-C で `yes` は 0.1 秒以内に止まったが、溜まった分の表示は 16 分たっても終わらず、CPU 100% が続いた。
- 容量の拡大: 表示より速い出力が続けば、いずれ捨てるか溜め続けるかになる。
- 読み取りの停止だけにする: 停止中に子が終了すると、上記のカーネルの挙動で最後の出力が消えた。

#### 後続課題（今回の変更が原因ではない既存の課題）

- write 側の fd の世代管理
- 同じ ID で起動し直した旧世代の子の終了・回収
- 世代の境目での制御列の途中状態のリセット
- feed のまとめ処理
- SessionViewModel は同じ ID で起動し直すため、旧世代の遅い消費通知が新ゲートの背圧を少し弱めることがある（固まりはしない）
