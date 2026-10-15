# 0215: ペインのスライドと中央幅の切替を分ける

日付: 2026-10-15。状態: アニメーション由来の反復処理を避ける局所修正として採用。base: `68ccccc3`。未マージ・稼働アプリ未反映。

## 決定と理由

長い会話を展開した状態で、左右ペイン開閉による中央幅の連続変化が本文配置・文字描画を増やす。
本文だけのanimation除去では祖先の中間幅が残るため、中央の最終割当とpane内部のスライドを分ける。
製品変更はDSSidePane.swiftと、DashboardView.swiftのHStack配置境界に限定する。
履歴量・保存形式・エージェント実行・非Lazyの本文構造・UserBubbleWidthは変更しない。

開要求時に先に中央を縮める案は、予約領域全体が背景だけになる空白帯を生んだため採用しなかった。
背景色だけを揃える方法でも内容の進入順は変わらないので、進行度で割当を切り替える方式を選ぶ。

## 現方式の機構と維持契約

1. `dsPaneAnimation(value:)` は開閉値が変わったtransactionに一時的な印を付ける。
2. DashboardのHStackの `dsPaneLayoutBoundary()` は印がある更新のanimationだけをnilにし、印は子へ残す。
   overlayより内側に置き、通常更新やoverlayへ境界を広げない。
3. 変わったpaneだけがDSAnimation.paneを再設定して印を消費する。Reduce Motionではnil。
   disablesAnimations指定時は再設定・印消費を行わず、親の禁止を尊重する。
4. Animatable modifierの進行度で固定幅内容のoffsetを動かす。
   割当幅は `requestedOpen && progress == 1` の厳密な終点だけ全幅、それ以外は0。
   開く途中は広幅の中央上を滑り、終点で中央を縮める。閉要求では割当を即0へ戻す。

completion callback・追加State・driver・lockは増やさない。Group/content identity、左右alignment、clip/zIndexを維持する。
閉状態のdisabled・hit testing・AX除外、既存300ms後unloadと再開時のtask取消、子の独自animationを維持する。
300msを描画完了保証とは扱わない。中央の終点snapと通常の最終幅への配置・文字描画費用は残る。
左右同時の中央割当が必ず1回になること、GPU完了やnative前後関係は機構だけでは保証しない。

## 現baseの品質検査

検証担当がcompact-test経由で正本run-swift-tests.shを使用し、通常3packageゲートは終了0。
Dashboard本体/実git分割と直列実行は正本どおりで、独自の除外を追加していない。

| 経路 | Swift Testing原summary |
|---|---|
| SessionFeature | 1187 tests / 134 suites passed |
| DashboardFeature本体 | 2157 tests / 209 suites passed、既知の問題1件 |
| DashboardFeature実git | 41 tests / 4 suites passed |
| DesignSystem | 203 tests / 41 suites passed |

既知の問題は旧Gitブランチ名再利用時の利用順を区別できない既存withKnownIssue（ADR0209）。今回追加した除外ではない。
既存opt-inのSwift Testing 17ケースとXCTest性能1ケースはskipで、実行成功に数えない。
cleanup診断3件は警告・データ保持を検査する既存負例。原診断は保持し、全一時パス不存在は主張しない。
warningを含む6076出力行は再出力等を含み独立診断数ではない。正規化で28種類/36参照pathを確認した。
既存テスト等の警告があり、変更した既存Typography harnessにも旧AX API警告がある。当該APIは元から存在した。
今回のpane製品・新paneテスト・新sidebar harnessの警告は当該ログでは見つからない。全警告不存在とはしない。
コンパイルを独立lintやUI検証と読み替えない。明示complete/WAEの隔離試験と、既定Swift 6の原本ゲートは区別する。

実paneテストは左右のnative中間位置、中央の800/600終点、通常animated close、禁止animation、同時/単独localを検査する。
open/reopenでは終点以外なら中央800という相関も追加した。採取は5ms polling等で、sample間の幅を保証するものではない。
180ms内retargetの実走は早期位置であり、全進行段階の取消を保証しない。localはtransaction設定で、描画形は未測定。
現baseの実OS ON focused単体試験は未実行。旧baseの実OS ON/OFF単体試験は旧11hash対象の別証拠である。
独立Claudeの製品最終static/argv reviewはpass。Dashboard境界行を外す自動回帰は不足している。

runnerは資源build/actool失敗の原診断をcompact-commandで出し、準備失敗をゲート失敗に数える。
shell2本は修正後終了0。実test対象のargv検査と、debug/release共通設定・未知値早期拒否・準備失敗後test成功でも失敗を検査した。
shellだけの後続変更では製品/runner/Swiftソースの同一hashを照合し、直前3package結果を保持した。
新base500 r1はRelease事前buildがtestable import用にcompileされず、`module 'SessionFeature' was not compiled for testing` で失敗した。
後続swift testは2passだったが、runnerは資源準備失敗を保持して終了1とした。この試行を成功とは扱わない。
Release事前buildだけに正規compiler flag `-Xswiftc -enable-testing` を渡す。通常test・アプリ設定は変更しない。
全configurationへの追加ではdebug事前build/後続testに両方再compileが生じたため、既定でtestability有効のdebugには追加しない。
Release argvは成功したr2と同一、debug argvは追加前へ戻した。限定補正後のshell2本とdebug DS（203 tests / 41 suites）は終了0。
最終debug準備0.14秒/後続0.13秒はcache hitでCompiling行・warning診断なし。cold cacheでのcompile回数は未確認。
このcompiler条件差のbuild時間を、本文UIの描画性能や改善率へ転用しない。
過去の同種準備失敗2回は原出力がなく、今回と同一原因とは断定しない。原失敗ログを保持する。

## 現baseのbuildと限定UI

分離Release/Debug buildは終了0、ReleaseのDeveloper ID署名はstrict verify成功。Debug ad-hocは検証用の想定状態。
build警告はSwiftTerm creator・TerminalUI non-Sendable・AppIntentsの3種類4出現で、警告なしとはしない。
検証担当は実画面で履歴4回追加、1800×1120、左閉/右dockの開閉・連打を観測した。
端末静止像ではpane前面へ漏れる異常がなく、閉状態composer左右のfocusを確認した。
新baseの本文選択/scroll検証ではなく、保存画像や中間全frameの保証もない。
Reduce Motion ONの実UI開閉後、AXとNSWorkspaceでOFF復元を確認した。単体試験ON成功とは混同しない。

## 性能と検証限界

現base人工500のr2一回は終了0。資源準備126.67秒、actool成功・Assets.car 117608 bytes、対象2 tests / 1 suiteは52.614秒でpass。
19hash一致、所有process不在、OS OFFを確認。r1の原エラーは修正後に解消し、過去の出力欠落2回の原因とは同一視しない。
20秒sampleは開閉窓を包含し、モデル幅到達3.2597/2.0596秒だった。paint/GPU完了時間ではない。
main標本15290、Text draw59・補間6・measure26・UserBubble11・AX3049・runloop10997。標本はms/呼出回数でなく分類間重複もある。
固定人工500の各操作1標本であり、改善率や全般的応答性を主張しない。長大本文の一度の最終配置費用は残る。
旧base `8def5af7` の現方式実履歴sampleではText draw 213/214、補間3/3を観測した。標本はms/呼出回数ではない。
同じ旧baseの現方式500は操作窓をsampleに包含したが、モデル幅到達3.168/1.981秒をpaint/GPU完了へ読み替えない。
旧方式の実履歴sample、旧500 r1/r2の窓外記録とr3の同期成功も現baseの性能証拠には使用しない。
旧baseの保存SCK画像では右open予約空白なしと限定native前面異常なしを観測したが、現baseの保存画像ではない。

読書位置は旧baselineにも同種jumpがあり、量の一致は未確認。保持を保証しない。
旧base hover/cursorは左右の限定位置を観測しただけで全般未検証。選択・カード状態・追従・新着・左途中像・native clipも残件。
大容量hitch記録/exportは失敗し有効GPU/hitch結果はない。今回所有データを診断保存後に掃除してdiskを復旧した。
反復補間を抑える機構・実pane回帰・限定UIを根拠に局所修正を採用する。すべての待ち時間を解消したとは主張しない。
長大本文の最終reflow費用と既存読書位置問題は別制約として残し、GPU/全frame/全位相/全hover測定を局所修正の無限の完了条件にしない。

外部根拠: `latest-dev-gate-pm-assessment.md`、現base build/UI原記録、19file sourcefreezeとshell原ログ。
旧base参考: `progress-ui-pm-observations.md`、`ds-pane-progress-review-ui.md`、`progress-500-r1-pm-assessment.md`。
私的本文・識別子・個人の絶対パス・画像は本ADRに転記しない。必要なcode検証は終了し、本更新は文書だけである。
