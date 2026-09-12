## 判定

**needs_changes**。所有権競合を根本原因とする判断と、TerminalUI内で修正する範囲は妥当です。ただし、配線検査の誤判定と、後着更新の副作用を見逃すテスト不足があり、このままの凍結には問題があります。

以下は実ファイルの静的照合結果です。`--selftest` は必須ラッパーで `mktemp: … Operation not permitted`、続いてログ参照エラーとなり、exit 1で実行前に停止しました。Swiftテスト・ビルド・画面再現は今回未実施です。

## 指摘

1. **HIGH：正しい凍結SHAでも、未コミット実装を検証できない。**  
   根拠：[task39-wiring.rb:249](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:249)、[task39-wiring.rb:1004](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:1004)。

   凍結コミットをFとして、HEADをFのまま製品を実装すると、`detach` の存在で `impl=true` になり、`TASK39_BASELINE=F` を「自己比較」として拒否します。しかし比較対象は **Fの製品コードと変更済み作業ツリー**であり、自己比較ではありません。契約の未コミット変更検査とも衝突します。自己検査の「実装後はHEAD一致を拒否」という期待値も、この誤判定を固定しています。凍結側に実装が含まれていないことと、現在のHEAD一致は分けて判定すべきです。

2. **HIGH：破棄時に「現在そのmountが扱う端末」を解放することを検証していない。**  
   根拠：[task39-wiring.rb:565](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:565)、[AcceptanceTerminalMountOwnershipTests.swift:189](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:189)。

   `dismantleNSView` の検査は `TerminalMount.detach` の文字列上の呼び出し数だけで、引数・到達可能性を確認しません。例えば次の誤りを見逃します。

   - mount生成時のXを保持したままX→Yに更新し、破棄時にもXをdetachする。Yが解放されない。
   - `if false { TerminalMount.detach(...) }` として実行しない。
   - 正しいdetachに加え、owner判定を迂回する除去処理を実行する。

   代替経路も、ファイル中に `viewWillMove(toWindow` とdetachが別々に存在すれば合格します。既存のX→Y→XテストはAPI直接呼び出しなので、この配線不良を落とせません。**X→Y更新後の実際の破棄経路**と、A→B後のA破棄を検査対象にする必要があります。

3. **HIGH：拒否した後着updateが、別端末を消す誤実装を落とせない。**  
   根拠：[TerminalView.swift:44](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift:44)、[AcceptanceTerminalMountOwnershipTests.swift:79](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:79)、[task-39.md:115](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-39.md:115)。

   現行の「別subviewを除去するループ」の**後ろ**に所有権ガードを追加しても、凍結テストでは後着要求先Aが空なので検出できません。所有権競合とセッション切替を組み合わせた、次の反証が必要です。

   ```swift
   // X・Yは別端末のhostingView、A・Bは別コンテナ
   #expect(TerminalMount.attach(X, to: A))
   #expect(TerminalMount.attach(X, to: B))
   #expect(TerminalMount.attach(Y, to: A))
   #expect(TerminalMount.attach(X, to: A) == false)
   #expect(X.superview === B)
   #expect(Y.superview === A)
   ```

   これがないと「Xの奪い返しは拒否するが、AのYを空白にする」修正が合格できます。

4. **MEDIUM：attach追加・スクロールの検査範囲が、許容範囲と一致しない。**  
   根拠：[task39-wiring.rb:531](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:531)、[task39-wiring.rb:550](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:550)、[task-39.md:317](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-39.md:317)。

   PM決定はTerminalView.swift内でattachの追加・移動を許可していますが、検査は`updateNSView`内の直接呼び出しを必須にする一方、他の関数に追加した経路を検査しません。また、guardの**前**に無条件スクロール予約を追加しても、後ろに既存guardを残せば合格します。既存whiteboxも文字列の存在確認なので、この追加副作用を落とせません。許容する追加経路と、全スクロール予約の成功条件を対応させる必要があります。

5. **MEDIUM：ログ検査の自己検査と通常検査が別物で、調査用printを見逃す。**  
   根拠：[task39-wiring.rb:637](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:637)、[task39-wiring.rb:914](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:914)、[task39-wiring.rb:1042](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:1042)。

   自己検査は`check_extra_logs`を使いますが、通常検査は`check_extra_logs_via_git`です。後者にはprint検査がなく、`print("mount …")`の追加を検出しません。また、生テキストの一致行数を比較するため、コメント内の`os_log(...)`追加を誤検出し、同じ行への呼び出し追加を見逃します。通常検査と同じ判定経路で正負例を検証すべきです。

6. **MEDIUM：契約baselineが無効でも、一致確認を省略する。**  
   根拠：[task-39.md:10](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-39.md:10)、[task39-wiring.rb:216](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:216)、[task39-wiring.rb:995](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task39-wiring.rb:995)。

   現在の`baseline_commit`はプレースホルダーです。契約ファイル欠落・不正値も`nil`になり、環境変数との一致確認を省略します。環境変数の未設定をNGにする点は正しいものの、**PMが固定した比較元である保証**がありません。凍結SHAを設定し、契約側の欠落・不正もNGにする必要があります。

## 掃いた項目

1. **因果：問題なし。** [実行時報告:86](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/docs/agent-output/investigation-bug-01-runtime.md:86)では新単一へのattachが成立しており、再要求不足は奪い返し後に復帰しない理由です。既存製品に明示的dismantleはなく、その順序を別の一次原因とする証拠もありません。
2. **公開面：表現可能。ただし指摘2。** コンテナNSViewをmountの同一性として使い、現在の接続端末を保持すれば3ファイル内で扱えます。struct再評価・coordinator差し替え後の破棄を保証する検査が不足しています。
3. **受け入れテスト：指摘3。** 表8行は各1ケース、追加2ケースも存在し、superviewは`===`。変化前後の制約比較はトートロジーではなく、A永久禁止も再接続テストで落とせます。
4. **配線検査：指摘1・2・4・5・6。** Dashboard／SessionViewModelと既存whiteboxのファイル不変比較はスコープに整合しますが、変更を許すTerminalView側の検査が不足しています。
5. **allowed_paths：問題なし。** [SessionViewModel.swift:633](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift:633)は入力・サイズ通知の接続でありmount操作はありません。Dashboard側を変更する具体的必要性は認めません。
6. **不変条件：方針の衝突なし。ただし指摘3・4。** サイズrefresh・PTY通知の保持は妥当で、[GridChatColumn.swift:26](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift:26)のADR-0116対策も別経路です。副作用順序とスクロール予約の検査を補う必要があります。
7. **PM目視ゲート：問題なし。** 2本の固定出力と待機するcat、切替直後のPNG、入力による復帰禁止で空白改善を判定できます。PM決定によるAの扱いも明確です。PTY継続・履歴保持の証明は別の検査に依存します。
8. **1タスク1契約：問題なし。** 所有権モデルとライフサイクル接続は、同じ永続端末を守る一体の修正です。新旧イベントの交錯と再利用時の状態管理がdeepの具体的根拠です。
9. **ユーザー固有の判断：なし。** 指摘は技術的な契約・検査の補正であり、PM側で解決できます。

## ユーザーへの問い

ありません。