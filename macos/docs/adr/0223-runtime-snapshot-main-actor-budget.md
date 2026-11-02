---
status: active
last-verified: 2026-11-01
---

# ADR 0223: 状態同期のメイン処理と不変本文の費用を抑える

## 問題と証拠

Releaseの隔離計測で、全セッション非表示でもN50のsnapshot生成＋JSON encode同期区間はp95177.223ms、GUI適用は89.678msだった。N50/M25の実重複内では生成＋encode最大342.908ms、GUI適用最大124.106ms。これはwall時間で、CPU占有率や入力遅延の寄与率とは別。全量の約55.9MBを繰返し同期し、encodeが大部分を占めた。

N50/M25で一時的に67,117,417byteへ達し、64MiB=67,108,864byteを超えて413となった。既存413 fatal契約を今回の高速化のために変えず、容量限界として報告する。上限を上げたり固定負荷を縮小して達成扱いにしない。

段1のTime Profilerでは、N50/M0・約10.9秒のGUI MainのCPU sample重み1,836ms中、質問状態の全履歴探索が661ms、適用経路が284msだった（親子stackの値を加算しない）。常駐側は同条件でMain 2,447ms中encode 2,378ms。これらはsample重みで、1回の連続占有や実画面遅延ではない。根拠は`.verification/responsiveness-stage1-20261031/report.md`と`analysis/`。現在の120Hz複合測定とは条件を分け、不変本文再適用・質問探索をGUI側の原因候補として同負荷比較で検証する。

## 検証する最小変更

1. MainActor上ではimmutableなDashboard snapshotと既存sequenceだけを確定する。JSON化をTransportとは別のprivate encoder actorへ渡し、Transportはawaitで通信受付を続ける。専用actorはencodeを直列に行い、既存pendingReads<2を応答完了まで保持するため、encode中1件＋待機最大1件に収める。JSONEncoderは仕事ごとに生成し、encode前後の取消を確認する。進行中encodeの協調中断はできない。
2. GUI投影では旧snapshotのexecutionIDとtranscriptRevisionがともに同じ、かつ現在のGUI側transcriptRevisionも受信値と同じ場合だけ、本文代入とID Set/Dictionary再構築を省く。初回(nil)・execution変更・revision変更・GUIローカル本文変更後は必ず全本文を適用する。status/承認/rawEventLog/history/エラー解除/draft回復は従来どおり適用する。
3. displayStatus経路のpendingAsyncQuestionDateは全履歴走査の結果Date?だけを(executionID,transcriptRevision)で1件メモ化する。nilも結果で、本文配列を保持しない。getterでrevision/executionIDと本文配列の参照を毎回読み、Observationの依存は維持する。cachehitでは本文の全走査を行わない。runtime本文を実際に置換するときにもcacheを明示失効する。GUIのreportErrorによるlocal revisionとremote revisionの数値衝突でも古い質問日付を残さない。blocking優先、async質問、permission除外、質問時刻を変更しない。

(1)を単独で同負荷測定し、その後GUI側の(2)(3)を同じ原因に対する一組として測る。効果がない差分は戻す。現段階では採用済み/高速化済みとしない。

## 現在の採否（2026-11-01）

(1)は実装とRelease再測定後に撤回した。encodeのworker移動はsampleで観測したが、N30/M15の切替改善を示さず、strict切替30件中2件も映像間隔条件を満たさなかった。配置変更だけで採用しない。全試行と補助的な上下限を保存する。(2)(3)のみを単独で実装し、正しさと同負荷の再測定を行った。N30の入力100件は全件validでp9534.800042ms。切替はstrict25/30のためexact分位は未確定で、全30件の観測bracketに対するp95範囲166.475042〜174.808333msを補助値として残す。5件を除外せず、200msの上限側を満たした観測と初frame未確定の制約を分ける。N10は入力100/切替30全件valid、p95は26.081708/143.388500ms。両規模のCPU削減は示しておらず、N30入力とN10切替中央値は悪化した単発値も保持する。継続採用は持続試験・quality・最終レビューの結果も含めて決める。

v7の固定N30/M15持続試験は29波・controller1834.633365秒と復帰後120.117999秒quietを完走し、261,000 recordsの投入/書込、本文・順序・保存が一致した。内蔵120Hz・論理900×560のguardは1927標本bad0。ただしOS表示の縮小4標本と観測gapは別記し、標本間を含めた画面状態不変とはしない。負荷中の承認済みcache整理費用は別計上し、容量回復を製品効果にしない。

同量loaded点のfootprint/fdは単調増加しなかったが、GUIのChatSessionViewModel18→31、SessionViewModel/TerminalCoordinator12→20、AnyCancellable74→114を観測し、有限cacheと持続増加を分離できない。recorderはexit2でtraceを保存したものの、Task更新は負荷前約22秒、保存キュー観測は0件で、全期間のTask数/滞留/最古待ち/収束は未測定null。30分完走を全資源収束・リークなしの証明にしない。証拠は作業記録と full-20261031/soak-v7-material-resource-summary.md/json・soak-v7-runtime-trace-summary.md/json。

qualityは既知ADR0209問題を残してexit0、変更後3フラグ性能試験はMarkdown p95 17.744334ms>16.7msでexit1、実IMEは未確認。追加N30比較は開始前60Hzの失敗を保持し、ユーザーの内蔵主画面ID1/120Hz復帰後、同じBで1回だけ完了した。入力100/100 strict、p50/p95/p99/最大21.616625/25.250791667/25.362500/26.808833333ms。切替は30件観測/29件strictで1件の16.6665ms frame間隔によりexact分位null、旧Bの5invalidも保持する。29件だけの分位や試行の合算は行わない。9000 records・保存SHA・57byte保存・所有cleanup・ABC復元を確認し、回答待ちは解除した。証拠は full-20261031/projection30-repeat1-summary.md/json。追加実測はこの1回で終了し、通常アプリを残して計測appは全終了。入力局所目標の達成と厳密切替/IME/全資源収束の未確認を分け、目的達成・全段階合格・(2)(3)の採用はいずれも保留する。

## 守る境界

wire形式・snapshot64MiB・sequence・35秒鮮度・全件再同期・セッション削除は変更しない。差分protocolを導入しないため、初回/再接続/欠落後も完全snapshotを取得する。Transportの急ぎcommand予約/response budgetと読取上限を維持する。

本文内容/順序、イベント、状態機械、保存actor/FIFO/失敗/flush、端末バイト/背圧、ファイルBOM/改行/NFD/競合/アクセス境界、アクセシビリティの仕様を変更しない。端末/ファイル処理を推測で改修しない。

## 採否の条件

同じMac・Release・画面Hz・固定N/M/history/outputで100入力/30切替、内部境界、CPU/memory/転送/保存待ちを前後比較する。通常の単体テストgreenは高速化の根拠にしない。入力p9550ms/切替200msは事前の全範囲へ維持し、未達や64MiB限界は明記する。

正しさは初回rev0、同revの状態更新、execution変更、revision増加/本文切詰め、質問の追加/解決/優先順、遅延decode/取消、urgent command、保存順/復元を検証する。verify-phlox、該当時状態モデル両モード、quality、3opt-in性能テスト、約30分の収束確認と最終独立レビューを行う。


## 追加の保持・保存観測（2026-11-01）

元BのRelease計測コピーで、N10/M0・900×560・外部60Hz（3123×1318pt/6246×2636px）を固定し、同じ元10 ID/execution/元6chat各500本文へ戻す100回の開閉を完走した。extra ChatSessionViewModelは0/10/20/40/70/100回/120秒quietで0/10/17/17/17/17/17、AnyCancellableは36/56/70/70/70/70/70。旧extraアドレスの一部は後の標本に消えており、最初の10回で残ったことだけでは永久保持を示さない。有限100回の頭打ちを支持し、個別ID寿命や全リーク不在は未証明。heap介入wall36.688秒/子CPU32.150秒を別記する。

通知2callbackの捕捉縮小と追加onHoverの捕捉縮小は、graph上の縮小自体を確認できたが、同一10回/120秒quietで保持数が減らず両案を不採用とした。製品へ新しいUI変更を加えない。残るThemeChangeSignal/AGSubgraph/row/Drop側の未知辺を全てstrongと断定しない。原100中間本文は消去済みなので、当時のruntime==saved検査とSHA/投入量の記録を、消去前本文の独立再読と区別する。

保存観測は既知仕事の短期校正を通した上限8192配送/192MiBの連番台帳を計測コピーだけへ加えた。N10/M5の固定3000出力・追加9保存仕事は待ち最大61.352ms、末尾cohort0/0。100回の全prefixは106queue/53418仕事/160254境界が一致しcohort0/0。N30/M15の2波校正も素材/全prefixを確認し、30分診断へ進んだ。1Hz表示監視は最終heap中のAX失敗2回を記録したまま、負荷/quiet終端の別read pointと区別する。背景60Hz診断を元の正式120Hz応答値・固定画面の全期間合格へ転用しない。

追加資料は`.verification/retention-queue-diagnostic-20261101/report.md`、`retention100-independent-audit.md/json`、`queue30-pilot-gates.md/json`。29波/負荷1811.637167秒/履歴復帰後120.000560秒quietを完走した。261000出力の保存/順序、初期9054仕事を除いた132327仕事の全triplet/FIFOと末尾cohort0/0、FD/TTYの有界な観測を確認した。一方RT footprintは後半およびquiet末尾に増加し、全メモリ収束は未証明。別N30/M0のVMmapではmalloc使用中割当が約64MiBでもFRAG/dirty/swappedの大きな会計があり、GUI切断後にCPUは下がるがfootprint301MiBは残った。接続中にも既に427.4→301MiBへ下がり、元30分上昇の関数帰属/リーク否定には使わない。全Task/全購読/timer、厳密切替値・実IME・Markdown性能の未達/未確認を維持し、採用・全目的達成は保留する。


## dev統合の判断（2026-11-01）

追加調査を終了した後、ユーザーがdevへのマージを明示指示したため、候補(2)(3)と回帰テスト・性能記録の出力先指定を統合対象とする。これは限定した改善の採用判断であり、全目的達成の判定を変えない。厳密なN30切替分位・実IME・全メモリ収束の未確認と、変更前後とも未達だったMarkdown性能を残す。encode移動と通知/hover捕捉の不採用案、計測専用処理は統合しない。共通マージツールの文書・品質・秘密情報ゲートが成功した候補だけをdevへ反映する。

## 後継の通信方式（2026-11-02）

[ADR0224](0224-incremental-runtime-snapshots.md)は、ここで維持した完全snapshot転送の方針を更新する。新方式は既知の本文とrollingログを共有して変更分だけを転送し、比較と変換をメイン処理から外す。ここで採用したGUIの不変本文省略と質問日付cacheは継続する。過去の測定・不採用判断は変更せず、新方式の効果は別のfixtureと実行記録で示す。
