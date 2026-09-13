---
id: task-17
difficulty: standard
depends_on: [task-25, task-38]
user_visible: true
acceptance_tests:
  - .claude/scripts/task17-wiring.rb
baseline_commit: 3abd7d1
contract_tests: []
allowed_paths:
  - macos/App/SettingsView.swift
  - docs/agent-output/task-17.md
---

## 目的

UI-05「ボタンの強さを操作の重要度に合わせる」。通知テスト・エージェント管理・更新確認の3補助ボタンを標準 `.bordered` に統一し、独自のグラデーション・枠・影と焦点抑制を取り除く。操作内容と有効／無効条件は維持する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:168`。UX-06（task-38）による5タブ化後の `SettingsView` を対象とし、旧草案の単一スクロール画面を前提にしない。

本契約は Codex 草案 `docs/agent-output/contract-draft-task-17-r2.md` を PM が 2026-09-13 に採択したもの（改訂 2）。旧版（XCUITest 前提）は git 履歴を参照。原文:調査時 HEAD は `3921d9c77f4a2fe1290771689beb2cfc9b513d03`。ファイル変更・本草案の保存・テスト作成／実行・App ビルド・実画面検証は行っていない。

## 入出力契約

### 事前条件と担当

- task-25 の隔離対応と task-38 の5タブ化を含み、UI-05 は未実装である状態を基準にする。調査時 HEAD を自動的に凍結 SHA としない。
- PM が本契約に従って `.claude/scripts/task17-wiring.rb` を作成し、自己検査成功と未実装による RED を確認して凍結する。
- 実装担当は Cursor。テスト・検査スクリプト・契約・台帳を作成／変更せず、凍結済み検査を実行する。独立レビューは Cursor の実装モデルと別モデルで行う。
- `allowed_paths` は実装役の変更範囲。受け入れ検査の作成・凍結、実画面確認と `docs/agent-output/visual-task-17.md` の記録は PM が担当する。
- 既存の `macos/UITests/SettingsAuxiliaryButtonsAcceptanceTests.swift` と `macos/scripts/test-settings-buttons-acceptance.sh` は、本タスクの受け入れ方式から置き換える。Automation Mode 認証でブロックされた旧 XCUITest の再実行・認証解除を必須にしない。実装役は旧ファイルを削除・変更しない。
- 今回は View 修飾の変更だけであり、新しい判定ロジックやモデルは不要。判定ロジックが必要になった場合は契約を PM へ戻す。`macos/App` にテストを置かず、DesignSystem 等の SwiftPM パッケージ内の小さなモデルと Swift Testing による検査へ分離する契約に改訂してから実装する。

### 現在の配置と変更箇所

以下は調査時の `macos/App/SettingsView.swift` で確認した位置。行番号は実装後の検査条件に使わず、宣言と実 Button を識別する補助情報とする。

| 対象 | 現在のタブ／Section | 実 Button とラベル | RichButtonStyle 適用 | 焦点抑制 |
|---|---|---|---|---|
| 通知テスト | 一般／通知、`generalForm` | 177行 `Button("通知テスト")` | 180行 | 181行 `.focusEffectDisabled()` |
| 管理を開く | エージェント／エージェント、`agentsForm` | 247行 `Button`、250行 `Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")` | 252行 | 253行 `.focusEffectDisabled()` |
| 更新確認 | 一般／アップデート、`generalForm` | 193行 `Button("今すぐ確認")` | 196行 | 198行 `.focusEffectDisabled()` |

維持する action と条件：

- 通知：178行の `SessionCompletionNotifier.notifyCompleted(sessionName: String(localized: "テスト"))`。
- 管理：248行の `openWindow(id: AgentConsoleCommands.windowID)`。
- 更新：194行の `appUpdater.checkForUpdates()` と197行の `.disabled(!appUpdater.canCheckForUpdates)`。
- 通知・管理には、現行の対象 Button 宣言内に `.disabled` はない。追加しない。

削除対象の定義は633行の `private struct RichButtonStyle: ButtonStyle`。638行の内部 `StyledBody`、hover・押下・無効表示・カーソル処理を含め、713行の定義終端まで削除する。630〜632行の専用説明コメントも削除する。

### 出力

- 上表の各 Button の `.buttonStyle(RichButtonStyle())` を、その位置で `.buttonStyle(.bordered)` に置換する。
- 上表の `.focusEffectDisabled()` だけを除去する。
- 呼び出し元がなくなった `RichButtonStyle` 定義全体を削除する。
- 独自の代替 ButtonStyle、背景、枠、影、寸法、hover 状態、焦点制御を追加しない。`.borderedProminent` にしない。
- `.focusable(false)`、親 View への焦点抑制移設、透明な重ね合わせ、常時非表示などで標準の挙動を妨げない。

### 不変条件

`SettingsView` は77行の `TabView` から `SettingsGroup.all` を列挙し、118行の `groupForm(_:)` を経由して各 Form を描画している。この接続を維持する。

| タブ | Section の順序 |
|---|---|
| 一般 | 言語 → セッション → 通知 → アップデート |
| 外観 | 外観 → アプリアイコン |
| エージェント | 権限 → エージェント |
| 接続 | モバイル接続 → 接続済みの端末。既存の表示条件を維持 |
| 詳細 | チームビュー討論 → 使用量 → プライバシー → このアプリについて |

- `SettingsGroup.swift`、タブ名・順序・所属・tag・identifier、非永続の選択状態、初期値 `"general"` を変更しない。
- 対象3 Button の名前・管理アイコン・action・disabled 条件と、その周囲の Toggle・Binding・header・footer を維持する。
- その他の Section、保存宣言・保存キー・既定値・Binding、表示条件、ライフサイクル処理、独自 View を維持する。
- 88行の `.frame(width: 520, height: 640)`、背景・テーマ追随、137〜140行の Form 修飾を維持する。画面全体の `.tint(DSColor.accent)` を薄くして代用しない。
- `MobileTokenSection` の QR 発行・条件・action、`MobileDeviceRow` の404行 `Button("失効", role: .destructive, action: onRevoke)`、405行 `.buttonStyle(.borderless)`、406行のエラー色を維持する。
- プライバシー Link、テーマ見本、テーマ／アイコンの選択表示を維持する。
- 外観確認のために通知送信・更新通信・管理ボタンの action・QR 発行・端末失効を実行しない。

実装役は `docs/agent-output/task-17.md` に、未完了事項・前提・契約からの逸脱・未実行の検証を記録する。該当なしは「なし」、末尾は `=== REPORT COMPLETE ===` とする。PM の目視確認前に総合完了を主張しない。

## 成功基準

### 1. 凍結 SHA に対する配線検査

PM が作成する `.claude/scripts/task17-wiring.rb` は、作業ツリーの製品ソースと `git show <固定SHA>:macos/App/SettingsView.swift` の blob を比較する。正常時は exit 0、違反・取得失敗・解析失敗は非ゼロとし、違反した宣言と条件を報告する。

**基準の検証**

- `tasks/task-17.md` の frontmatter `baseline_commit` と必須環境変数 `TASK17_BASELINE` を読み、コミットへ解決した値が一致すること。
- 欠落・プレースホルダ・不正値・存在しないコミット・不一致・対象 blob 取得失敗を拒否する。
- `HEAD`、`HEAD~…`、`@`、ブランチ名、未設定時の HEAD フォールバックを禁止する。
- 固定 SHA は HEAD の祖先であり、その SettingsView は5タブ化済みで、対象3 Button に旧スタイルと焦点抑制が残り、旧スタイル定義が存在すること。UI-05 実装後のソースを基準にできないこと。
- 固定 SHA にある `task17-wiring.rb` の blob と実行する検査ファイルをバイト単位で照合し、凍結後の改変を拒否する。
- **凍結 SHA が現在の HEAD と同じという理由だけでは拒否しない。** 凍結 HEAD 上の未コミット実装は、固定 blob と作業ツリーを比較できる。禁止するのは実装後 HEAD の自動採用と作業ファイル同士の自己比較である。

基準検証は `task39-wiring.rb` の `contract_baseline_errors`・`check_frozen_baseline`、宣言の切り出しと比較は `task38-wiring.rb` の方式を参考にする。

**製品の検証**

1. `SettingsView.swift` 内の `RichButtonStyle` の定義・使用がともに0件。
2. 表に示した実 Button が各1件存在し、現在のタブ／Section 内に残り、それぞれ直接 `.buttonStyle(.bordered)` を持つ。別 Button・コメント・文字列に `.bordered` を置いても合格しない。
3. `.focusEffectDisabled()` の呼び出し数が固定基準から厳密に3件減少する。減少箇所は対象3 Button に限定し、それ以外の呼び出し・引数・所属は不変。調査時は基準候補3件、変更後0件となるが、検査を単なる全域禁止で代用しない。
4. 許す差分は、対象3 Button のスタイル置換・対象3箇所の焦点抑制削除・旧スタイル定義と専用コメントの削除だけ。
5. 対象 Button では、この許可差分だけを局所的に取り除いて固定基準と比較する。action、ラベル、アイコン、disabled、修飾順序の残部が同一であること。
6. 他 Section と Section 外のコードを宣言単位で固定基準と照合する。属性・型・初期値を含む保存宣言、関数・計算プロパティ、内部 View、条件分岐を保護する。特に destructive role・色・action は同一であること。
7. 宣言の追加・欠落・重複、Section の移動・順序変更、対象 Button の移設、未使用ヘルパーや `if false` への隠蔽を拒否する。許可差分以外の残余も比較し、解析対象外のコード追加を素通りさせない。

正規化はコメントと文字列外の空白に限定する。文字列内の空白、URL、補間、ラベル、footer の差異を消さない。括弧対応・宣言境界・対象の一意性を確認できない場合は失敗にする。

### 2. `--selftest` と凍結前 RED

`--selftest` はファイルを変更せず、メモリ上の fixture と通常実行と同じ判定関数を使う。負例は、合格する正例へ違反を一つだけ加えて作る。

- 正例：契約どおりの3置換・3削除・旧定義削除。
- 正例：対象外に焦点抑制がある基準でも、それを維持して対象3件だけ削除。
- 正例：コメント・改行・文字列中の括弧・URL・補間を正しく扱う。
- 負例：未実装、1ボタンだけ旧スタイル、旧定義残存、標準スタイルの欠落／別ボタンへの適用／強調スタイルへの置換。
- 負例：焦点抑制の残存、対象外の削除、親への移設、焦点無効化の追加。
- 負例：各 action・更新の disabled 条件・管理アイコン・ラベル・footer の変更。
- 負例：失効の destructive role・色・action、QR 処理、Binding・保存キー・既定値の変更。
- 負例：Section の欠落・重複・移動・順序変更、TabView 接続変更、未使用コードや常時非表示への退避。
- 負例：ヘッダー・テーマ見本など対象外宣言の変更、文字列内空白の変更、構文切り出し失敗。
- 基準の負例：SHA 欠落・不正・環境変数との不一致・HEAD 指定・blob 欠落・実装済み基準・凍結検査の改変。固定 SHA と HEAD が同値でも実装前 blob を持つ正常例は拒否しない。

実行コマンドはリポジトリ直下で次のとおり。`<凍結SHA>` は PM が実値へ置換する。

```sh
~/.agents/scripts/compact-test task17-wiring-selftest ruby .claude/scripts/task17-wiring.rb --selftest
~/.agents/scripts/compact-test task17-wiring env TASK17_BASELINE=<凍結SHA> ruby .claude/scripts/task17-wiring.rb
```

PM は実装前に、自己検査の成功と、製品検査が旧3ボタンを理由に失敗することを確認する。基準未設定や解析エラーによる失敗を RED と数えない。実装後は両コマンドの成功を必要とする。

### 3. 先行契約との衝突を凍結前に解消する

現行 `task38-wiring.rb` の `check_invariants` は Section 内容と `RichButtonStyle` 定義を保護し、1242行には旧スタイルと焦点抑制の存在要求がある。現行 `task35-wiring.rb` も対象 Section の内容変更を拒否する。したがって、UI-05 の正しい変更は既存検査の不変条件と衝突する。

PM は実装委譲前に、先行契約・回帰検査を正式に改訂し、**本契約が許す3ボタンと旧定義の差分だけ**を扱える状態へ再凍結する。テーマ見本、5タブの分類・接続、他 Section・宣言の保護は継続する。正しい UI-05 差分を許す正例と、action・disabled・他 Section の変更を拒否する負例を持たせる。

固定基準の内容比較と検査ファイルの凍結整合性も再確認する。旧検査を無変更のまま成功すると扱うこと、失敗無視、検査の単純削除、実装後 HEAD への基準すり替えは禁止する。この調整は PM 所有であり、Cursor の変更範囲を広げない。

### 4. App ビルドと回帰確認

SettingsView は App ターゲットのため、SwiftPM の成功だけではコンパイルを保証しない。PM が今回の製品から Debug App をビルドする。

`macos` ディレクトリで実行する。`<専用DerivedData>` は PM が今回の作業用に確保する。

```sh
~/.agents/scripts/compact-test task17-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用DerivedData> -destination platform=macOS build
```

統合検証はリポジトリ直下で既存の正本を実行する。

```sh
~/.agents/scripts/compact-test task17-integration bash .claude/verify.sh
```

確認した `.claude/verify.sh` の対象は8パッケージ・更新隔離検査・`git diff --check`。件数は実行結果を記録し、過去の件数を転載しない。追加の設定済み品質ゲートは PM が凍結時に確認する。未設定・対象外・実行不能・警告を区別し、配線検査・ビルド・実画面確認を互いに読み替えない。

### 5. PM 目視ゲート：隔離 Debug と AX

**準備**

1. 凍結基準の変更前 App と実装後 App を、同じ OS・言語・寸法・テーマ条件で比較する。通常の Release や他セッションの Debug を終了しない。
2. 専用の `PHLOX_DATA_DIR`、`PHLOX_AGENTS_JSON`、`PHLOX_DEFAULTS_SUITE` と `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を使う。PID・実行ファイルパス・ウィンドウ所有 PID を照合して操作対象を固定する。
3. Dracula（`dracula`）と Phlox Light（`phlox-light`）を別々に起動する。日本語とテーマは非永続起動引数で指定し、画面のテーマ選択・OS の外観／キーボード設定を変更しない。
4. 非空の専用 suite により updater の起動を抑える既存経路は `macos/App/PhloxApp.swift:407`。実画面でも「今すぐ確認」の AX enabled が false であることを確認する。異なれば原因を調べ、期待値変更や通信開始で回避しない。
5. 設定表示に必要なメイン画面は、PM 確認済みの `sessions.json` 復元失敗プレースホルダで用意できる。**実 claude／codex／cursor の起動、課金セッション、メッセージ送信をゲートに要求しない。**

**到達と所属**

6. 対象 PID の AX から設定を開く。タブは toolbar 内の **title「一般」「エージェント」**を照合して AXPress する。タブ identifier の露出を前提にしない。
7. task-38 の過去の AX 観測では、ウィンドウ title も選択タブ名へ変わる。今回もウィンドウ所有 PID、title、画像を照合して選択先を確認する。
8. 「一般」で「通知テスト」「今すぐ確認」、「エージェント」で「エージェント管理を開く」へ到達する。必要ならそのタブ内をスクロールする。通知・管理の AX enabled=true、更新=false、ラベル・管理アイコン・文字の欠け／重なりがないことを記録する。

**通常・hover・無効表示**

9. 各テーマ・各対象ボタンについて、ポインタを外した通常状態 → ボタンへの hover → ポインタ離脱を撮影する。対象 Button は押さない。
10. PM が変更前後の画像を比較し、旧独自グラデーション・発光枠・影が標準 bordered の控えめな表示へ変わったことを判定する。OS 標準の薄い陰影まで禁止しない。
11. 無効な更新確認が有効な通知・管理と見分けられ、ラベルを読めること。無効ボタンの hover は表示観察だけとし、有効ボタンと同じ反応を要求しない。

**焦点**

12. 通知・管理それぞれについて、表示中の対象 AXButton に **AX の set focused** を行う。focused 属性を読み戻し、焦点がその Button にある画像を撮影する。
13. 属性が true であることと、PM が焦点表示を視認できることの両方を必要とする。ソースから焦点抑制が消えただけでは合格にしない。
14. Return／Space／対象 Button の AXPress は実行しない。無効な更新確認へ焦点を強制しない。
15. AX set focused が失敗する、属性を確認できない、焦点が見えない場合は未達として記録する。OS 設定変更で回避しない。このゲートは AX による焦点設定・可視性を検証するものであり、Tab キーによる巡回成功とは報告しない。

**証拠と後始末**

16. `docs/agent-output/visual-task-17.md` に変更前後のソース識別情報、ビルド、テーマ、タブ title、PID、ウィンドウ、寸法、AX enabled／focused、通常／hover／離脱／焦点画像、PM 判定を保存する。
17. 起動前後・設定表示前後の保存先と通常設定／データの差分を確認する。suite 指定だけで通常設定全体の隔離を保証したと扱わない。ウィンドウ位置保存、既存のモバイル待受・到達性照会などの副作用は別に記録する。
18. 起動元と親子関係を確認し、今回起動した不要な Debug と子プロセスだけを終了する。通常 Release と他セッションのプロセスの維持を確認する。

有効状態の更新確認と、隔離データに存在しない端末の失効行は、本タスクで実描画を要求しない。「実描画未検証、宣言の不変性を検査」と記録し、別状態の画像で代用しない。

## レビュー観点（Rubric）

- task-38 後の実 Button 3件だけを変更し、一般／エージェントの所属と5タブ構成を維持している。
- 各 Button が標準 `.bordered` を直接使い、旧スタイル定義・3箇所の焦点抑制が除去されている。代替装飾や焦点無効化を追加していない。
- action・ラベル・アイコン・更新の disabled、他 Section・Binding・保存先・表示条件・destructive role が固定基準から変わっていない。
- **主操作の強いアクセントを残す箇所があれば列挙し、そこは変えない。** 今回確認した設定内には、対象3件以外の主操作用強調ボタンはない。99行のヘッダーのグラデーションは装飾、139行の tint とテーマ／アイコンのアクセントは共通色・選択表示であり、削除対象に混ぜない。他画面の主操作を変更しない。
- 実装役がテストを書かず、PM の凍結検査と別モデルの独立レビューで判定している。
- 検査が固定 SHA の blob を読み、宣言単位の同一性と局所的な許可差分を検証している。HEAD 自己比較・コメント偽装・未使用コード・解析失敗で通過しない。
- task-35／38 との衝突を正式な契約改訂と再凍結で扱い、既存検査の失敗を隠していない。
- 明暗・通常・hover・離脱・無効・焦点を区別して実画像を確認している。AX 属性だけで外観合格としない。
- 課金セッションを要求せず、隔離 Debug の所有確認と後始末を行い、保存先の差分・副作用・未検証範囲を開示している。
## PM 採択時の調整（2026-09-13）

- 受け入れテスト・配線検査 `task17-wiring.rb` の作成は Cursor（テスト作成担当。実装担当とは別セッション）に委譲し、PM が凍結前に `--selftest` と未実装 RED を確認する。
- 成功基準 3 の「先行契約との衝突」は次で解消する: task-35／task-38 の配線検査（`task35-wiring.rb`・`task38-wiring.rb`）は各タスクの受け入れ時点の固定 SHA と比較する歴史的検査であり、統合 `verify.sh` には含まれない。UI-05 実装後は SettingsView に対する両検査の再実行を要求せず、SettingsView の保護は本契約の `task17-wiring.rb`（固定 SHA との宣言単位比較）が引き継ぐ。decision-log に記録する。
- PM 目視ゲートの実施（Debug ビルド・AX 操作・撮影）は Cursor 観測担当が手順どおり実行し、PM が PNG を確認して判定する。

## 敵対レビュー反映（2026-09-13、`docs/agent-output/task17-acceptance-adversarial.md`）

- MUST 1・MED 4・5・6 は rb 側の欠陥として Cursor に修正を委譲し、再凍結する（コメント/文字列の同時識別、対象ごとの `.bordered` 厳密 1 件＋旧スタイル位置での置換比較、単一違反の負例分離、有効 SHA 同士の不一致・HEAD 同値実装前 blob・実装後 blob の正負例）。
- HIGH 2: 成功基準 3 は本節の裁定で上書きする。task-35／task-38 の配線検査の SettingsView 保護は **本契約の凍結時点で適用終了**とし、後継は `task17-wiring.rb`（対象 3 Button の許可差分以外の全宣言を固定 SHA と比較）。両契約ファイルに適用終了の注記を追記する。`ui-ux-verify-task.sh` の task-35/38 分岐は完了済みタスクの再検証用として残すが、UI-05 実装後に SettingsView の差で失敗することは既知とする。
- HIGH 3: 対象 3 Button への AX `set focused` の成立は事前実測しない。実装後の目視ゲートで成立しなければ契約どおり「未達（未検証）」として記録し、pass 条件から外して残す（OS 設定の変更で回避しない）。この残余リスクは PM が受容する。
