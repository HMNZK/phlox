**要修正です。MUST 1件・HIGH 7件・MEDIUM 2件を確認しました。** 指定の7観点を静的に確認し、退避テストと Ruby は凍結 SHA `57bfa9e` の blob と一致していました。read-only のため、ファイルへ保存せず以下に報告します。

被覆は、取得経路、本文形式、role／メタ属性、候補なし、順序・長さ、行数・バイト境界、不正 JSON・文字コード、DB 成否・フォールバック、元履歴の不変性を軸に確認しました。以下の行番号は実ファイルで確認済みです。

## MUST

### 1. Codex の既存 preview と矛盾する期待値

- **該当行**：[受け入れテスト](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift:494) 494–507行。[実パーサ](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift:249) 249–253、320–324行。
- **理由**：fixture は user より前に `agent_message` の `"system 相当の出力"` を置いています。既存 `scan` は preview 選定時に role を確認せず、`messageText` はこの `event_msg.message` を返します。したがって従来の preview は **`"system 相当の出力"`** です。507行の `"response_item の本文"` は、契約83行の「既存 preview を変更しない」と両立しません。
- **修正案**：preview の期待値を従来値へ修正し、材料は `[Self.responseUser]` のまま維持する。`firstUserAt` も当該 event の `10:02:00` を固定し、新規材料の選定が既存日時へ波及しないことを検査する。

## HIGH

### 2. `firstUserLine`・既存 preview 選定が凍結比較の対象外

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:781) 781–815行。[Claude の既存選定](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift:177) 177–185行。
- **理由**：比較しているのは主に正規化関数と loader 本体です。Claude の `processScannedLine`、両取得器の entry 採否・既存引数、Codex の `scan` 内 preview 選定を比較していません。正規化関数を残したまま、最初の発言・日時・ブランチの選定を変更できます。契約136行の「変更した関数全体を比較対象から外さない」を満たしません。
- **修正案**：新規材料の宣言・収集・引数追加だけを限定的に除外し、残った既存処理を凍結 blob と比較する。先行メタ行と後続 user に異なる日時・ブランチを与えるテストも追加する。

### 3. loader が呼ぶ共有パーサーを保護していない

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:784) 784–789行。[Claude の本文抽出](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift:319) 319–345行。[Codex の本文抽出](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift:320) 320–356行。
- **理由**：Claude の `extractUserText`／`extractTextContent`、Codex の `messageText`／`text`／`read` などは比較されません。loader 本体を変更せずに復元本文を変更できます。また772行の比較は `compact` により**文字列内の空白まで削除**するため、`" "` と `""` の変更も区別しません。
- **修正案**：loader が依存する共有処理も比較対象に含め、Claude の `isMeta` 追加だけを許容する。空白の正規化はコード部分に限定し、文字列リテラルの内容を保持する。

### 4. 材料の「配線」を識別子の存在だけで判定している

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:505) 505–619行。
- **理由**：
  - `connected` は材料引数のない entry 生成を検査対象から落とします。
  - メタ条件は `isMeta == true` 等の存在だけで、除外方向や append との関係を確認しません。
  - Codex は `messageRole` と `titleUserMessages` があればよく、`role == "user"` を要求しません。
  - 加工済み本文の検出は引数内の `normalizedPreview` だけで、別変数を経由する加工を検出しません。
  - `titleSummary` の出所・必須接続を確認しません。文字列を残したソースから呼び出しを検索する箇所もあります。
- **修正案**：実 entry 生成ごとに、収集配列・append 対象・条件・DB 列から引数までの接続を検査する。条件反転、配列破棄、別変数経由の加工、片方の生成経路だけ未接続、文字列内だけの偽装を負例に追加する。

### 5. SQL・DB 優先・読み取り専用の検査が契約を満たさない

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:721) 721–753、790–813行。[実 DB 処理](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift:80) 80–175行。
- **理由**：SQL は4つの断片の存在確認だけで、基準との比較ではありません。809–813行の基準側ループは判定に影響しません。`LIMIT`、列順、bind、DB 選択順は保護されず、DB return 前の追加走査も検出しません。接続フラグも実際の `sqlite3_open_v2` 引数ではなく、関数内の識別子で判定します。
- **修正案**：実行される SQL・bind・DB 選択処理を凍結比較し、接続フラグは呼び出し引数を検査する。DB 分岐への追加読込、LIMIT 削除、列順変更、接続フラグの別変数化を単一違反の負例にする。

### 6. 読込上限の値は確認するが、実際の境界を保護しきれない

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:696) 696–718行。[受け入れテスト](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift:350) 350–380、551–571行。
- **理由**：Ruby は定数値と `index>200` の存在だけを確認し、使用箇所・`break`・処理順を確認しません。Swift 側には Codex の **cwd 一致時の512 KiB境界**がありません。行数境界の直前にある user の採用も固定していません。実 Codex は不正 JSON で `continue` すると末尾の打ち切り判定へ到達しないため、単純な「先頭200行化」は既存動作を変えます。
- **修正案**：既存の読込呼び出し・ループ条件・打ち切り位置を比較する。Claude の200行目／201行目、Codex の index 201／202、不正行を挟む境界、512 KiB 内外の材料を固定する。`onRead` で読込回数・バイト数も検査する。

### 7. selftest の本番接続検査が自己参照になっている

- **該当行**：[配線検査](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task51-wiring.rb:1349) 1349–1363、1584–1591行。マーカー宣言は356行、本番開始は1600行。
- **理由**：`src.index(PRODUCTION_MARKER)` は、本番開始行より先に**定数宣言内の文字列**へ一致します。その後の範囲には検査関数自身の定義が含まれ、`check_frozen_baseline` の存在確認を満たします。負例も全出現を置換するため、実際の本番呼び出しだけを外す欠陥を検証していません。1461–1477行の偽装ケースも、正常配線を残した正例が中心です。
- **修正案**：独立したマーカー行を特定し、本番呼び出しだけを除去・無効化した負例を検査する。偽装ケースは正常配線を除去してから、コメント・文字列・未使用ヘルパー・`if false` 内だけに置き、拒否を要求する。

### 8. Codex の候補なし・複数本文・本文形式の被覆が不足

- **該当行**：[受け入れテスト](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift:435) 435–509、575–608、1014–1038行。[実本文パーサー](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift:320) 320–339行。
- **理由**：Codex の材料テストは短い単一 user が中心です。複数 user の出現順、複数 text block、文字列 content、`event_msg.content`、改行付き長文、system／tool の本文を試していません。loader テストには複数 user がありますが、607行の取得結果は捨てています。assistant の event だけで既存 entry が成立し、材料が `[]` になる経路も未検査です。
- **修正案**：実パーサーが扱う形式を使い、上記の材料配列を固定期待値で検査する。assistant のみの場合は entry と従来 preview を維持し、材料が `[]`、summary が `nil` であることを要求する。

## MEDIUM

### 9. 不正 JSON・文字コードと材料収集の組合せが未検査

- **該当行**：[fixture 作成](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift:858) 858–861、891–895、967–972行。[Claude 行リーダー](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift:21) 21–34行。
- **理由**：新規 fixture は正しい JSON と UTF-8 が中心です。正常本文の間に不正 JSON／不正 UTF-8 がある場合の材料保持や、マルチバイト境界を検査していません。既存テストには Claude の空・壊れたファイルと loader の UTF-8 境界がありますが、新規材料の配列は確認していません。ADR 0040 の18行は、この境界での文字喪失を明示的に扱っています。
- **修正案**：生の `Data` で不正行・境界を作り、前後の有効な材料と既存 preview を検査する。Codex の空ファイル／メタデータのみも追加する。

### 10. 元履歴のファイル集合検査が隠しファイルを見逃す

- **該当行**：[snapshotTree](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift:1096) 1096–1118行。
- **理由**：`.skipsHiddenFiles` により、取得処理が隠しファイルや隠しディレクトリ配下へ保存しても、前後のファイル集合比較に現れません。契約126行の集合不変を完全には検査していません。
- **修正案**：合成 fixture のルートでは隠し項目も列挙し、必要ならディレクトリの追加も記録する。

検証範囲：実パーサー・呼び出し元・参照型を確認しました。ADR 0040／0016／0031との直接の矛盾は確認していません。実 CLI の現行出力全体との一致は **unverified** です。指定された作成担当レポートは未読です。凍結時コンパイル RED は指摘対象にしていません。

実行検証：必須ラッパー経由の Ruby selftest は、`mktemp: ... Operation not permitted` で exit 1となり、Ruby 本体は未実行です。Swift テスト・変異検査も未実行であり、上記の見逃し例は静的解析による指摘です。