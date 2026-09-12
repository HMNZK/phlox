---
id: task-39
difficulty: deep
depends_on: []
user_visible: true
hazard: "SwiftUI の新旧 mount のライフサイクルが交錯し、新 mount の接続後に旧 mount の update・破棄処理が到着して、永続 hostingView の所有権を奪う"
acceptance_tests:
  - macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift
  - .claude/scripts/task39-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift
  - macos/Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift
  - macos/Packages/TerminalUI/Sources/TerminalUI/TerminalHostingView.swift
  - docs/agent-output/task-39.md
---

## 目的

BUG-01 / P0「表示切替後にターミナルが空白になった条件を調べる」の根本原因を修正する。対象仕様は `macos/docs/specs/ui-ux-improvement-backlog.md` の「表示不具合の調査」。

`docs/agent-output/investigation-bug-01-runtime.md` の再現 A/B/C では、選択変更の有無によらず grid→single で空白になった。所有権競合を修正し、出力・履歴を保持したまま単一表示とグリッド表示を往復できるようにする。

### 根拠と因果

実行時報告の C・1 往復目では、同じ hostingView `32777439104` に対して次の順序が記録されている。

| 時刻 | 事象 | 結果 |
|---|---|---|
| `2163.005` | グリッドコンテナ `32784159104` に attach | グリッドに出力あり |
| `2165.066` | 新しい単一コンテナ `32777439744` に attach | 単一側へ載せ替え |
| `2165.070` | 旧グリッドの `updateNSView` が後着 | 同じ hostingView をグリッドへ奪い返す |
| `2165.080` | 旧グリッド側で `window=nil` | 単一コンテナは空のまま。以後そこへの attach なし |

現行 `TerminalMount.attach` は、superview が異なると無条件に旧親から外して新親へ追加する。旧 mount の失効を記録せず、`TerminalView` に明示的な `dismantleNSView`／detach 経路もない。この実装は上記の奪い返しを許す。

空白時には単一側で `setFrameSize` に伴う refresh が走っていない。次のグリッドでは既存出力が再表示されており、再描画だけの問題やデータ消失を一次原因とする修正は採用しない。

タイル見出しの AX 操作では選択が変わらない一方、`axclick.py` では選択変更が確認されている。この違いは再現記録に残すが、見出しの AX 選択機能の追加は本タスクに含めない。

本草案は read-only 調査に基づく。コード照合時の HEAD は `374249ed04280776fa103dff5b14c828a1cae388`。実行時の根拠は既存報告のログ抜粋であり、本起草では再現・テスト・ビルドを再実行していない。`bug01-spike-trace.patch` はフック位置の参照専用とし、製品へ適用しない。

## 入出力契約

### 事前条件と実際の呼び出し経路

- `SessionViewModel` がセッションごとの `TerminalCoordinator` を保持し、coordinator が同じ `terminalView` と `hostingView` を保持する。
- 単一表示は `DashboardView` → `DashboardDetailView.singleDetail` → `SessionView` → `TerminalView`。
- グリッド表示は `DashboardDetailView.detailMainContent` → `SessionGridView` → `PaneLayoutView` の `.pty` 分岐 → `TerminalView`。
- 実際の single/grid 分岐は `DashboardDetailView` にある。`DashboardView` には詳細画面の呼び出しとモード・選択変更の処理がある。
- 製品内の `TerminalMount.attach` の直接呼び出しは、現状 `TerminalView.updateNSView` の 1 箇所。
- `SessionViewModel` に直接の mount attach/detach 呼び出しはない。`bindCoordinator` が入力とサイズ通知を接続し、`handleResize` が初回 spawn・実行中 resize・spawn 中のサイズ保留を扱う。
- 新コンテナの生成・接続後にも、旧コンテナへの `updateNSView` が来るものとして扱う。旧ビューの破棄が先に終わるという仮定を置かない。

### 検査可能な公開面

既存の `TerminalMount` を、製品とテストで共有する唯一の載せ替え窓口とする。SwiftUI の `Context` や実ウィンドウを必要としない、次の面を固定する。

```swift
@MainActor
enum TerminalMount {
    static func attach(_ terminal: NSView, to container: NSView) -> Bool
    static func detach(_ terminal: NSView, from container: NSView) -> Bool
}
```

ここでの公開面は `@testable import TerminalUI` から検査できるモジュール内 API を指す。外部向けの `public` API 拡張は不要。`terminal` には製品と同じ `TerminalCoordinator.hostingView` を渡す。

- `attach` の `true` は、所有権を受け入れ、実際に載せ替えたことを意味する。
- 同じ所有者の再更新と、失効した旧所有者の要求は `false`。subview・制約・スクロールに副作用を与えない。
- `detach` は、指定した container が現在の所有者である場合だけ接続と所有権を解放し、`true` を返す。
- 非所有者または解放済みの container による detach は `false`。現在の所有者を外さない。
- 世代・所有者情報の保存方法は実装に委ねる。判定は製品の実経路で使い、テスト専用の別モデルや無条件載せ替え経路を残さない。

### 所有権の事後条件

**attach の所有権を最後に有効な接続を要求した mount に固定し、旧 mount の `updateNSView` が hostingView を奪い返せないこと。**

「最後」は単なる関数呼び出し時刻ではない。新 mount の接続と、すでに所有権を失った旧 mount の再更新を区別する。旧 mount の後着 update を新しい接続要求として昇格させない。

| 操作 | 固定する結果 |
|---|---|
| 未接続の端末を A に attach | `true`、superview は A |
| 同じ端末を新 mount B に attach | `true`、superview は B |
| A の後着 update が再び attach を要求 | `false`、superview は B のまま |
| B の連続 update | `false`、superview は B のまま |
| B 所有中に A が detach | `false`、B の接続・所有権は維持 |
| B が detach | `true`、superview は `nil` |
| B 解放後に、生存している A が改めて attach | `true`、superview は A |
| B 解放後に、新しい C が attach | `true`、superview は C |

最後の A と C は独立したケースとして検査する。旧 mount を永久に接続禁止にして、正当な再利用を妨げない。

### ライフサイクルへの接続

- `TerminalView` の mount ごとに、更新・破棄を跨いで同一性を保つ。SwiftUI の struct 再評価ごとに所有者を新規発行しない。
- `dismantleNSView` または同等に確実な破棄経路から、当該 mount の detach を行う。
- 旧 mount の後着破棄が、新 mount の所有権を解放してはならない。
- 単一コンテナを再利用して coordinator が差し替わる場合は、旧端末の接続・所有権を解放して新端末を接続する。旧端末を再選択した場合も正常に接続できること。
- `window == nil` や frame がゼロであることだけで attach を拒否しない。実測では新しい単一コンテナも接続時点でこの状態になる。
- 実際に載せ替えたときだけ、既存の次 runloop での `scrollToBottom()` を行う。拒否した旧 update と同一 mount の update はスクロールを予約しない。

PM 判断:

- 上記 API で表現できない具体的な実装上の障害が判明した場合は、PM が公開面とテストを同時に再契約する。実装役だけで凍結済み API を変更しない。

## 不変条件

- 表示切替で `TerminalCoordinator`、SwiftTerm の `terminalView`、`hostingView` を再生成しない。PTY の再起動、バッファ reset、出力再投入によって空白を隠さない。
- PTY の入力・出力、出力バッファ、スクロールバック、既存の追従・読み戻しを保持する。
- `TerminalHostingView.setFrameSize` のサイズ変更判定、次 runloop での全行 refresh、`needsDisplay` の既存経路を保持する。
- `TerminalCoordinator.sizeChanged` → `onResize` → `SessionViewModel.handleResize` の通知と、spawn／resize の既存分岐を保持する。
- 所有権判定は `@MainActor` 内で完結させる。本件はメインスレッド上のイベント順序による競合であり、待ち時間の追加や再試行タイマーで解決しない。
- 所有権確認を、subview の除去・追加・制約変更より先に行う。拒否する要求が別端末を container から除去してはならない。
- 所有権情報が破棄済みコンテナやセッションを恒久保持しない。プロセス全体で増え続ける所有者台帳を作らない。
- ADR-0010 の描画中の観測状態変更回避と、既存の非同期スクロール方針を維持する。
- ADR-0116 の `.appServer` 用 live resize 対策を維持する。現行 `GridChatColumn` の幅保持・resize 開始終了通知を変更しない。PTY の所有権修正をチャット描画へ広げない。
- グリッドのタイル配置、出力描画、選択、ドラッグ、クリップ、余白、フォーカスの既存経路を維持する。
- `[BUG01]`、`Bug01Trace`、調査用ファイル出力・`print`・追加 `os_log` を製品に残さない。

### 変更してよいファイル／スコープ

`allowed_paths` は実装役の変更許可であり、列挙ファイルをすべて変更する要求ではない。

| ファイル | 許容する変更 |
|---|---|
| `TerminalView.swift` | 所有権判定、載せ替え、更新・破棄の接続 |
| `TerminalCoordinator.swift` | 必要な場合に限り、セッション単位の所有権保持 |
| `TerminalHostingView.swift` | 必要な場合に限り、hostingView に付随する所有権保持 |
| `docs/agent-output/task-39.md` | 原因、変更、検証結果、未検証・警告の開示 |

テスト、`.claude/scripts/task39-wiring.rb`、契約、検証ゲートの登録は PM が担当する。実装役の `allowed_paths` に含めない。

`DashboardView`、`DashboardDetailView`、`SessionView`、`SessionGridView`、`PaneLayoutView`、`SessionViewModel`、Vendor、依存・ビルド設定、仕様・ADR は本草案では変更対象外。

PM 判断:

- TerminalUI 内で解決できず `SessionViewModel` の変更が必要な場合は、必要性と変更箇所を示してから PM が許可パスと配線検査を更新する。
- Dashboard 側の変更は原則認めない。必要と判断する場合は、所有権の修正だけでは解決できない理由と許容差分を PM が契約に明記する。

## 成功基準 1 — macOS 単体で実行できる回帰テスト

PM が `AcceptanceTerminalMountOwnershipTests.swift` を作成して凍結する。既存 `TerminalOpenAtBottomWhiteboxTests`、`TerminalHostingViewTests` と同じく、Swift Testing、`@MainActor`、`@testable import TerminalUI` を使う。

実際の `TerminalCoordinator` と `NSView` を生成し、製品の `TerminalMount` を呼ぶ。SwiftUI の画面起動、AX 権限、実 PTY、課金 CLI、任意の sleep に依存させない。

### 必須ケース

1. **奪い返し防止**  
   A attach → B attach → A の後着再 attach。戻り値は `true, true, false`、最後の `hostingView.superview === B` を直接検査する。
2. **正当な再接続**  
   B detach 後の superview は `nil`。別々のケースで A の再接続と新 C の接続が成功する。
3. **同じ mount の連続 update**  
   初回だけ `true`、以後 `false`。superview、subview 数、端末に接続する有効制約が増減しない。
4. **旧 mount の後着 detach**  
   A→B の後に A を detach しても `false`、superview は B。B の detach は成功し、再度の detach は `false`。
5. **単一コンテナのセッション切替**  
   同じ container で端末 X→Y→X を接続できる。前の端末は外れ、現在の端末だけが接続される。X の遅れた解放要求で Y を外さない。
6. **端末の保持**  
   固定文字列を feed して載せ替えを行い、coordinator・hostingView・terminalView の同一性と既存出力の保持を確認する。既存スクロールバック・追従テストも通ること。

期待する所有者、Bool、文字列は契約から固定する。実装の owner getter、判定関数、ソース解析結果から期待値を生成しない。全コンテナを実ウィンドウに載せず実行し、`window == nil` でも新 mount が接続できることを含める。

### 実行方法と凍結

リポジトリルートで実行する。

```bash
~/.agents/scripts/compact-test task39-terminalui \
  bash macos/scripts/run-swift-tests.sh TerminalUI
```

`run-swift-tests.sh` は任意のパッケージ指定を受け、内部で `swift test --package-path Packages/TerminalUI` を実行する正本である。既定対象には TerminalUI が含まれないため、明示指定する。除外スイートを追加して合格させない。

- PM は現行の `attach` だけでも実行できる A→B→A のケースを修正前に実走し、期待 B に対して A になるアサーション失敗を記録する。新設 detach API の欠落によるコンパイル失敗だけを、奪い返し防止テストの効力の証拠にしない。
- 凍結後は実装前 baseline に対する変異検査で、この失敗を検出できることを確認する。
- 既存 `TerminalOpenAtBottomWhiteboxTests` には `updateNSView` の guard と非同期スクロールのソース文字列検査がある。削除・弱体化して通さない。
- acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

PM 判断:

- 本起草ではテストを作成・実行していない。修正前の失敗箇所、凍結 SHA、変異検査結果は PM が凍結時に追記する。
- 既存ソース文字列検査と必要なライフサイクル変更が衝突する場合は、PM が元の保護対象を維持する検査へ改め、凍結する。

## 成功基準 2 — 配線検査 rb と自己検査

PM が `.claude/scripts/task39-wiring.rb` を作成し、通常検査と `--selftest` を検証ゲートへ登録する。Ruby 標準ライブラリで実行できること。

### baseline の扱い

- `TASK39_BASELINE` は PM が固定した実装前の完全なコミット SHA とし、`baseline_commit` と一致させる。
- 未設定、空、不正 SHA、存在しない commit、契約との不一致は理由を出して非 0 終了する。
- `HEAD`、`HEAD~1`、ブランチ名、現在の HEAD を自動取得して baseline にする処理は禁止。
- 比較元は固定 SHA の製品ファイル、比較先は現在の作業ツリー。未コミット変更と対象範囲内の新規製品ファイルも検査する。
- 同じ HEAD の内容を両側へ読み込む自己比較、検査対象が見つからない場合の黙示的な成功は禁止。

### 検査項目

| 対象 | 合格条件 |
|---|---|
| `DashboardView` | 詳細画面の呼び出し、モード変更、選択変更の処理が baseline と同じ |
| `DashboardDetailView` | single/grid/team 分岐、`selectedSession`、`focusedID`、PTY／appServer の接続が baseline と同じ |
| `SessionView`・`SessionGridView`・`PaneLayoutView` | 単一とグリッドの `TerminalView` 呼び出し、渡す coordinator、分岐・修飾が baseline と同じ |
| `TerminalView` | 製品の attach が所有権判定を通る。現状 1 箇所の直接 attach 呼び出しを基準とし、追加・移動は所有権修正に必要なものだけ。成功時だけ非同期スクロールする |
| 破棄経路 | 実際の mount 破棄から owner を照合する detach に到達する。テスト専用の detach を置いて終わらない |
| `SessionViewModel` | 現状の直接 attach/detach 呼び出しは 0。coordinator の保持、`bindCoordinator`、`handleResize`、spawn・resize・feed の経路が baseline と同じ |
| サイズ・描画 | `setFrameSize`→非同期 refresh、`sizeChanged`→`onResize` の既存処理が保持される |
| ADR-0116 | `GridChatColumn` の live resize 幅保持・開始終了通知が baseline と同じ |
| 調査コード | 製品ソースに `[BUG01]`・`Bug01Trace` がなく、baseline からの追加 `os_log` やスパイク相当のログ出力がない |

呼び出し数だけで合格にせず、呼び出し元・引数・分岐と owner 判定への到達を検査する。コメントや文字列内の記述を実コードの呼び出しとして数えない。既存の正当なログを一律禁止せず、追加分を検出する。

この草案では TerminalUI 外の製品差分を許容しない。所有権修正に必要な差分の許容は具体的な箇所に限定し、ファイル全体や attach/detach を含む任意の行を検査から除外しない。

### `--selftest`

一時 fixture またはメモリ上のソースを使い、通常検査と同じ判定関数を検証する。製品ファイルを書き換えない。

次を個別に固定する。

- 許容する修正例と、意味を変えない空白・コメントの変更は合格。
- single/grid 分岐の削除・入れ替えは不合格。
- `TerminalView`／`TerminalMount` 呼び出しの削除・重複、別 coordinator への差し替えは不合格。
- owner 判定の迂回、戻り値を捨てたスクロール、detach の未接続は不合格。
- SessionViewModel の resize／feed 経路変更、live resize 対策の除去は不合格。
- `[BUG01]`、`Bug01Trace`、追加 `os_log` の各混入は不合格。
- baseline 未設定・不正・`HEAD` 指定、必要なファイル・関数がない入力は不合格。
- コメントや文字列に必要な呼び出し名だけを置いても、不足する実コードの代用にならない。

自己検査は各 fixture の期待合否と実結果が一致した場合だけ exit 0。通常検査で不正例を実際に拒否できることを示す。

```bash
~/.agents/scripts/compact-test task39-wiring-selftest \
  ruby .claude/scripts/task39-wiring.rb --selftest
```

```bash
TASK39_BASELINE='<PM 固定 SHA>' \
  ~/.agents/scripts/compact-test task39-wiring \
  ruby .claude/scripts/task39-wiring.rb
```

PM 判断:

- 所有権実装に伴う attach 呼び出しの追加・移動は、PM が必要性と許容形を固定する。通常検査を現在の実装に合わせて自動更新しない。

## 成功基準 3 — App ビルドと PM 目視ゲート

### 統合検証・App ビルド

PM は既存の `.claude/verify.sh` を正本として実行する。同スクリプトは関連 8 パッケージ、更新機能の隔離テスト、`git diff --check` を実行する。個別の TerminalUI テストの成功だけで統合検証済みとしない。

```bash
~/.agents/scripts/compact-test task39-integration \
  bash .claude/verify.sh
```

次の App ビルドを `macos/` で実行し、exit 0 と `BUILD SUCCEEDED` を確認する。**PM ゲートの必須項目**とする。

```bash
xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build
```

ビルド対象と再現に使う `.app` が修正版に一致することを記録する。別 worktree の古い成果物で代用しない。プロジェクトが未生成なら、既存 `macos/project.yml` に基づく `xcodegen generate` を前処理として記録し、指定ビルドを再実行する。

ビルド、テスト、配線検査、目視は別々に結果を記録する。失敗・警告・実行できなかった項目を省略しない。

### PM 目視ゲート

`investigation-bug-01-runtime.md` の再現 A/B/C を、修正版の隔離 Debug で再実施する。課金セッションは禁止。Release のアプリ、設定、データ、プロセスには触れない。

準備:

- `sh -c 'seq 1 30; exec cat'` の custom agent を 2 本だけ起動する。
- `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON` を検証専用に分離し、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を用いる。
- 前回と同じく `open -n`、日本語表示、`-ApplePersistenceIgnoreState YES` を用いる。操作対象は今回起動した Debug の PID に限定する。
- 実際のセッション名・IDを記録する。前回の花名や座標を固定値として流用しない。
- 操作前に両セッションの出力を確認する。

| 再現 | 操作 | 合格条件 |
|---|---|---|
| A：AX 操作・選択不変 | 1 本目を選択 → グリッドボタン AXPress → 2 本目の見出しへ前回と同じ AX 操作 → 単一ボタン AXPress | 選択が変わらなかったことを区別して記録し、選択中の端末に出力あり |
| B：マウス相当・選択変更 | グリッドで 2 本目の見出しを `axclick.py` でクリック → 選択成功を確認 → 単一ボタン AXPress | 2 本目の単一表示に出力あり |
| C：選択固定・3 往復 | 1 本目を選択したまま、見出し操作なしで grid→single を 3 往復 | 単一表示が 3 回とも出力あり。各回のグリッドも両タイルに出力あり |

- モードボタンは AXPress、B の見出しは現在の位置・遮蔽を確認した `axclick.py` を用いる。key code／keystroke は使わない。
- 見出しの AX actions は前回 `AXShowMenu` のみだった。AX 操作の成功応答を選択成功と読み替えず、現在の選択を確認する。
- A・B の各 grid/single と、C の各往復の grid/single を PNG に保存し、PM が画像を開いて出力を確認する。AX の列挙結果だけで描画ありと判定しない。
- 切替後の出力を新しい入力や別セッションの再選択で復帰させて合格にしない。各切替直後の対象画面で判定する。
- 実行時報告に、ビルド識別、Debug PID、隔離先、操作、選択結果、PNG パス、各回の判定を残す。
- 終了時は、この検証で起動した Debug と子プロセスだけを後始末し、残存を確認する。過去報告の PID を使って停止しない。

PM の記録先は `docs/agent-output/visual-task-39.md` とし、実装役の許可パスには追加しない。

PM 判断:

- A の AX 操作が現在の環境で実行不能な場合は、エラーと選択状態を記録して未実施とする。C の成功で A を実施済みに置き換えず、PM が再現条件の変更要否を判断する。
- 本起草時点では成功基準 1〜3 は未実行。修正後のテスト・配線検査・指定ビルド・PNG 確認が揃うまで、BUG-01 を修正済みにしない。

## レビュー観点（Rubric）

- **因果への適合**：B の接続後に来る A の update を拒否しているか。再描画強制、待ち時間、選択変更、端末再生成で症状を隠していないか。
- **所有権の対称性**：attach と detach が同じ所有権規則を使うか。旧 mount の更新・破棄が現在の所有者へ影響しないか。現所有者の解放後は A／C が接続できるか。
- **製品への到達性**：テスト対象の `TerminalMount` が単一・グリッド双方の実経路で使われ、破棄も detach へ到達するか。判定の迂回経路がないか。
- **再利用と寿命**：単一コンテナの coordinator 差し替え、旧セッションの再選択を扱えるか。所有者 ID の再利用や強参照による失効漏れ・保持漏れがないか。
- **副作用の順序**：拒否判定より前に別 subview を外していないか。同一 mount の更新で制約追加・再描画・最下部への引き戻しを起こしていないか。
- **既存挙動の保持**：PTY、バッファ、スクロールバック、サイズ通知、非同期 refresh、ADR-0010／0116、グリッドのタイル描画を保っているか。
- **検査の効力**：期待値が実装から生成されず、修正前の A→B→A を拒否できるか。配線検査は固定 baseline を使い、自己検査で不正例を落とせるか。
- **完了の証拠**：指定 App ビルドと PM の A/B/C 再実行が揃い、C の単一表示 3 回と各グリッドの出力を PNG で確認しているか。未検証・警告を成功扱いしていないか。
- **スコープ**：差分が許可パスと所有権修正に限られ、調査コード、テストの弱体化、Dashboard の不要な変更を含まないか。
## PM 決定（2026-09-13、草案の「PM 判断」への回答）

1. **公開面**: 草案の `TerminalMount.attach/detach -> Bool` を採用。実装上の障害が出た場合は実装役が開示レポートで報告し、PM が公開面とテストを同時に再契約する。
2. **allowed_paths**: TerminalUI の 3 ファイルに限定。`SessionViewModel`・Dashboard 側の変更は開示レポートで必要性を示したうえで PM が契約を更新するまで不可。
3. **RED の記録**: PM 側（テスト作成担当）が、現行 `attach` だけで実行できる「A→B→A の後着 update で superview が A に戻る」ケースのアサーション失敗を凍結前に記録する。`detach` 新設によるコンパイル失敗だけを効力の証拠にしない。
4. **rb の attach 呼び出し検査**: 所有権実装に伴う attach 呼び出しの追加・移動は TerminalView.swift 内に限り許容し、SessionViewModel/DashboardView の呼び出し経路は `TASK39_BASELINE` と一致を要求する。
5. **PM 目視ゲート**: 再現 A（タイル見出し AXPress）は現環境で選択が変わらないことが既知（actions=AXShowMenu のみ）。A は「操作を記録し、単一が空白でないこと」を確認対象とし、選択変更の成否は問わない。B（axclick.py）と C（3 往復）が主判定。
6. **トレース**: `docs/agent-output/bug01-spike-trace.patch` の調査用差分は製品に入れない（rb で `[BUG01]`・`Bug01Trace` の不在を検査）。
