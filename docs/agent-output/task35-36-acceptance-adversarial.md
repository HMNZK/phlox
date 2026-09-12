## 判定

**needs_changes**。正しい実装を拒む配線検査、契約違反を見逃す検査、既存 ADR と相反する契約が残っています。指定の 7 観点を確認しました。コード変更はしていません。

実走は未検証です。受け入れ対象のパッケージテストと配線検査を計 4 回、指定ラッパー経由で試しましたが、いずれも検査本体の起動前に exit 1 でした。

```text
mktemp: mkstemp failed on /tmp/tmp.…: Operation not permitted
/Users/ryosuke/.agents/scripts/compact-test: line 26: : No such file or directory
cat: : No such file or directory
```

`swiftc --version` もキャッシュ作成拒否、FSEvents・キャッシュディレクトリ取得の警告を出し、`permissionDenied` で失敗しました。以下の反例は静的に確認したもの／提案であり、実走結果ではありません。

## 指摘

1. **[MUST] 新設する見本 View が、それ自体で「許可外の差分」になる。**  
   根拠: [task35-wiring.rb:345](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:345)、[SettingsView.swift:383](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/App/SettingsView.swift:383)。  
   `replace_struct` は存在する構造体をプレースホルダーに置換します。baseline `18bbcc4` に `ThemeAppPreview` はないため、既存 View と同階層に正しく追加すると、現在側だけに `/*stripped:ThemeAppPreview*/` が残り比較が失敗します。  
   **修正案:** 対象構造体を両側から空文字で除去する。検査自体に次の正例を追加する。

   ```ruby
   before = "struct SettingsView {}"
   after = before + "\nprivate struct ThemeAppPreview: View {}"
   # 対象構造体を除去した残余は同一でなければならない
   ```

2. **[HIGH] task-36 の受け入れテストに、実装欠落とは別の型エラーがある。**  
   根拠: [AcceptanceAgentConsoleNavigationModelTests.swift:85](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceAgentConsoleNavigationModelTests.swift:85)。  
   3 箇所で `[(String, String)]` を配列の `==` で比較しています。タプル同士の比較演算子と、配列比較に必要な要素の `Equatable` 準拠は別です。通常の Swift 6 設定で使える比較ではありません。[Swift の提案と差し戻し状態](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0283-tuples-are-equatable-comparable-hashable.md)にもこの制約が示されています。ローカルのコンパイル診断は未検証です。  
   **修正案:** ID と title の配列を別々に比較する。期待する 19 組は変えない。

   ```swift
   #expect(claude.sections.map(\.rawValue) == Self.claudePairs.map(\.id))
   #expect(claude.sections.map(\.title) == Self.claudePairs.map(\.title))
   ```

   [著者報告:28](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/docs/agent-output/tests-task-35-36.md:28)の「新 API 未実装のためコンパイル RED」は、掲載された Ruby ログだけでは原因を限定できません。配置後の Swift 診断で切り分けが必要です。

3. **[HIGH] 配線検査が、主要な接続の誤りを見逃す。**  
   根拠と具体的な反例は次のとおりです。

   | 検査箇所 | 検査条件を満たす契約違反 |
   |---|---|
   | [task35-wiring.rb:199](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:199) | 両 View に同じ変数を渡すだけで、その変数が候補の `make` 結果かは確認しない |
   | [task35-wiring.rb:227](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:227) | 背景色を 2 回書いても、入力欄の下地には使わない。色帯を `model.terminalSwatches.reversed()` で描いても検出しない |
   | [task36-wiring.rb:307](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:307) | Picker の set 内で `make(agent: newAgent, selection: nil)` を呼び、結果を捨てる |
   | [task36-wiring.rb:335](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:335) | `.accessibilityAddTraits(.isButton)` だけ残し、選択 trait を削る |
   | [task36-wiring.rb:524](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:524) | `isAvailable: model.isAvailable && false` が部分一致を通る |

   **修正案:** 呼び出しの存在だけでなく、引数全体・戻り値の代入先・対応する描画箇所を検査する。上記の変異を負例にする。表示の到達性は契約どおり AX／目視で別途確認する。

4. **[HIGH] task-36 は「既存機能を固定 SHA と比較する」と約束しているが、実際は一部の単語だけを検査している。**  
   根拠: [task-36.md:160](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:160)、[task36-wiring.rb:403](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:403)、[task36-wiring.rb:579](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:579)。  
   変更対象について baseline 比較しているのは主に detail の対応表です。例えば Codex の「サンドボックス」行、Finder 操作、`loadMCPServers()`、WindowView の `.task` を削っても、その欠落を検査しません。init の引数変更や ConsoleModel の状態保持の破壊も見逃します。  
   **修正案:** 変更しない toolbar・reload・init・設定節などを baseline と比較する。messageBar は case ごとの error／info／dismiss の対応を固定する。契約に書いた保持対象と検査対象を一致させる。

5. **[HIGH] ナビゲーションの入力と出力の組合せに穴がある。**  
   根拠: [AcceptanceAgentConsoleNavigationModelTests.swift:125](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceAgentConsoleNavigationModelTests.swift:125)、[同:155](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceAgentConsoleNavigationModelTests.swift:155)。  
   入力は `3 agent ×（19 selection＋nil）=60 組`。所属外 selection は 38 組中 6 組だけです。また `sections` は nil 入力時にしか検査していないため、**「項目を選ぶと sections が空になる」実装でも既存テストは通ります**。移設後の `section.agent`、section の `allCases` 順序も直接固定していません。  
   **修正案:** 既存のリテラル表を使い、60 組で agent・sections・selectedSection・locationText を検査する。

   ```swift
   let model = AgentConsoleNavigationModel.make(
       agent: .codex, selection: .codexTrust
   )
   #expect(model.sections.map(\.rawValue) == Self.codexPairs.map(\.id))
   #expect(AgentConsoleSection.codexTrust.agent == .codex)
   ```

   ThemePreview 側も [同テスト:105](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceThemePreviewModelTests.swift:105)の 10 テーマループでは、本文・選択行・入力欄の文言が未検査です。モデル全体の `Equatable`／`Sendable` 要件も、ジェネリック制約で確認すべきです。

6. **[MED] Ruby の構文処理が、正しい等価構文を拒む。**  
   根拠: [task35-wiring.rb:23](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:23)、[task36-wiring.rb:186](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:186)、[同:557](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:557)。  
   `//` 除去は文字列内の URL まで壊し、`/* ... */` は除去しません。括弧対応も文字列を区別しません。さらに標準の次の記法は、label クロージャを読まないため拒否されます。

   ```swift
   DisclosureGroup(isExpanded: $showsCLIDetails) {
       // バージョンとパス
   } label: {
       Text(summary.cliDetailsTitle)
   }
   ```

   `.pickerStyle(MenuPickerStyle())` や tint の `return` を省く switch 式も同様です。  
   **修正案:** 文字列・コメントを区別し、許容する標準構文の正例を検査する。著者が検査都合で加えた制約を、暗黙の契約にしない。

7. **[HIGH] task-35 と task-36 を統合すると、task-36 の不変性検査が正当な変更を拒む。**  
   根拠: [task36-wiring.rb:38](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:38)、[同:585](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task36-wiring.rb:585)。  
   task-36 は SettingsView 全体を `18bbcc4` から無変更と要求します。一方 task-35 は同ファイルの変更が必須です。双方の `depends_on: []` とも噛み合いません。  
   **修正案:** 「task-36 自身が SettingsView を変更しない」はタスク差分で判定する。あるいは task-35 統合後の固定 SHA を task-36 の比較元として明示する。HEAD 自己比較にはしない。

8. **[HIGH] UX-12 は active な ADR の明示的な決定を覆している。**  
   根拠: [ADR-0121:39](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/adr/0121-agent-management-console.md:39)、[task-36.md:98](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:98)。  
   ADR は「3 グループを縦に並べる」「切替器にはしない」「説明を行に併記する」と明記。契約は Picker で絞り、説明を help に移します。これは改善案の具体化だけでなく、従来の「見比べる用途」を変更する判断です。  
   **修正案:** 方針転換の理由と承認を記録し、ADR の該当決定を更新・置換する。実装者の allowed_paths に無理に加えず、PM の文書作業として扱えます。

9. **[HIGH] UI-06 の完了条件が同じ契約内で相反している。**  
   根拠: [task-35.md:111](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-35.md:111)、[同:115](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-35.md:115)、[同:125](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-35.md:125)。  
   本文と Rubric は入力欄比較未達での完了を禁止しますが、PM 追記は比較を保留したまま完了マークへ注記する運用に読めます。合否がレビュアー次第になります。  
   **修正案:** 判断までは「実装・自動検査済み／実画面比較未完了」に統一する。比較を免除するなら、ユーザー判断を受けて成功基準と Rubric の双方を改訂する。

10. **[MED] task-36 は独立して失敗する 3 契約を束ねている。**  
    根拠: [task-36.md:35](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:35)、[同:42](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:42)、[同:78](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:78)。  
    enum の公開失敗、Picker の遷移失敗、状態文言や開閉の失敗は別々に発生します。  
    **分割案:**

    | 契約 | 受け入れ条件 | 依存 |
    |---|---|---|
    | enum 移設 | 19 項目・属性・順序保持、公開参照、App ビルド | なし |
    | ナビゲーション | 選択の正規化、Picker、現在地、19 ペイン接続 | enum 移設 |
    | 状態要約・CLI 詳細 | 4 組の文言、先頭表示、開閉、既存情報保持 | なし |

    状態要約モデルを別ファイルにし、それぞれの allowed_paths・凍結テスト・配線検査を分ける。task-35 は「候補テーマの見本」という 1 契約として成立しています。

11. **[MED] App ビルドを要求する契約に対し、指定された自動ゲートには App ビルドがない。**  
    根拠: [task-35.md:94](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-35.md:94)、[task-36.md:148](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-36.md:148)、[verify.sh:5](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/verify.sh:5)、[ui-ux-verify-task.sh:42](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/ui-ux-verify-task.sh:42)。  
    確認したゲートはパッケージテスト・Ruby・差分検査です。公開範囲、App 側 extension、SwiftUI の型エラーは残り得ます。  
    **修正案:** PM の隔離 Debug ビルドを、具体的なコマンド・対象 SHA・成功ログを持つ独立した必須ゲートとして明示する。

## 掃いた観点

| # | 見解 |
|---|---|
| 1. 1 タスク 1 契約 | task-35 は成立。task-36 は移設・ナビゲーション・状態要約に分割可能（指摘 10）。 |
| 2. 入力空間 | 10 テーマの主要配色、暗色 6／明色 4、CLI 未検出×設定なしを含む Bool 4 組は被覆。ナビゲーションの組合せと一部文言は不足（指摘 5）。custom は `AgentConsoleAgent` の入力外で、契約も明示的に除外しているため、第 4 の管理対象テストは不要。 |
| 3. 反証可能性・著者判断 | Phlox の RGB・不透明度・色帯、19 項目、状態文言は具体値で固定されており、全体が自己比較ではない。ただし指摘 3〜5 の欠陥実装を通す余地がある。明色 ID 集合、GitHub Light の候補値との比較、Phlox マーカー固定、Layer を組み立てず読む判断は妥当。構文・背景出現回数による代替は不十分。 |
| 4. allowed_paths・参照可能性 | 現契約の製品実装には概ね十分。`RGB.relativeLuminance` と `sidebarSelectedOpacity` は同じ DesignSystem 内なので public 化不要。App が読むモデル・enum・メンバーと `Identifiable.id` は公開が必要。Layer の public init は不要。依存は **App → AgentConfigKit**。`tint: Color` を App の extension に残す方針は正しい。 |
| 5. 配線検査 | 偽陰性・偽陽性の双方あり（指摘 1、3、4、6、7）。文字列の存在を描画・操作の保証に読み替えてはいけない。 |
| 6. ADR | ADR-0121 と直接衝突（指摘 8）。ADR-0042 のグレー化・コーラル・輝度判定、ADR-0019 の不透明下地とは整合。ADR-0042:39 の「再起動反映」は、現在の `ThemeStore.active` と `reapplyTheme()` の即時反映コードに対して古い記述であり、今回新たに生じる矛盾ではない。 |
| 7. ユーザー固有の判断 | 従来の比較用途から対象集中へ変える判断、入力欄の実画面比較を完了条件に残すかの判断。public 化や Ruby 修理は技術的に決められ、ユーザーへ委ねる必要はない。 |

規範の 8 次元も確認しました。契約適合・正しさ・構造・テスト品質は上記指摘あり。根本原因は合否条件と検査の不一致です。誠実性ではコンパイル RED の原因限定に証拠不足があります。到達性・アクセシビリティは契約上確認しましたが、実装後の画面・AX は未検証です。今回の読取範囲で新たな性能問題は指摘しません。

## ユーザーへの問い

- UX-12 は、ADR-0121 の「3 対象を見比べる」方針を撤回し、選んだ対象への集中を優先する変更として確定してよいですか。
- UI-06 は、入力欄の実画面比較ができるまで未完了としますか。それとも、その比較を今回の完了条件から外すことを承認しますか。