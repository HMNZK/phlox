---
status: active
last-verified: 2026-11-01
---

# macOSの応答性改善

## 範囲

段0の基準→段1の実測診断→段2の原因ごとの最小修正/同負荷再測定→段3の約30分の持続確認と最終レビュー。ユーザーの全段階自走承認を受けて継続。実AIを使わず、使用中のアプリを止めない。Git統合/公開は今回の完了条件に含めない。

[ADR0223](../adr/0223-runtime-snapshot-main-actor-budget.md)に候補と境界を先に記録した。正式段0をN30/M15で完了し、変更Aは再測定後に撤回した。変更B（GUI本文の不変時省略と質問日付cache）だけを実装し、ReleaseでN10/N30の同負荷再測定を終えた。容量不足による中断後、ユーザーの専用中間物削除許可を受けて空きを回復し、残る検証を再開する。採用判断は検証完了まで保留。旧計測を正式baselineへ転用しない。

証拠の正本はworktreeの`.verification/responsiveness-input-probe-20261031/full-20261031/`。`plan.md`にN10→30→50→100/M=N/2・固定本文/件数/byte・目標・測定区間を記録。各修正は「再現→仮説→根拠→最小変更→同負荷再測定→正しさ確認」を追記する。

## 進行中

変更Bの正しさ確認はSessionRuntimeProjectionTests/AsyncQuestionNotificationTestsのrunner報告31件で成功。Release実アプリの同負荷測定は下記の通り実施済み。計測版と普段使いのPhloxをPID/保存先で区別し、前面条件gateを維持する。不成立試行は保持し、成功値へ混ぜない。verify-phlox段1は6packageの全登録patternが成功しmissing/skip/issueなし。段2は受入1件83.478秒と中断→再開1件4.808秒が成功、両者のowned cleanup全件exited=true。adapter初回の0件実行は無効としてログを保持し、unittestが正しいmoduleを探索する接続へ直して再実行した。2波pilot後の本試験は、負荷生成器の誤認と容量不足により両方とも未完になった。qualityはENOSPC/exit120の初回未完を保持した上で正本再実行がexit 0。既知ADR 0209問題1件と任意試験skipは残る。変更後3フラグ性能試験はMarkdownの基準未達でexit 1。v3は途中表示切替のため固定画面収束の証拠には使わず、60Hz短期対照でもBによる保持数増加の導入は示せなかった。v6は途中heapの計測干渉で不成立のまま中止し、その任意採取だけを外したv7は30分負荷・復帰quiet・素材保存確認まで完了。ただし保持量の増加とTask/キュー欠測により全資源の収束は未証明。実IME変換も未確認で、採用は保留。独立レビュー初回の確定機能不具合0・保持リスク1に対し、最終結果の再確認が残る。

## 検出した資料不整合

`measure-single-switch-procedure.md`には/tmp・rm -rf・同一bundle ID・live履歴コピーの古い例があり、現AGENTSの隔離/置き場/禁止コマンドに従って実行する。性能3スイートは.build固定出力で、出力先変数を追加する最小変更が必要。旧ADR0093には見出し番号0091が残る。実行の正本は現コードとAGENTSを優先する。

検証準備として性能3スイートへ`PHLOX_PERFORMANCE_OUTPUT_ROOT`を追加し、元のassert/閾値/実行フラグは維持。現在の画面は内蔵120Hzで、旧60Hz readerが拒否したため新しい120Hz条件を事前固定した。不成立のN10試行は保存し、複合基準として採用しない。

正しさ調査で、GUIのreportErrorもローカル本文を変更しrevisionを増やすと判明。旧remote stampだけで省略せず、現在のGUI revisionも一致を要求する。local/remoteのrevision数値衝突時は本文置換で質問cacheを明示失効し、getterはcachehitでも本文Observable参照を読む。これを公開状態とObservation通知の回帰テストで検証した。

## 段0確定と変更Aの着手（2026-11-01）

固定した120Hz/900×560pt、100入力・30切替、入力batch間250ms・切替間350msを共有操作関数で実行した。N10/M5: 入力p50/p95/p99/max=18.694917/29.536958/32.727125/34.613667ms、切替125.492917/193.863583/202.107083/202.107083ms。N30/M15: 入力16.468125/27.663458/33.657833/36.093167ms、切替199.958125/291.607750/291.614333/291.614333ms。両規模とも入力100/100、切替30/30が前面・全glyph・隣接120Hzframe条件を通過した。入力/選択のアプリ受理からWindowServer上の最初の対象表示の観測までで、物理scanoutは含まない。切替の目標超過をN30で再現したため、段0の終了条件を満たす。測定器費用はまだ分離しきれておらず、絶対的な快適さの証明とはしない。N50の旧実測で64MiB超過を確認済み、100へ拡大しない。目標を適用する事前条件は変更しない。

変更A: 再現条件は上記N30/M15。仮説はJSON encodeをMainActorとTransport受付actorから外すと、snapshotの同期占有と停止等を待たせる時間が減ること。根拠は前段Time Profiler/signpostで生成＋encodeの大半がencodeだったこと（元記録を保持）。最小変更は不変envelopeとsequenceをMainActorで確定し、private専用actorでencodeを直列化するだけ。既存read上限2、64MiB、wire、sequence、取消前後確認、状態・保存・端末仕様は維持する。変更後に同じ複合負荷・N10/30で再測定し、効果がなければ戻す。

## 変更Aの評価と撤回

native Release buildとSessionRuntimeTransportTests（runner報告23件）は成功。実サービスN30/M0のsampleではJSON encode209 weighted samplesがworkerにあり、MainThreadは0観測。これは配置の裏取りで、CPU時間改善の証明ではない。N30/M15同一負荷の100入力は全件valid（p95 19.980500ms）。切替は28/30valid、2件でframe間隔16.6665msとなりstrict120Hz条件を満たさず、正式な分位値を出さない。全30件を捨てずに保持した補助的な観測上限p95は295.074333ms（修正前291.607750ms）、改善を示さない。入力の目標は修正前から達成しており、配置だけ変わったことを効果と扱わず、この案を製品と計測sourceから戻した。Aのsource/patch/binary hash/無効試行を含む全rawを保存した。

変更B: N30/M15の切替超過と、既存profileでのGUI適用/質問探索の全履歴費用を根拠に、不変本文の再適用と質問日付探索を省く案だけを試す。初回・execution変更・remote revision変更・GUI local revision変更を全適用し、本文を置換したときは質問cacheを無効にする。status/approval/raw log/保存/接続/状態機械は変更しない。先に既存動作を保持する回帰テストを追加し、固定sourceの再実行はrunner報告13件成功（初回は実行中編集でbuild無効、成功扱いせず記録保持）。B単独のReleaseで同じ100入力/30切替を比較し、効果がなければ戻す。

## 変更Bの同負荷測定と正しさ

N30/M15: 入力100/100valid、p50/p95/p99/max=16.370208/34.800042/38.014000/38.355417ms。切替strict25/30（残り5は16.6665ms frame間隔）、exact分位は出さない。全30件の補助bracket p95は166.475042〜174.808333ms、観測上限最大174.844125ms。段0のbaseline bracket p95は283.274500〜291.607750msで、観測区間モデル内の差下限は108.466167ms。統計的な信頼下限・未観測の一瞬の表示/戻りがないことの保証とは呼ばない。N10/M5は入力100/切替30全件validで、p95は26.081708/143.388500ms。全分位の改善やCPU削減とは主張しない。N30入力p95とN10切替p50は修正前より高い単発観測も保持する。

両規模で全producer600件、固定history500件の内容/順序と保存stream全文SHA、57byteのBOM/CRLF/NFD保存が一致。N10の実アプリで日本語の選択置換、Undo、Redo、Undo後の保存を追加確認し、元57byteと一致した。日本語IMEの実変換は未確認。人の手入力と自動キー操作を同等の証拠にせず、下記の自動操作2回も変換成功とは扱わない。

段3は同じGUI/runtime PIDでN30/M15を反復する。fake-agentは各child一度だけ600件を出すため、負荷15個を閉じて同量の新childへ戻す。全件保存後の退役本文は既存revertで空にし、live本文は毎回501件×chat18へ戻す。退役file/削除ID等のmetadataは別に計上し、完全に同じ全状態とは呼ばない。閉開・再seed中の出力休止と追加seed量も記録し、全30分ずっとM15出力だったとは主張しない。1周pilotで実観測の成立を確認後、30分以上の反復と同状態checkpointを採る。Task/保存queueの記録は既存境界signpost入り別Releaseを用い、plain Releaseの応答測定と計測費用を区別する。


## 持続試験の具体化と独立レビュー途中結果

逐次pilotは出力停止が約51秒あり不採用。2組15セッションを交互に動かし、次組の固定600件を出している間に前組を閉開・再seedする手順へ変更した。Nは29〜30、同時出力は実時刻で記録する。2波pilotは150.852秒で完走し、各波9000件の内容・順序・保存を確認した。負荷中checkpointは一方のchat9が503項目、他方9が501項目で比較し、初回・最終は全chat18を501項目へ戻す。退役metadataは別計上する。

独立レビューは、不変本文をGUIが保持する間もSessionRuntimeClient.latestSnapshotが最新decode本文を保持するため、GUI内の配列共有だけではclientまで含めた二重保持は防げないと指摘した。boundedな保持量増加の可能性として扱い、コメントの範囲をGUI内へ修正した。実行コードは変えず、同履歴でのfootprint/滞留を持続試験で確認する。

全process対象の2本のpilot traceが記録保存中に重複した。単独計測器費用の校正や性能比較には使わず、Task/保存queueと素材・終端の観測可能性の確認に限定する。


## 持続試験の未完記録と再実行

最初の本試験`run-soak-full`は26波の検証済み9000件ずつを処理した後、1649.416秒で負荷生成器のassertにより終了した。モデル一覧取得用の`initialize/model/list`だけを扱う短命fixtureを、新規チャットの候補へ含めたのが原因。新しいセッションと同時にこのfixtureが作られると候補が2つになった。製品の障害や30分成功とは扱わない。最終の履歴復帰は未完のまま、ログと生記録を保持した。

負荷生成器だけを修正し、structured fixtureは実際の`thread/start`を受けたものに限定した。既存fixtureの識別と同じ規則で、PIDの比較対象からも短命probeを外し、終了済みprobeのPID再利用と混同しない。実記録にある7 probeの拒否・18 chat/12 PTYの受理、全本文/順序/切詰め拒否の自己検査をcompact-test経由で再実行し成功。製品差分は変えていない。新しい`run-soak-full-v2`を別のGUI/runtimeで開始し、固定負荷・出力量・N/Mを維持する。runtime単独のTask/保存queue採取は負荷前から32分間、最終復帰後まで続ける。先の未完試験と混ぜて分位値や収束を報告しない。

手入力の日本語確認は未入力で保存button無効の画面を確認し、依頼をいったん保留して計測版を入れ替えた。確認用ファイルは保持する。全体検証後に再表示する。ビルドキャッシュ完全削除の質問は未回答なので削除せず、終了済みのアプリコピーとtraceをSHA一致する透過圧縮で保存した。


## 容量不足による停止記録（再開前）

新しい本試験も27波・243,000件、最後の検証済みcheckpoint 1683.838934秒までで中断した。30分完走でも、最終同履歴への復帰成功でもない。ディスクの通常空き171,999,232 bytesを観測した直後、停止用heredocさえENOSPCになったため、ファイル作成を伴わない操作で今回所有するcontroller/recorder/driverへSIGINT、GUI/runtimeへSIGTERMを送った。fixture残存なしと通常Phlox（PID670/39692）の稼働を確認した。controllerと資源collectorはexit120で、最終result.jsonは作成できていない。一次資料は `.verification/responsiveness-input-probe-20261031/full-20261031/storage-capacity-stop.json` と `run-soak-full-v2/soak-progress.json`。

この容量停止時点では変更Bの採用・完了を保留し、厳密な変更後N30切替分位、qualityの再実行、3フラグ明示の変更後性能測定、30分完走/最終復帰、実IME確認を未完とした。当時は使用済みmanaged中間物約5GiBの完全削除許可も未回答で、削除していなかった。原traceと要約を保持して再生成可能な解析XML3件だけを整理し、終了済み記録の透過圧縮と同一内容appのAPFS clone共有を行った。物理共有extentが不明なため、割当サイズ差を実空き増と同一視しない。

独立最終レビューは確定機能不具合を検出しなかったが、GUI旧本文とclient最新decodeの二系統保持リスク、必要な検証不足を残している。最終レビューは `full-20261031/final-independent-review.md`。容量と日本語手入力を確保した後、同じ条件で残る検証を再実行する。


## 中間物の削除許可と検証再開

ユーザーが full-swift-debug・swift-perf-release・native-debug-verify の使用済みコンパイル中間物約5GiBの完全削除を明示許可した。既存の管理lock/所有記録・現在のopen files・保護名を照合し、計画の12ディレクトリだけ削除した。空きは1,216,618,496から6,850,060,288 bytesへ回復し、署名済みappのSHA一致と12対象の不在を確認。ソース、依存checkout、app製品、原記録・結果、通常cache、.env*は保持。結果は full-20261031/approved-intermediate-cleanup-result.json、管理events.jsonlにも整理を記録した。

日本語変換はユーザーが計測用ファイルに限ってAppleScriptによる日本語切替・通常キー入力・元sourceへの復帰を明示許可した。feature手順の人の手入力と同等の主観的確認とは呼ばず、実OS入力メソッドでの変換/確定/保存を自動操作として検証する。PID・実行パス・ファイル・前面を各操作で照合し、他アプリへ入力しない。


## quality完了・変更後性能と残る確認（2026-11-01）

正本quality再実行はexit 0。macOS Swift Testing成功ID 5,610、skip event 23（suite含む）、XCTest 8成功/1skip、iOS 694成功、必須fake 13成功。iOS lintとSimulator app buildも成功した。ADR 0209の旧ブランチ名再利用時の利用順に既知未解決1件が残り、正本が既知として許容した。初回ENOSPC/exit120の未完記録を消さず、通常品質成功を性能実測や既知問題なしへ読み替えない。正本は full-20261031/quality-retry-summary.md/json。

変更後性能は3フラグを明示したRelease実行でexit 1。XCTest 4実行=3成功/1失敗/skip0、Swift Testingは4関数登録・3開始/3成功・1skip。唯一の失敗はDESIGN.md描画p95 17.744334ms>16.7ms（207frames、最大40.768333ms）。syntax全13条件とLargeFile主試験は成功し、mixed.md 1MB強調完了p95は142.226167msだった。任意real-550KB/6.6MB素材不足、long-line関数1skipと4 variant未実行を維持する。既存閾値を変えず、Bが変更していないsyntax/Markdownの前後差を因果効果と断定しない。画面外測定を実画面の入力→表示へ読み替えない。詳細は full-20261031/performance-after-summary.md/json。

日本語IMEは利用者が手入力できず、自動で2回OSの入力ソース選択（TIS）からひらがなを選択して通常キーを入力したが、英字のままで変換を再現できなかった。製品か自動操作経路か未分離で、成功扱いにしない。元のABC入力ソースとIME確認用ファイル37 bytesを復元した。記録は full-20261031/ime-auto-summary.md。

この追記後、v3の29波完走・元履歴への復帰と120秒quietを確認し、ユーザーの追加承認によりquality中間物257対象も限定削除した。詳しい結果は次節。製品の追加変更はない。旧run-soak-fullとENOSPCのv2、厳密なN30切替分位の不足、Markdown未達、IME未検証は引き続き保持し、最終レビューへ渡す。


## 30分v3の完走と追加整理（2026-11-01）

後続のOS記録調査で、v3実施中の約10:02に蓋閉鎖と表示構成切替があったと判明した。開始時の内蔵120Hz条件が全期間続いたとは扱わず、固定画面条件での30分性能・収束の達成証拠には使わない。素材の投入・内容・順序・保存の検証は保持する。GUI保持増加の原因帰属には表示切替の交絡も加える。正式120Hz目標は維持し、外部60Hzで別枠の原因診断を行う選択は、後述のユーザー再開指示で確定した。OSの根拠は full-20261031/display-transition-evidence.md/json。この時点の対照用も所有・起動時刻・実行パスを照合して正常終了し、後述の新しい対照runで再開した。通常使用のPhloxと常駐サービスは継続稼働を確認した。

v3はcontroller経過1832.521127秒、29波で完走。全435 producerが各600件、負荷261,000 records、payload 187,084,800 bytes、wire 212,923,800 bytesを投入・書き込み、保存内容/順序を確認した。wave間の出力休止1.845〜2.659秒を別計上し、全期間M15の継続出力とは呼ばない。初期/再seed history量はloadと分けて記録した。最終chat18件を各501 itemsへ戻し、120.009730秒quietも完了。500 historyのID順序/固定本文と600片streamの279件読み直しはmismatch 0。退役本文261件は全て[]で、残存する表示metadataを保存キュー滞留へ読み替えない。正本は full-20261031/soak-v3-material-resource-summary.md/json。

同等loaded checkpointのメモリ/fdは単調増加していないが、GUI heapのChatSessionViewModelは18→48、SessionViewModel/TerminalCoordinatorは12→31、runtimeは18→18/12→12だった。標本2個の保持経路にはサイドバー行の強参照があるものの、閉鎖済みセッションとの対応、永続保持、Bの原因帰属は未確定。有限のSwiftUIキャッシュや周期変動を排除せず、リーク・非収束・収束達成のいずれも断定しない。GUI Taskの終了側attach表が空であることを既存Task実数0と解釈しない。全live Task/購読/タイマー、保存キュー滞留と最古待ち時間は未測定。GUIの根拠は soak-v3-gui-retention-summary と soak-v3-gui-task-summary。runtime traceは正常保存され、本更新時点で解析中。

全計測終了後、quality keyの257中間ディレクトリ約5.61GiBをユーザーが別途明示承認した範囲で削除。管理lock/所有/inode/open files/保護名を再照合し、結果はcompleted/productsUnchanged=true。空きは16,100,462,592→21,899,223,040 bytes、差5,798,760,448 bytes。Products/app/xctest/source/checkouts/ログ/結果は保持し、承認記録を実行済みへ更新した。正本は full-20261031/approved-quality-intermediate-cleanup-result.json。割当量と実空き差を同一視しない。

runtime traceの解析は完了した。Taskの実更新は開始約16秒までで、終端へ延長された176を最終生存数と解釈しない。保存キューは後半1771.959〜1842.933秒の7,073組が全対応して終了し、観測cohortの末尾待機/実行中は0、最古待ち最大850.771458ms。ただし前半欠測があるため、全期間の最大値や収束の評価はnullとした。TOC終端後のraw行はphase集計から除外した。正本は full-20261031/soak-v3-runtime-trace-summary.md/json。前段の「解析中」はこの追記で更新する。

最初の追加2波対照準備は外部60Hzがactiveで旧内蔵120Hz guardに拒否されたが、下記のユーザー再開指示を受けて別枠60Hz診断へ進んだ。正式120Hz目標を変更した達成扱いにはしない。サイドバーの子行を折りたたみ60秒以上待つ診断でモデル48/31が減らなかった記録も保持し、永久保持や原因を断定しない。旧v3と旧対照用の所有GUI/runtimeは終了済み。qualityは既知問題1件を許容して成功したが、Markdown性能未達とIME未検証は残り、v3完走を全段階完了や固定画面の長期収束へ読み替えない。


## 外部60Hzでの保持対照を再開（2026-11-01）

ユーザーが「どちらの画面でもよい、今は両方開いている」と再開を指示した。前後とも外部主画面ID2・60Hz、2918×1231pt/5836×2462px、window900×560ptに揃える。内蔵ID1は非主画面120Hz、1800×1169ptで同時active。元の120Hz正式応答基準は維持し、保持原因の短期診断として別集計する。事前条件は full-20261031/retention-control-protocol.json。

元soak-run.pyを変えず、guard参照1行のみを変更した検証用soak-control-60hz.pyとretention-control-case.pyを使う。既存controller/resourcesを呼び、全active画面のmodeと所有windowの所属・sizeを1Hzで監視する。変化時は診断を無効にする。専用selfcheckはcompact-test経由でexit 0。製品source変更はない。

before-v2とafter-v3の短期対照は両方completed/displayStable=trueで、全280/282標本が同じ画面構成。各18,000 records、payload 12,902,400 bytes、wire 14,684,400 bytes、2波＋約120秒quietを揃え、本文再検査36件ずつは不一致0。GUI ChatSessionViewModelは両方18→30、SessionViewModel/TerminalCoordinatorは12→20、runtimeは18→18/12→12だった。Bで保持数増加を導入した証拠はないが、等価・リークなし・長期収束は断定しない。正本は full-20261031/retention-control-comparison.md/json。

after-v2はcompleted=trueでも7標本にwindow/display不一致・観測エラーがあり比較から除外した。after-v3でやり直して採用し、両比較appは所有確認後に終了済み。短い60Hz対照を元120Hzの正式応答達成や固定画面30分収束へ拡張しない。旧v3の途中表示切替、Task欠測、Markdown未達、IME未検証は保持する。


## v4/v5の不成立と承認済み論理寸法基準のv6（2026-11-01）

v4は途中で外部画面が外れ、内蔵120Hz・1512×982ptへ表示構成が変化したため不成立で中断。v5はWindowServer矩形が一時243×151となって不成立。その後に最小化/実拡大の校正へ使用して中断した。v5 traceはexit 2・ktraceFailedStopで、保存内容を正常な全期間Task観測の証拠にはしない。新基準を遡及適用せず、v5以前の無効判定を保持する。

校正770標本では、最小化中101標本でCG可視windowが消えても読取専用AXの論理寸法は900×560だった。実拡大はAX1512×949として89標本で検出した。ユーザーは次の試験から論理viewportで実リサイズを判定し、OS縮小/非表示を別記録する変更を明示承認した。校正要約に残る承認待ちは当時の状態で、新しい承認済み条件は full-20261031/fixed-display-full-v6-plan.md、校正はwindow-frame-calibration-summary.md/jsonへ保存。正式入力/切替の前面・初描画frame基準は変えない。

v6を内蔵120Hz・1512×982pt/3024×1964px、論理900×560、N30/M15・各600 records・500 historyで開始した。30分＋履歴復帰120秒quietと5波ごとのGUI heapを予定し、全display構成とAX論理寸法/所属を1Hz監視する。OS上のpresentationは別記録し、実リサイズ・画面/Hz変更・AX欠測は不成立のまま。開始連絡時点で約4分・4波、所有GUI6667/runtime6706、controller10331、recorder10044。この時点ではv6は未完で、その後、下記の計測干渉により不成立のまま中止した。製品source追加変更はない。

## v6の計測干渉とv7の再試験（2026-11-01）

v6の5/10/15/20波のheap採取4区間と追加の同一heap対照1区間に、AX読取エラー6件の全てが重なった。区間外のAXエラーは0件。任意の途中heap採取が観測へ干渉すると判断し、v6を不成立のまま中止した。全probe時刻と失敗は full-20261031/heap-observer-interference-summary.json、当時のsourceはSHAを再現するretention-control-case-v6.pyへ保存。v4/v5/v6を遡って成功扱いにしない。

v7は任意の負荷中heapだけを撤回し、開始前/最終120秒quiet後のheap、連続proc_rusage、承認済みの読取専用AX論理寸法と全display構成の1Hz監視を保持する。実リサイズ・画面/Hz変更・AX欠測の失敗guard、負荷速度・各600 records・500 history・30分・元501 itemsへの復帰は不変。正式before/afterの入力/切替の前面・初描画frame基準も変えない。事前条件は full-20261031/fixed-display-full-v7-plan.md。

v7は内蔵120Hz・1512×982pt、論理900×560で開始した。開始連絡時点で約2.7分・2波・172標本、bad 0件だった。所有GUI29102/runtime29155、controller31249、recorder30942、helper session67822/driver59943/trace69870を記録する。開始時点では最終保存・quiet・保持量は未確認だった。その後の確定結果は下記へ追記する。製品source追加変更はなく、既存Markdown性能未達・実IME未確認を維持する。

## 承認済み16キャッシュの整理完了（2026-11-01）

ユーザーの「未使用キャッシュ16件を削除して続行」を別途記録し、今回専用full-swift-release/native-release/native-release-boundariesのexact16対象を限定削除した。結果はcompleted/protectedUnchanged=true、16対象全て削除済み。空き5,442,777,088→8,467,992,576 bytes、差3,025,215,488 bytes。削除処理2.713834秒、全検査込み5.013183秒、PID47120と実施時刻・検査費用を保存した。app executable/DWARFの限定SHAと固定した製品・.o等のmetadataは前後一致し、source/deps/ログ/結果と管理status/pinnedは保持した。full-swift-releaseのfailedは性能試験exit1の履歴として変えていない。正本は full-20261031/approved-remaining-used-cache-cleanup-result.json と remaining-used-intermediates-approval.json。

容量回復と削除時間を製品の高速化へ読み替えない。整理記録の追記時点ではv7は約19分、画面不一致0の進行中だった。その後の完走結果と未確認事項は下記へ更新し、Markdown未達・実IME未確認も維持する。製品/テスト変更、重い解析、ビルド、trace exportは行っていない。

## v7完走と残る観測限界（2026-11-01）

N30/M15のv7は29波・controller1834.633365秒、最終18chat各501 itemsへの復帰と120.117999秒quietまでcompleted=true。435 producer各600件、261,000 records、payload187,084,800 bytes、wire212,923,800 bytesの投入/書込と本文・順序・保存が一致した。固定内蔵120Hz・1512×982pt/論理900×560のguardは1927標本bad0。ただしOS presentationの縮小4標本とpreload/load/postheap周辺の観測gapは別記し、標本間の全状態不変とはしない。正本は full-20261031/soak-v7-material-resource-summary.md/json。

同量loaded点のfootprint/fdは単調増加しないが、GUI ChatSessionViewModel18→31、SessionViewModel/TerminalCoordinator12→20、AnyCancellable74→114を観測した。runtimeは18→18/12→12。有限cacheと持続増加を分離できず、リークなし・収束達成はいずれも未証明。型別heap数は全購読/全Task実数ではない。quiet終盤CPUはGUI約55%/runtime約15%で残り、単なる30分完走を快適さの証明へ読み替えない。snapshot診断最大43,057,280 bytesは64MiB未満で、N50の容量限界を取り消す根拠にはしない。

recorder30942はexit2・ktrace停止エラーを残してtraceを保存した。Task更新は負荷前約22秒のみ、保存キュー境界の観測は0件で、全Task数/滞留/最古待ち/最終待機/収束は未測定null。保存内容一致を観測欠測の代用としない。累積IPC・純粋背圧・raw PTY全byte/ANSI一致も未測定。限定診断の正本は full-20261031/soak-v7-runtime-trace-summary.md/json。負荷中の承認済み16cache整理は時刻/費用を分離記録し、容量回復を製品効果にしない。

v7の所有アプリ全件の正常終了と通常GUI670/runtime39692の生存を確認した。厳密N30追加比較run-projection30-repeat1は外部主画面60Hzのためpre-capture guardで拒否され、capture/load未開始・性能測定なし。その後ユーザーが内蔵120Hzへ復帰し、追加試行を完了したため回答待ちは解除。結果は下記へ追記する。旧切替5invalid/厳密分位未確定、quality既知問題付き成功、Markdown性能未達、実IME未確認を維持し、採用・全体完了は保留。製品/テストの追加変更はない。

## B N30追加1回の完了と未確定項目（2026-11-01）

ユーザーによる内蔵120Hz復帰後、主画面ID1・1512×982pt/3024×1964px・window900×560を確認して同じBを1回だけ再測定した。開始前60Hzのpreflight失敗はcapture/load未開始の履歴として保持し、質問待ちは解除。製品Bやreader/厳密gateは変更せず、元B N30の25/30も置換・合算しない。追加試行はこれ1回で終了する。

入力100/100 strict valid、p50/p95/p99/最大は21.616625/25.250791667/25.362500/26.808833333ms。切替は30件全てを保持し29/30 strict、trial10のframe間隔16.6665msによりexact分位はnull。29件だけの分位値を出さず、全30件の補助bracket p95 167.152542〜175.485875msと厳密目標未確定を分ける。入力p95 50ms以内でも複合目標全体合格とはしない。

9000 records、payload6,451,200/wire7,342,200 bytes、全15producer各600件、初期500本文と負荷9chat保存SHA、57byte保存が一致。controller全child exit0、所有GUI/runtimeはcleanup全件exited=true、ABC復元を確認した。通常GUI670/runtime39692は存続し、自分の計測app全件を終了済み。正本は full-20261031/projection30-repeat1-summary.md/json。停止42.440333msは固定M外の非出力ターンに対する1回の中断観測で、固定負荷を止めた効果ではない。

完了は追加測定・内容/順序/保存・所有cleanup。Markdown性能は未達、厳密切替分位と実IMEは未確認、全資源収束/リークなしは未証明。quality既知問題付き成功とv7の観測限界を維持し、目的達成・全段階合格・採用はいずれも保留。新しい質問や製品/テスト変更はない。


## 閉鎖個体と保存待ちの追加診断（2026-11-01）

ユーザーの続行指示を受け、通常GUI670/runtime39692を残して専用Releaseを背景起動した。保存境界の標準log streamは既知40仕事の校正でも0境界となり不成立だったため、隔離コピーだけに上限8192配送/192MiBの連番台帳を追加した。enqueue/begin/endは仕事IDを共有し、通常経路のJSON化/書込は専用queueで行う。ack公開のI/O競合は独立レビューで検出し、完全write・fsync・close後のatomic renameとjournal内同nonce照合へ修正した。40仕事/120境界、overflow/cap/I/O障害時の不成立検出を校正し、製品ソースには追加していない。Task全数の観測とは別である。

N10/M0で追加1chatのID/executionと唯一の新規GUI heap addressを対応付け、runtime/GUI行削除後120秒でも残る個体を確認した。承認済みの2秒前面化、project名の更新、折畳みでも解放しなかった。追加10回の全個体が残り、保存graphにはSidebarSessionRowから閉鎖VMへの明示strongと通知/テーマ観測の枝がある。未知のSwiftUI内部辺を全てstrongと断定せず、有限10回で永久リーク・無限増加とは結論しない。台帳ありの新規対照でもactive6→16、120秒quiet後16、AnyCancellable36→56だった。

N10/M5の短い固定出力は3000records、payload2,150,400/wire2,447,400 bytes、全5producer各600件、3chat各307,200byteと500履歴の順序/本文/SHAが一致した。静止した負荷前後の完全prefixを照合し、初期seed/churn8058仕事を除いた追加9仕事/27境界のenqueue→beginはp50 0.460833/p95=p99=最大61.352000ms、begin→end wallはp50 7.019042/最大61.192458ms、記録cohort末尾0待ち/0実行中。drop/pending/error0・capなし。ack.pendingは観測配送であり保存待ちとは別。初期seed burstの最大約10秒とは条件が違い、改善比較には使わない。runtime本文と保存ファイルの一致・idleも別確認した。約60秒の成功を長時間収束や共有actorのCPU占有の証明にしない。

通知callbackのmodifier全体捕捉をBool Bindingだけへ変える小さい私的対照を準備し、同一churn-caseで比較中。製品への採用は効果と正しさが確認できるまで保留。再現手順・hash・個体対応・校正・失敗記録・観測費用は`.verification/retention-queue-diagnostic-20261101/`へ保存する。入力/切替の正式120Hz基準は変更せず、背景診断を実画面応答の合格に読み替えない。


2callback私的対照は完了し、元B+journalと同じVM6→16、AnyCancellable36→56、TerminalCoordinator4→4、120秒以上のquiet後も閉鎖10個体を保持した。効果がないため不採用で、製品差分は増やしていない。候補graphでは新callbackがBoolのState locationだけを捕捉すること自体を確認したが、内側contentに従来menu→閉鎖VMの経路が残った。次は残るonHoverの暗黙modifier捕捉だけを狭める私的対照を1つ行う。根拠・変更前後hash・再現条件は`menu-capture-comparison.json`、`menu-hover-hypothesis.md`、targeted graph解析へ残す。単にコードが短くなったことを採用根拠にしない。


追加onHover案も同じ10cycle/120秒以上quietでVM6→16、AnyCancellable36→56、TerminalCoordinator4→4となり不採用。3callbackの捕捉がBool State locationだけへ縮小したことはgraphで確認できたが、閉鎖VMを保持する別のrow/観測/drag-drop枝が残った。捕捉縮小の成功と閉鎖個体の解放を区別し、これ以上の製品修正へ進まない。両私的候補のsource/署名/hash/失敗結果を保存し、所有確認後にアプリを終了した。比較は`menu-all-candidates-comparison.json`と`menu-hover-followup-analysis.md/json`。

サイドバー親はScrollView→LazyVStack→Section→ForEach(SessionID)で、明示的な旧row保持上限は見つからなかった。N30の閉鎖13個体が有限cacheなのか、画面付近で実体化した行に保持が偏るのかは未確定。そこで元B+journalのN10/M0・同じ位置100回開閉の上限診断と、元N30/M15固定素材の保存台帳付き継続診断を別に準備する。正式な120Hz入力/切替guardは変更せず、背景診断の表示条件/観測欠測を別記する。N30 seed18chat/9000recordsの本文順序一致とsnapshot33,563,073B<64MiB、9054保存仕事/27162境界の完全prefixを確認した。初期burst待ち最大12,718.614417ms、末尾cohort0/0だが、継続負荷の結果とはしない。


100回の保持上限診断は完走した。N10/M0・同じ元10 ID/execution/元6chat固定500本文へ毎回戻し、全100追加子の終了と退役[]を確認。0/10/20/40/70/100/120秒quietのextra ChatSessionViewModelは0/10/17/17/17/17/17、AnyCancellable36/56/70/70/70/70/70、型数/address数は全地点一致。10地点の3addressが20地点で消え、単純累積保持ではなかった。quiet120.005024秒、末尾fullprefix106queue/53418仕事/160254境界は欠落なし/cohort0/0、drop/pending/error0・capなし。今回条件の100回で頭打ちを支持するが、全Task/全購読/timerや個別ID寿命、任意条件のリーク不在へ拡張しない。原100中間seed本文はrevertで[]へ消しており、当時のruntime==saved検査/保存SHAと投入量の台帳はあるが、消去前本文の独立再読とは区別する。根拠はD/retention100、retention100-independent-audit、queue-analysis/retention100-full。

N30/M15は別の背景診断controllerを既存Soakから最小派生し、2波校正から開始した。独立レビュー/自己検査は成功し、元のstart-next→replace-old、固定600出力/500履歴、素材/保存/子終了/64MiB/1GiB reserve判定を維持する。正式120Hz guardは変更せず、1Hz表示観測とresource observerは別プロセスで、go前初回標本/PID/開始時刻を確認した。liveはcounter/nonce/offset照合だけを行い、重い全triplet replayは負荷/quiet/heap後に行う。controllerのcompletedをcoverageや全体合格と読み替えない。現在2波出力まで完了しquiet待ち、30分は未開始。


## 追加診断の終了と判定（2026-11-01）

元B+journalのN30/M15は29波、負荷1811.637167秒、復帰後quiet120.000560秒、全1966.806107秒で完了。261000records/payload187084800B/wire212923800B、全producer600、全保存本文/順序・18chat各501/退役[]を確認した。全prefix141381仕事/424143境界、初期9054を除いた132327仕事の待ちp50/p95/p99/最大295.570208/842.606500/1054.607417/1331.064792ms、末尾cohort0/0。quiet追加仕事0、drop/pending/error0、記録80509177B<192MiB。最大観測snapshot43234822B<64MiB。通常テストやobserver pending0だけで保存を判定していない。

表示load/quiet区間は1924標本error/change0、複数source最大gap1.429538秒。最終heap中のAXエラー2件とfullmonitor falseは保持、正式120HzUI性能合格に転用しない。GUI/RT各1986有効resource標本、FDはGUI初期6→reset5→quiet5/RT82→81→83、loaded範囲5〜6/82〜87、RT TTY名行数12一定。RT VM/Terminal/保存queue/ChainToken/Storeは18/12/18/18/1で同数、malloc約67.23→67.60MBだがfootprint後半は371→426MiB台、最後loaded470.533、quiet末482.704MiBへ増え、収束とは判定しない。GUI VM18→30/Term12→21/Cancellable76→118。malloc/Task stackの型別数を全Task/購読/timer実数としない。

別N30/M0でVMmap対照を行った。接続実252.815秒/切断後map開始129.632秒と計画より長い区間差を記録し、等しい先頭120秒窓はRT CPU23.4316→0.0471%、footprint+9.859MiB対−0.0625MiB。map自体は427.4/301.0/301.0MiB、malloc zone allocated63.8/63.6/63.0MiB、FRAG216.6/114.4/114.9MiB。接続中にも低下し、切断前後はdirty185→102.7/swapped116→198.3MiBでfootprintは同じ。RSS低下を解放、(empty)をreclaimableと同一視せず、元30分増加の関数帰属/リーク否定は未確定。元30/18x501/子30/queue9054、GUI停止中追加保存0を確認した。

追加実測は終了し、製品の追加変更0。通知/hover捕捉2案は効果なしで不採用。候補B/性能出力先/回帰テストは未統合で保持し、厳密切替分位・実IME・Markdown性能、全メモリ/Task等の未達/未確認により全目的達成・採用は保留する。 source連続性はProd一方byte一致、他方コメント1行のみ（逆置換で全文一致）。旧計測コピーのテストは現Wの回帰追加/出力表現・整形と差があり、literal全SHA一致とはせず初回不一致も記録した。

所有app/driver/collectorを全終了し、通常GUI670/runtime39692の存続を確認。今回専用compile中間物7件/CLI modulecache2件/重複app16件を限定削除し、元Products/dSYM/必要source/raw/graphs/dataは保持。managed-build4キーをfinish、native Productsをpinned。独立最終レビューと詳細報告の正本は`.verification/retention-queue-diagnostic-20261101/report.md`、`final-independent-review.md`、`queue30-long-gates.md/json`、`long-resource-analysis.md/json`、`vmmap-control-analysis.md/json`。旧v3/v6/v7等の失敗/欠測/条件を遡及変更しない。


## devへの統合準備（2026-11-01）

ユーザーの「devにマージして」を受け、候補Bの製品2ファイル、回帰テスト、既存性能テスト3件の出力先指定、仕様・ADR・本記録だけをコミットして共通マージツールで検査する。追加調査は再開しない。過去の採用保留はこの指示前の判断として保持し、今回の統合判断はADR0223末尾に記載した。未達・未確認事項を合格へ変更せず、計測専用コピーや.verificationはGitへ含めない。マージの成否と新たな品質記録は共通ツールの.verification/gitflow-merge.*へ残す。
