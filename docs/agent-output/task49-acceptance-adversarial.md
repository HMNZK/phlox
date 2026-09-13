**MUST 1件、HIGH 5件、MEDIUM 3件です。** 正しい実装でも Ruby が失敗する構造不一致と、契約違反を検出できない箇所があります。退避テストと Ruby は `4018caa` の凍結 blob と一致しています。

## MUST

### 1. 実際の ViewModel を解析できない

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:849](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:849)、同ファイル1079行。[ChatSessionViewModel.swift:13](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift:13)
- **理由:** 製品は `public final class`、検査は `extract_struct_body` を使用しています。凍結時点も同じ class なので、保護対象3宣言が「解析できない」になります。自己テストだけ架空の `struct ChatSessionViewModel` を使っており、この不一致を隠しています。task-49 の許可範囲を正しく実装しても解消しません。
- **修正案:** class を解析し、実際の凍結 VM を正例にする。併せて850行の「比較元・比較先が欠落したら成功」を非ゼロ判定へ変更する。

## HIGH

### 2. View の凍結比較がなく、表示条件・高さ・composer の保護が抜けている

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:829](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:829)、同875行。[ChatSessionView.swift:145](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift:145)
- **理由:** `invariant_errors` は両 View を比較しません。表示条件・レイアウト・composer も名前の存在確認だけです。条件を `shouldOfferHistoryStart || true` にする、`maxCardHeight` を固定値へ変える、`.padding(.bottom, bottomInset)` を削除する変更を検出できません。高さ制御関数の不変だけでは、[ADR 0073:22](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/adr/0073-overlay-inset-by-measured-height.md:22) の配線を守れません。
- **修正案:** 契約154行どおり、表示変更を認める部分だけ除外して残部を凍結比較する。条件、計測値、引数、余白、composer の操作配線それぞれに単一違反の負例を追加する。

### 3. 行と選択先の対応・クリック以外からの再開を検査していない

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:758](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:758)、同777・786・817行。[ChatHistoryStartView.swift:31](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatHistoryStartView.swift:31)
- **理由:** `ForEach(entries)` と `onSelect(entry)` がどこかにあれば成立します。例えば `row(for: entries[0])` への変更で全行が先頭履歴を選ぶ状態を検出できません。モデルの `entry:` 引数も未検査です。また、既存 Button を残して `.onAppear { onSelect(entry) }` を追加しても拒否条件がありません。既存の再開テストは VM を直接呼ぶため、この View の欠陥を補いません。
- **修正案:** `ForEach` の要素→行引数→モデル→Button action→親の再開引数を同じ値として確認する。別 entry、重複呼び出し、表示時再開、Button 撤去を負例にする。

### 4. 補助表示が未接続でも、help・AX が文字列の偽装でも成立する

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:765](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:765)、同773〜789・1013〜1027行。
- **理由:** `projectName` の描画と `lastUsedAt` の受け渡しを検査していません。`Text("固定名")`、`formattedLastUsed(nil)` でも必要な検査条件が残ります。「最終利用」の表示も正例にありません。さらに `.help("presentation.fullTitle entry.sessionID")` のような文字列が参照として認められます。案内・AX identifier・ブランチ・1行制限も、それぞれ正しい描画対象への接続を確認していません。
- **修正案:** 実際の Text と修飾子の対象・引数を確認する。補助値の固定化、文字列による参照偽装、案内を非表示用途へ移動する負例を追加する。

### 5. 導出器の戻り値を捨てても再利用扱いになり、設定・時計への依存も通る

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:460](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:460)、同489・713行。
- **理由:** 導出呼び出しと `.title`／`.fullTitle` の存在を別々に確認しています。導出結果を `_ = derived` で捨て、`self.title`／`self.fullTitle` に独自処理の結果を代入する構成を排除できません。禁止依存も限定列挙で、`UserDefaults.standard` や `Date.now` は対象外です。正しい表示値を返しながら設定を書き換える実装は、モデルの期待値比較でも検出できません。
- **修正案:** 導出結果から公開フィールドへの代入を確認する。結果破棄・別値代入・設定書き込み・時計参照を、本番と同じ検査関数の負例にする。

### 6. 材料の優先順・summary・未加工引き渡しに未被覆領域がある

- **該当行（実ファイル確認済み）:** [凍結テスト:135](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift:135)、同148〜200行。[SessionTitleDeriver.swift:113](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift:113)
- **理由:** 材料の有無・順序、除外、summary、文字境界、パス、日時の軸で照合すると、次が未検査です。

| 未被覆領域 | 見逃す実装 |
|---|---|
| 適格なユーザー材料が複数 | 最後の材料を採用する |
| `[]` ＋適格な summary | 空配列なら summary も調べず終了する |
| nil＋不適格 preview＋適格 summary | preview 失敗後に終了する |
| summary 内のコマンド・改行・長文 | summary だけ導出器を通さない |
| 本文先頭の4空白・タブ | 本文全体を trim してから導出器へ渡す |

特に `[]`＋summary は [CodexSessionHistory.swift:167](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift:167) が実際に生成する状態です。

- **修正案:** 各領域へ固定期待値を追加する。例えば `["    説明\n履歴表示を修正"]` の期待値を「履歴表示を修正」として、先頭空白の保存を検査する。

## MEDIUM

### 7. 着手時の変更範囲検査が2ディレクトリに限定されている

- **該当行（実ファイル確認済み）:** [task49-wiring.rb:888](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:888)
- **理由:** SessionFeature と DashboardFeature/Spawn 以外を列挙しません。実際の provider 注入元である `Environment/AppEnvironment.swift`、`Dashboard/SessionSpawnService.swift`、AgentDomain 等の許可外変更が `TASK49_SCOPE_CHECK=1` でも対象外です。
- **修正案:** リポジトリ全体の変更を取得し、契約の許可パスと照合する。統合中の他タスク変更を区別する必要があれば、その比較範囲を契約で固定する。

### 8. 公開 API の型・アクセス範囲を固定できていない

- **該当行（実ファイル確認済み）:** [凍結テスト:8](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift:8)、同59・70行。[task49-wiring.rb:713](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task49-wiring.rb:713)
- **理由:** `@testable import` と値の等値比較では、public 宣言や非 Optional の String を固定できません。Ruby も公開メンバーの型・`Sendable` を確認していません。
- **修正案:** 公開宣言を検査し、既存テストに非 Optional 型と `Sendable` を要求するコンパイル検査を追加する。

### 9. entry 不変テストは値型の自己比較にとどまる

- **該当行（実ファイル確認済み）:** [凍結テスト:329](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift:329)、[ClaudeSessionHistoryEntry.swift:9](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift:9)
- **理由:** entry は全フィールドが `let` の値型で、通常の値渡しです。呼び出し元の同じ値を前後比較する検査は、通常の Swift では構造上成立します。元履歴・設定への副作用を保護する検査にはなりません。
- **修正案:** 契約指定の値不変確認として残し、副作用保護の証拠には数えない。副作用の検査は指摘5で別に担保する。

検証範囲は実ファイルと凍結 blob の静的照合です。自己テストはラッパーの `mktemp: ... Operation not permitted` で起動前に失敗しました。Swift・Ruby の実行結果、偽装例の実行再現は **unverified**。ファイル変更はありません。