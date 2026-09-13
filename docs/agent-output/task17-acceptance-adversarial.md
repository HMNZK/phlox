---
status: completed
task: task-17
verdict: needs_changes
baseline_commit: 3abd7d1
reviewed_head: 50b6726c36689cc425c6f21b6ac6a472c3a608ad
report_saved: false
---

差し戻し。MUST 1件、HIGH 2件、MED 3件。コメント解析によって実コードを検査から隠せる欠陥があり、現状の凍結検査では契約違反を確実に拒否できない。

以下の反例はコードの静的追跡による判定であり、変異検査の実走結果ではない。

1. **MUST — コメント内の引用符で、禁止された実コードを隠せる〔②③〕**

   [task17-wiring.rb:33](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task17-wiring.rb:33) はコメントを認識する前に文字列を退避する。そのため、正しい変更後の通知ボタンに次を加えると、引用符の間にある実際の修飾まで退避され、続く行コメント除去で消える。

   ```swift
   .buttonStyle(.bordered)
   // "
   .disabled(true)
   // "
   ```

   Swift 側では通知ボタンが無効になるが、検査側には正しい `.bordered` だけが残る。action 内の追加呼び出しも同じ方法で隠せる。Button の切り出し、焦点抑制の計数、宣言・全体残余比較が同じ処理に依存するため、後段でも回復できない。

   **rb 側の修正案:** コメントと文字列を同時に識別し、コメント内の引用符を文字列開始と扱わない解析へ修正し、この単一違反と引用符・入れ子コメントだけを加えた正例を追加する。

2. **HIGH — 「歴史的検査」への変更は、回帰保護の引き継ぎとして未完成〔⑤〕**

   [task-17.md:140](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-17.md:140) は先行契約・検査の改訂と再凍結を要求するが、213行の採択調整は再実行を不要としている。後者を上書き裁定と解釈することは可能でも、旧契約側に保護の終了範囲・後継検査が記されていない。

   実コードでも task35 の `section_diff_messages` は対象 Section の変更を拒否し、task38 の `check_invariants` は旧スタイル・焦点抑制を要求する。さらに `.claude/scripts/ui-ux-verify-task.sh:41` の task35 分岐は旧検査を呼ぶ状態で残っている。

   統合 `verify.sh` に含まれないことは、旧検査が歴史専用である根拠にはならない。後継検査の保護力にも指摘1の穴があるため、引き継ぎ完了とは判定できない。

   **契約側の修正案:** 成功基準3を採択後の内容へ統一し、先行契約と実行入口に適用終了範囲・後継検査を明記したうえで、UI-05正例と維持対象の違反負例による引き継ぎ証拠を要求する。

3. **HIGH — 対象ボタンで焦点ゲートが成立する事前証拠がない〔⑥〕**

   [task-17.md:186](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-17.md:186) は通知・管理への `set focused`、属性の読み戻し、可視の焦点表示を必須にする。一方、`visual-task-34.md:131` の成功記録はメイン画面の「グリッド表示」であり、今回の Form 内の標準 `.bordered` ボタンではない。

   この要求が実行不能と断定する根拠もないが、現在の OS・キーボード設定を変えずに成立するかは未確認である。失敗時に未達とするだけでは、契約どおりの製品変更で到達できる合格条件かを凍結前に確かめたことにならない。

   **契約側の修正案:** 同じ設定画面構成・OS条件の標準ボタンで、対象ごとの focused 書き込み可否・戻り値・読み戻し・可視画像を委譲前に実測し、成立しなければ焦点ゲートを再裁定する。

4. **MED — 許可差分の除去が、スタイルの重複・位置変更まで許す〔②③〕**

   [task17-wiring.rb:701](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task17-wiring.rb:701) は `.bordered` が一つでもあれば合格し、739行の処理は該当修飾を個数に関係なく除去する。

   したがって、`.buttonStyle(.bordered)` を二重に付けても残余は同一になる。また更新ボタンの `.bordered` を `.disabled(...)` の後ろへ移しても、除去後の残余は同じになる。契約の「その位置で置換」「許す差分は3置換だけ」を検査していない。

   **rb 側の修正案:** 各対象のスタイル修飾を厳密に1件とし、基準の旧スタイル位置にある1件だけを置換して比較する。

5. **MED — selftest の一部は単一違反ではなく、別の検査で成功できる〔③〕**

   [task17-wiring.rb:1360](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task17-wiring.rb:1360) の「1ボタンだけ旧スタイル」は `NOTIFY_OLD` を戻すため、旧スタイルと焦点抑制の両方を復活させる。スタイル検査が壊れても焦点抑制で NG にできる。

   また1369行の「別ボタンへの適用」は、対象3件の `.bordered` を維持したまま失効ボタンを変更するだけで、「対象からスタイルを外し、別ボタンに置いて偽装する」負例ではない。`has_ng?` も候補文言のどれか一つで成功するため、名付けた検査の保護力を証明しない。

   **rb 側の修正案:** スタイルだけを戻す負例と、対象のスタイルを別ボタンへ移す負例を分け、それぞれ目的の違反診断を必須にする。

6. **MED — SHA不一致とHEAD同値のselftestが、通常実行の条件を検証していない〔③〕**

   [task17-wiring.rb:1490](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task17-wiring.rb:1490) の正常例は `"abc1234"` の形式確認だけで、HEADとの同値・基準blob・祖先関係・凍結整合性を通していない。

   1498行の不一致例に使う `aaaaaaaa` と `bbbbbbbb` は、今回のリポジトリでは両方ともコミット解決に失敗した。判定は「無効」でも成功するため、有効な二つのコミットの不一致比較を削除しても、この負例は成功し得る。

   通常実行には固定blob比較、実装前内容の確認、凍結rb照合があり、HEAD同値を一律拒否する実装ではない。問題は、その性質をselftestの成功から裏付けられないことにある。

   **rb 側の修正案:** 通常実行と共通の基準検証に、有効だが異なるSHA、HEAD同値の実装前blob、実装後blobを入力する独立した正負例を追加する。

検討した入力軸は、3ボタンの所属・件数・ラベル・action・修飾、対象外宣言、コメント／文字列／改行、基準SHAとblob、明暗・有効／無効・hover・焦点である。現行の `SettingsView.swift` では対象3件の位置は一意で、単一のスタイル変更として契約をまとめることと、実装役の `allowed_paths` には追加指摘はない。

タブtitleによるAXPressには `visual-task-38.md:75` の過去観測があり、契約も今回の再照合を要求している。無効ボタンのhoverを表示観察に限定する手順にも矛盾はない。ADR 0019の標準部品方針、ADR 0042の共通グラデーション残置とも、対象3ボタンだけを変更する契約は直接衝突しない。

検証範囲はファイル読解とGit照合。検査rbと製品ソースは `3abd7d1` から差分がないことを確認した。selftestは指定ラッパーの一時ログ作成で `mktemp: ... Operation not permitted`、続いて `No such file or directory` となり exit 1。検査本体、実ソースのRED／正例／変異、Appビルド、AX操作は今回未実行である。探索時の不存在パス参照もあり、AppUpdaterは `PhloxApp.swift` 内で確認した。

読み取り専用環境のため、指定の `docs/agent-output/task17-acceptance-adversarial.md` には保存していない。製品・契約・検査は変更していない。

=== REPORT COMPLETE ===