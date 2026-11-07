---
status: active
last-verified: 2026-11-07
---

# 長いユーザーメッセージの復元後に画面が固まる問題

## 対象と確認済みの事実

1.14.6の画面プロセスの採取済みスタックは、`UserBubbleWidth.sizeThatFits`からCoreTextの文字サイズ計算へ集中した。実データの本文は調査ログとテストへ転記しない。既存のRelease版、実行サービス、会話は変更しない。

合成入力と正本から抜き出した`UserMessageCell`、`UserBubbleWidth`のネイティブ検証で表示停止を再現した。周辺の色・時刻・コピー部品のみ検証用の代替にした。496万文字の英字無改行は約5.8秒、日本語は約6.1秒かかった。改行を含む496万文字と家族絵文字10万文字は12秒でレイアウトが未完了だった。タイムアウト時のsampleも同じ幅計算とCoreTextに集中した。これは縮小再現の単発値で、アプリ全体の改善率ではない。JSONのencode・atomic保存・decodeは同入力で0.1秒以内に完了した。実物の保存・復元処理と隔離アプリでの検証結果は後段に記録した。

## 実アプリでの原因確認

実データを使わず、隔離した保存先に496万文字の日本語と改行の発言1件、エラー3件、別会話1件を合成した。修正前のアプリは実行サービスが約3.098秒でreadyとなった後に画面が固まった。画面のAX要求は`-25204`で失敗し、起動22秒後のCPUは97.6%だった。その場のsampleでも`UserBubbleWidth.sizeThatFits`から`CTLineCreateWithAttributedString`への集中を確認した。起動準備、GUI応答、プロファイルの記録を分けて採取した。

従って、今回再現した応答不能の直接原因は、全文を同期する文字サイズ計算へ渡した表示処理と確認できる。実データの内部でどの文字種が支配的だったかは本文を採取・転記しておらず断定しない。単語区切り、無改行の英字、日本語、改行、絵文字、結合文字を合成入力で切り分けた。

記録は`.verification/long-user-message-freeze/native-baseline-lines/ownership.json`、同`logs/long-message-unresponsive-97330.sample.txt`、同`logs/long-message-unresponsive-process.txt`にある。最初の空白区切りの受入失敗は省略案内が存在しないことでも失敗し得るため、固まりの証拠にはこの改行条件の記録を用いる。

## 修正の設計

保存する本文、送信する本文、復元する本文は全文のまま保持する。変更箇所は共通のユーザーメッセージ表示に限定する。データは既存の`ChatUserMessagePresentation`へ表示用本文と省略状態を追加する。`UserMessageCell`はその表示用本文だけを`Text`へ渡す。

表示量は先頭4096 Unicode scalarまでとする。Unicode scalarは文字を構成する符号位置で、1文字に大量の結合文字が付く入力でも処理量を制限できる。さらに、32個目の改行記号の直前までに制限する。これらの上限以内は原文をそのまま表示する。scalarで切るため、表示末尾は絵文字合字や結合文字列の途中になる場合がある。保存本文は変えない。

省略時は「先頭のみ表示」を示し、常時使える「全文をコピー」を置く。通常のコピーと全文コピーはどちらも元の本文を使う。新しい全文ビュー、ページ移動、保存形式は追加しない。別設計として本文の省略とファイルへの全文書出しを検討したが、保存失敗やダイアログの処理が増えるため採用しない。

5回ずつ交互に実行した縮小再現では、4096 scalarだけを制限した最初の案でも、`a\n`の繰り返しは表示に2048行を渡し、0.958〜3.158秒かかった。共有マシンで品質ゲートも動いていたため、これは厳密な速度改善率には使わない。表示する改行記号にも上限を加え、同期レイアウトへ渡す行数を制限する。`CharacterSet.newlines`で改行と見なされる符号を数える。CRLFはそれぞれ数えるため、Windows形式のプレビューは短くなる場合がある。

## 15秒の準備待ち

初回の実行サービスは11:06:13.484750に起動試行を記録し、11:06:31.362419にreadyとなった。同じPIDで約17.88秒かかり、画面は11:06:28の15秒期限で先に失敗した。固まった画面のsampleは11:11:59に起動した別PIDの後続画面である。実行サービスは画面の文字サイズ計算を行わないため、同一の処理停止ではない。

準備時間の内訳を示す記録はない。全セッションの直列復元などが準備完了までの経路にあるが、遅延の原因とは断定しない。今回、期限と起動処理は変更しない。準備完了後のエラー画面の再試行は既存サービスへ接続する。再発時のフェーズ別計測は別件で必要である。

## 検証計画

- 合成入力の長さ、英字、日本語、改行、絵文字、結合文字を変え、表示の境界も確認する。
- 実物の`FileTranscriptStore`とViewModel復元を使い、表示後・flush後も保存された全文が一致することを確かめる。
- 隔離した固有bundle IDのアプリで長文をcold restoreし、画面のAX応答、別会話への切替、省略表示と全文コピー導線、保存全文のSHA-256を確認する。APIの成功だけを画面応答の証明にはしない。
- 正本の`verification-gate.py quality`とmacOSアプリのビルドを実行する。実行不能や既存失敗は結果へ残す。

判断には`Fix Root Causes`を適用し、正当な入力を保存時に捨てず、応答不能が生じる表示入口を変更した。`Model the Domain`を適用し、表示上限と省略状態を既存の表示モデルへ集約した。`Explain the Number`に従い、縮小再現のレイアウト、実物の保存・復元、アプリの準備、AX応答を別々の測定として扱う。

調査資料と一時物はworktreeの`.verification/long-user-message-freeze/`にまとめる。結果は後段にまとめた。


## 最終候補の計測と受入結果

保存・復元の実物テスト5回の中央値と範囲は次の通り。合成本文は496万文字、発言1件とエラー3件。`FileTranscriptStore`、`ChatSessionViewModel.restore`、実セルを使う。CLIクライアントだけをfakeにし、CLIやネットワークの時間を保存・復元時間に含めない。

| 処理 | 中央値 | 範囲 |
|---|---:|---:|
| JSON encodeとatomic保存 | 14.5 ms | 14.2〜16.6 ms |
| ファイル読込とdecode | 14.8 ms | 14.5〜15.3 ms |
| ViewModel復元 | 15.7 ms | 15.1〜17.0 ms |
| セルのレイアウト・描画・PNG保存 | 96.4 ms | 34.9〜114.7 ms |
| flush | 15.2 ms | 14.9〜16.4 ms |

この描画時間はPNG保存を含むため、下の縮小再現のレイアウト時間と同一指標ではない。5回とも復元本文の既知SHA-256と保存ファイルの前後SHA-256を確認した。個別の`metrics.json`、`owner.json`、`long-user.png`、`short-user.png`は`.verification/long-user-message-freeze/tests/`にある。集計は`.verification/long-user-message-freeze/phase-summary.json`。

縮小したネイティブ再現を修正前後で5回ずつ交互に実行した。周辺の色、時刻、コピー部品を代替した最適化ビルドであり、製品全体の速度改善率には使わない。CPU数12、初期負荷平均12.77を記録し、同時に動く利用者の作業は止めなかった。CoreTextに入るまでとレイアウト完了を別ログで確認し、JSONの往復一致と正常終了も検査した。

| 合成入力 | 修正前のレイアウト | 最終版のレイアウト |
|---|---:|---:|
| 英字1万文字 | 中央値22.7 ms | 中央値17.4 ms |
| 英字100万文字 | 中央値1.196 s | 中央値17.6 ms |
| 英字496万文字 | 中央値5.939 s | 中央値17.8 ms |
| 空白区切り496万文字 | 中央値4.898 s | 中央値17.3 ms |
| 改行を含む496万文字 | 5回とも12秒で未完了 | 中央値12.3 ms、12.0〜22.4 ms |
| 日本語496万文字 | 中央値6.189 s | 中央値18.0 ms |
| 家族の絵文字10万文字 | 5回とも12秒で未完了 | 中央値19.8 ms |
| 10万の結合符号を伴う1文字 | 中央値10.5 ms | 中央値12.1 ms |

最終版は40回すべて完了した。詳細は`.verification/long-user-message-freeze/comparison-final-summary.json`と各実行ログ。修正前の時間制限切れを完了時間として集計していない。

固有bundle IDと保存先のアプリでも、改行を含む496万文字のcold restore、AXによる会話切替、GUI再起動後の再接続、保存全文のSHA一致を確認した。受入は`native-final-acceptance/ownership.json`と`final-native-driver.log`に記録。撮影とprofileは別の補助処理で採取し、`native-final-acceptance/logs/native-long-message.png`では省略案内と全文コピーが常時見える。修正後のsampleは主スレッド147標本中141標本がイベント待ちだった。API応答の成功を画面応答の証拠に読み替えていない。

## 回帰テストと画面比較

`LongUserMessageTests`の9テストが成功した。パラメータによる文字種の条件も含む。空本文と添付、4096 scalarの境界、改行、絵文字、結合文字、保存された全文、実コピーボタンを検査する。コピー検査は非表示領域の実セルからAX操作し、表示範囲外の末尾までクリップボードへ届くことを確認する。既存のクリップボードは全形式をメモリへ退避し、他の変更がなければ復元する。

初回は新規テストの動的AX呼び出しを直接`#expect`へ渡す書き方でSwift 6.2.3がクラッシュした。結果を型付きのBoolへ受けて同じassertionを行う形へ直した。次に、テスト内AX有効化と画面外ウィンドウの初期化を既存ハーネスに合わせ、ボタンの実操作を通した。製品側の可視性をテスト向けに変えていない。

`DesignSnapshotRenderTests`を`PHLOX_DESIGN_SNAPSHOTS=1`で実行し、`10-A1-dark-ja`と`12-U1-dark`を書き出した。この既存レンダラーに今回のユーザーメッセージ専用の状態はないため、セル単体PNGと隔離アプリの撮影で補った。`PhloxSessionWindow.dc.html`の表示見本とも比較した。通常の発言の右寄せと色は維持する。見本は角丸10pt・内側余白10×12pt、既存コードは角丸14pt・縦9pt/横13ptで差がある。今回、この差を変更せず既存コードを優先した。コード内コメントが参照する`PhloxChat.dc.html`は現在の見本一覧にはなく、比較には現存する`PhloxSessionWindow.dc.html`を使った。

設計比較と独立レビューは同じモデルの別コンテキストで行った。レビューで見つかったコピー結果の未検証は実操作テストで補った。省略末尾は複合文字の途中になる場合があるが、元の本文とコピー結果は変わらない。

## 再実行する

アプリは固有bundle IDの隔離版をビルドし、実データへ接続しない。標準の`managed-build`と`compact-test`を使う。

```sh
~/.agents/scripts/compact-test --full long-user-regression \
  python3 -B ~/.agents/scripts/managed-build.py run \
  --project "$PWD" --session long-user-message-freeze --key macos-packages-debug -- \
  env 'SWIFT_TEST_SCRATCH_ROOT={build_dir}' SWIFT_TEST_FILTER=LongUserMessageTests \
  bash macos/scripts/run-swift-tests.sh SessionFeature

~/.agents/scripts/compact-test --full long-user-native \
  python3 -B macos/scripts/tests/session-runtime-long-user-message.test.py \
  --app <固有bundle-IDの署名済みアプリ> --work-dir "$PWD/.verification/<新しい受入名>"
```

全体品質ゲートは`python3 -B macos/scripts/verification-gate.py quality`。macOS専用lintと独立した静的解析は未設定。Swiftコンパイルをそれらの代替とは扱わない。最終候補でのゲートは2026-11-07 12:34:35 JSTにexit 0で完了した。入力SHA-256は`02421c2f515d00b1436baab5c0190b6523896c60f69d7ac7911f3fa9be61c20e`。証跡は`.verification/long-user-message-freeze/quality-20261107T032046754832/`、短い集計は`.verification/long-user-message-freeze/verification-summary.json`。

- macOSの19パッケージを全数検査した。通常検査の既定の除外23件には、後段で実施する必須fake 13件を含む。実CLIや性能計測の任意検査10件は未実施。既存のGit履歴の利用順に関する既知問題1件はゲートで許容されている。今回その扱いを変更していない。
- SessionFeatureは新規9テストを含む1334テストが成功した。iOSはlint、695テスト、generic iOS Simulator向けアプリのコンパイル・リンクが成功した。
- 必須fake E2E 13件はすべて実行・成功した。これらとは別に、今回のネイティブ受入と、固有bundle IDのmacOSアプリのDebugビルド・リンク・署名確認も成功した。
- 初回ゲートでは、新規テストのコンパイラクラッシュと、既存の`scrollEditingBlockAwayAndBack`の4つのassertionが失敗した。前者はテストの書き方を修正した。後者は製品・テストとも変更せず、最終候補の全体検査で成功した。初回だけ失敗した原因は未確定であり、初回の記録も残した。この検証の終了時点ではdevへの統合やリリースは行っていない。
- macOS専用lintと独立した静的解析は未設定。macOS XCUITestとiOS実機検査は未実施。今回の主要UIフローは、入力ソースを変更しない自動AX受入で検査した。利用中Releaseへの適用と実データの再投入は行っていない。

## 後片付け

今回の隔離GUI、実行サービス、fake CLIは所有確認付きのハーネスで終了した。利用中のRelease、実行サービス、他の会話を終了・変更していない。終了済みのXcode補助プロセスが管理ビルドのロックを保持した場面では、今回のロックFDと起動時刻を照合して、その補助プロセスだけを終了した。

管理ビルド6件にfinishを記録し、Git依存コピーの状態、.env保護、実行中参照を共通スクリプトの検査で確認した。使い捨ての約10.1GiBのビルド出力と専用管理記録は、一緒にゴミ箱へ移した。さらにアプリ複製、合成転写、未使用の比較用ソースコピーを片付けた。移動先は`managed-build-trash.json`、`fixture-cleanup.json`、`obsolete-cleanup.json`に記録した。ビルド所有記録の控えは`build-records/`にある。通常の開発キャッシュには触れていない。

未統合のソース変更と、依頼された診断・検証を裏付けるログ、JSON結果、sample、画像、縮小再現用ソースを保持した。再利用する際はビルドを作り直す。
