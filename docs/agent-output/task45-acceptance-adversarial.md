凍結前の修正が必要です。契約に沿う変更を拒否する検査と、未接続・既存動作の破壊を検出できない検査があります。以下は実ファイルの静的確認に基づき、反例の実行結果は未検証です。

## MUST

### 1. scope 検査が契約どおりの省略変更を拒否する

**該当行（実ファイル確認済み）:** [task45-wiring.rb:981–1007](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:981)、[PaneLayoutView.swift:335–340](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift:335)。

**理由:** 名前を含む行だけを比較から除外し、後続の修飾子は残している。既存の `.truncationMode(.middle)` を契約必須の `.tail` に変更すると残余比較が不一致になる。複数行の initializer や名前領域の AX・レイアウト追加も同じ問題を持つ。

**修正案:** 名前 Text と修飾子、必要な読み取り経路を構文単位で扱い、既存操作は別途保護する。実際の未配線コードから契約準拠の変更を加えた scope 正例を追加する。

## HIGH

### 2. 名前・補助花名・help・AX の実接続を検査していない

**該当行（実ファイル確認済み）:** [task45-wiring.rb:663–733](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:663)、[DashboardSidebarView.swift:455–503](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift:455)。

**理由:** `.primary` と `Text(` などの同時出現で判定するため、主名を未使用変数へ読み、実際には旧名を描画しても条件が成立する。補助 Text の欠落、別要素に付いた help・AX・1行制限も識別できない。名前領域の AX 要素化と花名の重複読み上げ防止も未検査。

**修正案:** 生成した表示モデルから各 Text、その名前領域の修飾子まで追跡し、接続を一つずつ切る負例を追加する。

### 3. 現在ノードからチーム子 View・トップバーまでの対応が未検査

**該当行（実ファイル確認済み）:** [task45-wiring.rb:801–899](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:801)、[TeamTimelineView.swift:550–569](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift:550)。

**理由:** チーム検査は親 View と helper のコードを無条件に結合する。子へ履歴名由来の `.legacy` を渡しても、未使用になった現在ノード用 helper が判定を満たす。トップバーも選択 ID とノード検索の存在しか見ず、検索 ID・返却ノードの使用を確認しない。

**修正案:** chip・発言カード・Thinking 行それぞれについて、対象 ID→現在ノード→表示モデル→子の引数を検査する。別 ID、存在するノードを無視した legacy、未使用 helper を単独負例にする。

### 4. 既存操作・状態・余白の恒久保護が不足する

**該当行（実ファイル確認済み）:** [task45-wiring.rb:760–811](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:760)、[PaneLayoutView.swift:341–378](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift:341)。

**理由:** グリッドの workspace・`StatusLabel`、サイドバーの選択・展開、トップバーのエージェント管理操作を十分に検査していない。閉じる操作はコメントを含む文字列の存在確認なので、空の action とコメント内の `onRemove` を区別できない。ドラッグ対象 ID、選択 callback、端末 coordinator、固定余白も凍結式と比較していない。

**修正案:** 契約が保護する操作・状態・余白の式、引数、順序を凍結 blob と照合し、scope なしでも個別改変を拒否する。

### 5. typography の引数・適用位置・委譲経路を保護していない

**該当行（実ファイル確認済み）:** [task45-wiring.rb:935–978](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:935)、[AgentChatRowPolicy.swift:103–108](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentChatRowPolicy.swift:103)、[TeamTimelineView.swift:624–631](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift:624)。

**理由:** 比較対象は参照名だけ。`bodyFontSize(scale: scale)` を `scale: 1` にしても変わらず、適用先変更・後続上書きも検出しない。直接参照のない `ChatItemView`／`GridChatColumn` への委譲も保護されない。

**修正案:** 呼び出し元・対象・引数・適用位置・委譲先を比較し、それぞれの単独改変を負例にする。

### 6. 表示モデルの純粋性と View からの状態更新を保護していない

**該当行（実ファイル確認済み）:** [task45-wiring.rb:736–749](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:736)、[同:921–932](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:921)、[task-44実装 SessionTitleState.swift:78–85](/tmp/ui-ux-wt-44/macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift:78)。

**理由:** 禁止対象は導出・保存関連の4名称だけ。initializer 内の `UserDefaults`／ファイル操作、View の `session.name` 代入、実際に導出へ到達する `receivingUserMessage` を拒否する検査がない。表示モデルは scope 比較からも除外される。

**修正案:** 表示モデルの許可依存・副作用と、描画経路からの状態変更呼び出しを検査し、上記を単独負例にする。

### 7. 必須の比較元 blob が欠落しても検査を省略する

**該当行（実ファイル確認済み）:** [task45-wiring.rb:558–625](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:558)、[同:1003–1025](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:1003)。

**理由:** View の基準 blob 取得失敗を `nil` に変換し、凍結検査・scope 比較が `next` や非 nil 条件で省略する。契約の「blob 欠落は非ゼロ終了」に反する。baseline 未設定という今回の運用とは別の欠陥。

**修正案:** 新設予定の表示モデル以外は、必要 blob の存在・取得成功を必須条件にする。

### 8. 長い導出名の help が省略形でも Swift テストが検出しない

**該当行（実ファイル確認済み）:** [受け入れテスト:133–150](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift:133)、[同:197–209](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift:197)。

**理由:** primary と全文が異なる33文字ケースでは `helpText` を検査していない。help の固定期待値を検査するケースは primary＝全文なので、help を primary から作る誤実装を区別できない。Ruby はモデル内部の文字列生成を検査しない。

**修正案:** 33文字ケースへ、全文・花名・workspace を連結した `helpText` のリテラル期待値を追加する。

## MEDIUM

### 9. 有効名・由来・可変引数に未被覆領域があり、定数の自己確認が混在する

**該当行（実ファイル確認済み）:** [受け入れテスト:19–26](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift:19)、[同:342–360](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceSessionTitlePresentationTests.swift:342)、[task-44実装:98–100](/tmp/ui-ux-wt-44/macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift:98)。

**理由:** 入力軸のうち、前後空白付き／空白だけの旧名、花名なしの正常 derived、異なる fallback・花名・非空 workspace が未被覆。実 API は旧名を保持したまま表示時に trim するため、`name.isEmpty` だけで処理する誤実装を区別できない。359–360行は自身の定数を同じリテラルと比較しており、引数利用の証明にならない。

**修正案:** 上記領域の固定期待値を追加し、自己定数アサーションを異なる引数での出力検査へ置き換える。

### 10. selftest に自己比較とエラー集合の部分確認がある

**該当行（実ファイル確認済み）:** [task45-wiring.rb:1402–1416](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:1402)、[同:1482–1527](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:1482)、[同:1702–1709](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task45-wiring.rb:1702)。

**理由:** scope 正例は同じ `good` 同士の比較で、実物からの正常変更を検証していない。複数の負例は `.select` でエラーを絞り、契約が要求する全エラー集合の比較になっていない。本番 marker の検索も定数宣言側に一致するため、関数定義の存在を本番接続と誤認できる。

**修正案:** 実物由来の変更前後を使い、負例の全エラー集合を比較する。本番 marker は行全体で特定し、本番の呼び出しを検査する。

### 11. ADR 0073 の省略方式と契約の変更が整理されていない

**該当行（実ファイル確認済み）:** [ADR 0073:23](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/adr/0073-overlay-inset-by-measured-height.md:23)、[task-45.md:68](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-45.md:68)、[同:135](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-45.md:135)。

**理由:** active の ADR は `middle truncation` を決定として記載し、実グリッドも `.middle`。契約は `.tail` を要求しつつ「ADR 本文の変更は不要」としている。

**修正案:** 末尾省略への変更を決定として記録し、ADR の該当部分を後継決定で更新する。高さ・余白の決定は維持する。

---

task-44 は `/tmp/ui-ux-wt-44` の HEAD `01db9d0` と照合済み。禁止された報告書は未読、ファイル変更なし。独立したセッション名の「タブ」経路は特定できず **unverified**。

反例実行は一時ファイル作成が read-only 制限で拒否され、テスト本体は未実行。Swift・Ruby selftest・GUI・変異検査の実行結果は **unverified**。短い SHA、凍結時コンパイル RED、実装後の変異検査という運用は指摘対象から除外しました。