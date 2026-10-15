---
status: accepted
last-verified: 2026-10-15
---

# 0201: ユーザー用 PTY の制御端末をシェルの実装に頼らず確立する

## 決定

ADR 0198 の `.interactive` の起動部分を変更し、親で argv・環境・fd 閉鎖上限を準備した後、C の子プロセスで `setsid` → `ioctl(TIOCSCTTY)` → 標準入出力の `dup2` → `execve` を行う。作業場所とシグナル設定の復元も C のシステム呼び出しで行い、fork 後に Swift・Foundation・メモリ確保・`proc_pidinfo` を呼ばない。

下部パネルとターミナル子タブに共通の修正とする。エージェント既定の `.raw` は従来の `posix_spawn` と明示 SIGWINCH 送信を維持する。`.interactive` のリサイズ通知は `TIOCSWINSZ` による前景プロセスグループへの配送に任せる。

## 理由

dev のユーザー用端末で zsh を起動すると、制御端末がなく `ps` の TPGID は 0 だった。統括役の `sleep 20` と `\x03` の計測ではコマンドが停止しなかった。前景プログラムへのサイズ変更通知も届かない。bash は自分で制御端末を取得するため、同じ起動方法でも症状が異なる。

移植元での計測では、bash 配下の前景プログラムは PGID=TPGID で `PROBE_WINCH 17 74` を返したが、zsh 配下は TPGID=0 のまま5秒以内に受信しなかった（移植元の報告値であり、このブランチの検証結果とは区別する）。`SETSID` と slave の複製だけでは制御端末を確立できない。全プロセスへ信号を送って補うと背景ジョブにも届くため、起動時に確立する。

発見の経緯は Ghostty の試作だが、この決定・実装・回帰テストにその試作への依存はない。

## 結果

2026-10-15 追記: 統括役の承認により、Ctrl-C の受け入れ条件を「`sleep 20` が5秒以内に中断されプロンプトへ戻り、次の行の `echo AFTER` が返る」に訂正する。以下の同じ行の AFTER 判定の未達・未承認は訂正前の記録。zsh が同じ行の残りを取り消すことは正常であり、制御端末を確立する決定は変更しない。ユーザー用端末にもエージェント用と同じ LANG 規則（アプリ環境の値、無ければ `en_US.UTF-8`）を適用する。

exec または子の設定失敗は close-on-exec の pipe で errno を親へ返し、親が子を回収する。標準入出力が閉じていても `dup2` に通知経路を壊されないよう、pipe の両端を fork 前に `fcntl(F_DUPFD_CLOEXEC, 3)` で3以上へ移す。

fd 閉鎖上限は fork 直前の親で `proc_pidinfo(PROC_PIDLISTFDS)` の最大 fd と `getrlimit(RLIMIT_NOFILE)` の soft limit から求める。子は標準入出力と errno 通知用 pipe 以外を上限まで `close` する。これにより soft limit を下げる前に開いた高番号 fd も閉じる。列挙と fork の間に別スレッドが上限より高い番号の fd を作ると漏れうるが、Phlox 自体は RLIMIT_NOFILE を下げないため実害は小さい。fd 作成全体の同期や専用ヘルパー実行ファイルの追加は行わない。

Swift Testing の `InteractiveSpawnTests` に zsh/bash の前景 TPGID・Ctrl-C・前景 WINCH、標準 fd 欠落時の ENOENT と子回収、高番号 fd 非継承、反復失敗時の fd 数不変・子回収、cwd・環境、既定 raw の通知を登録した。ただし、下記のとおり zsh の Ctrl-C の要求された判定は未達。UI の変更はなく、追加の画面画像は対象外、実アプリの起動・XCUITest は行っていない。

### このブランチの検証（2026-10-15）

- テスト実行はすべて `~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh <パッケージ名>` 経由。
- `SWIFT_TEST_FILTER=InteractiveSpawnTests` の絞り込みを3回実行。初回はテストの `AgentDomain` import 不足でコンパイル失敗（終了コード1・テスト未実行）。2回目は8件中2件失敗（終了コード1）。失敗は、制御端末の子の終了後に revoke された同じ PTY を再利用したことによる EBADF と、zsh のプロンプト装飾を考慮しない待機条件だった。PTY を毎回開き直し、検査コマンドが出す完了印で待つようにした。3回目は8件中7件成功・1件失敗（終了コード1）。残った失敗は以下の zsh の AFTER 判定。
- `SWIFT_TEST_FILTER='AcceptanceUserTerminalTests UserTerminalControllerWhiteboxTests UserShellSettingsTests'` の DashboardFeature 絞り込みは34件・3スイート成功、終了コード0。
- `Posix.spawn` の interactive 分岐を一時的に外し、`SWIFT_TEST_FILTER=InteractiveSpawnTests/foregroundGroupAndInterrupt` を実行。1件・1スイート中、zsh の TPGID=0 と AFTER の5秒待機タイムアウトの2指摘で失敗（終了コード1）。Ctrl-C 後の出力は `^C` で止まり、プロンプト復帰もなかった。分岐は検査終了後に復元済み。
- 最後にフィルタなしで `PTYKit DashboardFeature` を各1回実行。PTYKit は46件・3スイート中45件成功・1件失敗。DashboardFeature は正本スクリプトの本体2,070件＋実 git 35件＝2,105件成功。まとめたコマンドの終了コードは1（PTYKit の失敗）。既存の38件は成功し、追加スイート8件のうち失敗は zsh の AFTER 判定1件だけだった。
- 修正後の全件実行では zsh の TPGID=99187 と Ctrl-C 後のプロンプト復帰を観測したが、`sleep 20; echo AFTER` の同じ行の後続コマンドも取り消され、`SpawnOutputTimeout(expected: "AFTER\\r\\n", ...)` となった。bash の同じ検査と、zsh/bash の前景 WINCH、標準 fd 欠落時の ENOENT・子回収は成功。zsh の判定を「sleep 終了とプロンプト復帰後、別コマンドの echo AFTER が返る」に変更する案は未承認のため実施していない。全件成功・dev 投入可能とは判定しない。
- `clang --analyze -Wall -Wextra -I macos/Packages/PTYKit/Sources/CPTYHelpers/include -Xanalyzer -analyzer-output=text` に CPTYHelpers の2つの C ファイルを渡して1回実行。診断0件・終了コード0。手元の実行であり、テストには未登録。
- `macos` で `/opt/homebrew/bin/xcodegen generate`、続けて `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxPTYBuild build` を各1回実行。いずれも終了コード0。アプリは起動していない。
- ビルドの警告は既存 `TerminalView.swift:209` の non-Sendable なクロージャ渡し2件、既存 `Posix.swift:198` の `init(cString:)` 非推奨1件、`No AppIntents.framework dependency found` によるメタデータ抽出省略2件。今回の対象外として残す。専用の Swift lint・型チェック設定は見つからず、Swift のコンパイルはテストとアプリビルドで検査する。

### 判定訂正・LANG 追加後の検証（2026-10-15、上記の続き）

- `InteractiveSpawnTests.foregroundGroupAndInterrupt` はプロンプト設定を分割した文字列で送り、入力エコーをプロンプト復帰と誤認しない。復帰後の `echo 'AFTER'` も入力エコーの末尾が期待値と一致しない形で送り、出力を待つ。zsh/bash とも5秒以内の復帰・子の終了・AFTER の出力を検査する。
- `TerminalEnvironment.userShell` をアプリの端末 factory から使用し、LANG の解決だけは `AgentLaunchPlanner` と共有する。`TerminalEnvironmentTests` に LANG 欠落時の UTF-8 と既存 HOME・PATH・TERM の保持、LANG がある場合の優先（`ja_JP.UTF-8`・`C`・空文字）を登録した。
- 以下のテストコマンドは `~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh` を共通の実行元とした。実行中にソースは編集していない。

| 引数・フィルタ | 結果 |
|---|---|
| `PTYKit`、`SWIFT_TEST_FILTER=InteractiveSpawnTests` | 8件中1件失敗、終了1。プロンプト設定の入力エコーを復帰と誤認していた |
| `PTYKit`、`SWIFT_TEST_FILTER=InteractiveSpawnTests/foregroundGroupAndInterrupt` | 6回。診断文の await によるコンパイル失敗1回（終了1・未実行）、通常実装で1件成功2回（各終了0）、入力エコー対策途中の bash の出力行判定失敗1回（1件・終了1）、修正を一時的に外した検査2回（各1件・終了1） |
| `DashboardFeature`、`SWIFT_TEST_FILTER='TerminalEnvironmentTests AgentLaunchPlannerTests AcceptanceUserTerminalTests UserTerminalControllerWhiteboxTests UserShellSettingsTests'` | 65件・4スイート成功、終了0 |
| `PTYKit DashboardFeature`、フィルタなし | 各パッケージ全件を1回、終了0。外側ラッパーが最後の要約だけを返し、確認できた件数は実 git の35件・3スイート。PTYKit と DashboardFeature 本体の実行件数はログ要約で非表示となり未確認。件数を得るための全件再実行はしていない |

修正を外した最後の比較では、interactive 分岐を一時的に無効にし、観測用の待機上限だけ25秒に延ばした（5秒以内というアサーションは維持）。zsh は TPGID=0、Ctrl-C 送信後からプロンプト復帰まで19.8945秒となり、5秒以内の条件で失敗した。先の比較は入力エコーを含むため5秒時点での子の残留までしか検査できていなかった。比較後は interactive 分岐と待機上限5秒を復元し、その状態で最後の全件を実行した。

`clang --analyze -Wall -Wextra -I macos/Packages/PTYKit/Sources/CPTYHelpers/include -Xanalyzer -analyzer-output=text` に C の2ファイルを渡して実行し、診断0件・終了0。`macos` で `/opt/homebrew/bin/xcodegen generate` と `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxPTYBuild build` を各1回実行し、両方終了0。ビルドログは warning・error・最終結果を抽出し、pipefail でビルドの終了コードを維持した。今回観測した警告は `Posix.swift:198` の `init(cString:)` 非推奨1件と AppIntents のメタデータ抽出省略2件。専用の Swift lint・独立した型チェック設定は未設定。UI 変更がないため画像は対象外。アプリ起動・XCUITest・実際の日本語入力は未実施。LANG の引き渡しは上記の環境組み立てテストで検査した。
