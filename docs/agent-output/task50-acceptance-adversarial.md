**差し戻し：MUST 3件、HIGH 7件、MEDIUM 2件です。** 契約・凍結テスト・配線検査・関連実コード・ADRを静的に照合しました。自己検査は `compact-test` の `mktemp: Operation not permitted` で開始できず、変異の再現実行は **unverified** です。ファイル変更、禁止されたテスト作成報告の閲覧は行っていません。

## MUST

**M1 — 正常な Codex 設定画面を「表示時の保存」と誤判定する**

- **該当行（実ファイル確認済み）:** [rb:897](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:897)、[CodexSettingsPane:34](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/App/AgentConsole/Codex/CodexSettingsPane.swift:34)、同77・117行。
- **理由:** ファイル内に `onAppear` と `applyConfig` が共存するだけで拒否する。実コードは表示時に下書きを同期し、Picker 操作時に保存する正常な構成であり、この条件に該当する。既存挙動を維持した実装が合格できない。
- **修正案:** `onAppear` から呼ばれる処理を追跡し、その経路への保存追加だけを拒否する。既存の下書き同期を正例に含める。

**M2 — 凍結基準が task-48 完成実装を含んでいない**

- **該当行（実ファイル確認済み）:** [契約:34](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-50.md:34)、同221行、[rb:520](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:520)。
- **理由:** `git ls-tree e95ebf8` で `UIWording.swift` が存在しないことを確認した。同 SHA の `ComposerSettingsControls.swift` も Plan などが直書きのまま。さらに rb は task-48 完成実装の存在を検査しない。これは新設型のコンパイル RED や短い SHA の問題ではなく、依存実装を保護する比較基準の欠落。
- **修正案:** task-48 完成実装を取り込んだ時点で再凍結し、その正本・共有ファイルの必要な接続を基準側でも検査する。

**M3 — 旧検査との整合調整が未完了**

- **該当行（実ファイル確認済み）:** [契約:260](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-50.md:260)、[task38 rb:831](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:831)、同1094・1201行、[既存メニューテスト:31](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/ComposerModeMenuAcceptanceTests.swift:31)。
- **理由:** task38 は旧 footer の逐語一致と `BypassToggleRow` 本体の不変を要求するため、契約どおりの変更を拒否する。既存メニューテストも言語指定なしの旧英語期待値のままで、契約が要求する日英検査へ改訂されていない。
- **修正案:** ディスパッチ前に、権限表示の差分だけを許す旧検査へ改訂・再凍結する。内部値・順序・保存処理の保護は維持する。

## HIGH

**H1 — 「基準との差分検査」が大部分で実装されていない**

- **該当行（実ファイル確認済み）:** [rb:845](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:845)、同1327行。
- **理由:** UI側の検査は主に現在コードの部分文字列検索で、基準側の action・Binding・tag・項目列と比較していない。`.tag(option)` の値変更、Toggle の Binding 置換、通常項目の並べ替え、設定グループ削除などを保護できない。task-48 保持も `.planOption` または `.permissionLabel` の存在確認にとどまる。正例の `check_invariants(good, good)` は差分検出能力の証明にならない。
- **修正案:** 許可された表示差分だけを除外し、残りを凍結 blob と比較する。文字列の空白・補間を保持し、切り出し失敗は拒否する。

**H2 — 起動条件の変更と必要 blob の欠落を見逃す**

- **該当行（実ファイル確認済み）:** [rb:395](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:395)、同841・906・937行、[SessionSpawnService:918](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift:918)。
- **理由:** 起動処理は一部の単語の出現数だけを比較する。`never`／`on-request` の交換や条件反転を検出できない。実際の引数を持つ `AgentDescriptor.swift`、`CursorChatClient.swift`、`CompositionRoot.swift` も比較対象外。取得できない blob は `next` で検査を省略する。
- **修正案:** 関連する起動処理を基準と比較し、必要ファイル・blob の欠落を非ゼロ終了にする。条件反転と ON/OFF 交換を負例へ追加する。

**H3 — 未使用の呼び出し・文字列による配線偽装を拒否できない**

- **該当行（実ファイル確認済み）:** [rb:308](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:308)、同551・556・746行。
- **理由:** `body` 内の呼び出し結果が実際の表示へ渡るか追跡していない。未使用変数へ正本の結果を代入して旧表示を残しても、必要トークンが揃う。`UIWording.permission` と `kind:` の検索には文字列を残したコードも使うため、実在する別の `UIWording` 参照とダミー文字列の組合せにも弱い。
- **修正案:** 呼び出しの引数・戻り値から `Text`／`Label`／チップまでの接続を検査する。未使用代入、文字列、コメント、`if false` をそれぞれ単独の負例にする。

**H4 — ON/OFF の片側しか見えない実装を正例にしている**

- **該当行（実ファイル確認済み）:** [契約:127](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-50.md:127)、[rb:705](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:705)、同1142行。
- **理由:** 正例が `Text(isEnabled ? wording.onExplanation : wording.offExplanation)` となっており、「反対側の意味を隠さない」という契約に反する。検査は両プロパティ名の存在しか要求しない。descriptor から正しい agent を選ぶ処理や、footer の実表示への接続も検査していない。
- **修正案:** OFF・ON の説明を同時に描画する正例へ変更する。片側表示、agent 固定、未使用 footer、固定エージェント一覧を個別に拒否する。

**H5 — 管理画面の必要な表示箇所が検査から抜けている**

- **該当行（実ファイル確認済み）:** [rb:753](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:753)、同1224・1259行、[CursorPermissionsPane:22](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/App/AgentConsole/Cursor/CursorPermissionsPane.swift:22)。
- **理由:** Cursor の導入文を検査していない。設定ペインでは項目名・選択肢ラベル・現在値説明を個別に要求しておらず、正例自体が Codex の sandbox 選択肢を `Text(option)` のまま残し、Cursor の sandbox コントロールを省略している。バケット見出しと Picker ラベルの片方だけ旧文言でも区別できない。
- **修正案:** 実際の `editor`、`bucketSection`、`settingRow`、`choiceControl`／`control` ごとに表示接続を検査する。各箇所を一つだけ旧表示へ戻す負例を追加する。

**H6 — 通常・省略メニューをエージェント別に検査していない**

- **該当行（実ファイル確認済み）:** [rb:634](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:634)、同657・678行、[実メニュー:351](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ComposerSettingsControls.swift:351)、同838行。
- **理由:** View 全体に `composerModeOptions` と `option.explanation` が一つあれば成立する。Claude だけ接続して Codex／Cursor の説明を残す変更を検出できない。選択中表示も Claude の kind の存在確認が中心で、Codex／Cursor のチップやサーバー由来プロフィール一覧の実接続を保証しない。
- **修正案:** 3エージェント×通常・省略メニューと各選択中表示を別々に検査し、実際の `agentRef`・現在値・プロフィール一覧を照合する。

**H7 — 表示言語の受け渡しを保証していない**

- **該当行（実ファイル確認済み）:** [rb:375](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:375)、同651・749行、[PhloxApp:125](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/App/PhloxApp.swift:125)、同139行。
- **理由:** 一部の直書き言語コードを禁止するだけで、`languageCode` が注入された locale から来るか確認していない。省略メニューと Codex／Cursor 設定ペインには同等の確認もない。固定変数や OS 言語を渡す実装は、正本の単体テストが通ってもアプリ内言語設定に追随しない。
- **修正案:** 各表示経路について環境 locale から正本の引数まで確認し、固定変数・別 locale・引数無視を負例へ追加する。

## MEDIUM

**D1 — 未知値・未設定・言語の入力領域が一部未被覆**

- **該当行（実ファイル確認済み）:** [受け入れテスト:304](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptancePermissionWordingTests.swift:304)、同448・493行。
- **理由:** 被覆軸は agent・kind・既知／未知／nil・原文保持・言語・再取得。Codex／Cursor の sandbox 未知値、Codex sandbox の英語 nil、Cursor approval の英語 nil、Cursor sandbox の日本語 nil、起動説明の地域付き／未対応言語を検査していない。空白・改行を含む未知値の原文保持も未被覆。また agent だけを変える負例がなく、引数の無視を検出できない。
- **修正案:** 上記の未被覆領域へ独立リテラルのケースを追加する。agent と kind が不一致の場合の扱いは、期待値を決めてから凍結する。

**D2 — 説明の切り詰め検査が `SettingsMenuRow.lineLimit(2)` に限定される**

- **該当行（実ファイル確認済み）:** [rb:561](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task50-wiring.rb:561)、[契約:193](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-50.md:193)。
- **理由:** `.lineLimit(1)`、固定高による切断、極端な縮小を拒否しない。設定行・footer・管理画面の説明も対象外なので、長文を読めなくする実装を配線検査が受け入れる。
- **修正案:** 契約対象の説明表示箇所で折り返しを確認し、行数制限・固定高・縮小を個別の負例にする。実際の可読性は契約どおり PM 目視ゲートで確認する。