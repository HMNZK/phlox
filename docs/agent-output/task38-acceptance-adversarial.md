## 判定

**needs_changes**

凍結表とモデルテストは妥当ですが、配線検査に契約違反を見逃す穴があります。ファイルは変更していません。以下は静的レビューの結果です。

両 Ruby 検査の実行は、指定ラッパーが `mktemp: Operation not permitted` で停止しました（exit 1）。`--selftest` 本体・Swift テスト・App ビルド・GUI は未検証です。

## 指摘

1. **HIGH — 実際の描画につながらないコードでも配線済みと判定される。**  
   `good_settings_src` の `groupForm(group)` を `Text("空")` に変えても、未使用になったヘルパー内の分岐を検査が拾います。タブのタイトル・シンボル・列挙順も実描画との照合がなく、`SettingsGroup.all.reversed()` を拒否できません。AX も文字列の存在検査なので、`accessibilityIdentifier(...)` を `help(...)` に変える偽装を拒否できません。`body` から実際に使われる描画経路と、タブ属性の接続を検査する必要があります。  
   根拠：[task38-wiring.rb:549](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:549)、[同:623](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:623)、[同:473](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:473)。

2. **HIGH — 保存先の対応関係と独自 View の保護が欠ける。**  
   `@AppStorage` はキー・変数・既定値を別々に検索しています。`bannerNotificationEnabled` と `completionSoundEnabled` の保存キーを交換しても、両方の既定値が `true` なので検出できません。また、契約で内部全体を固定した `AppIconRowView` が比較対象から漏れており、選択 action の無効化を見逃します。宣言単位の比較と対象追加が必要です。  
   根拠：[task38-wiring.rb:670](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:670)、[同:455](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:455)、[task-38.md:192](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-38.md:192)。

3. **HIGH — 「開いただけでは値を変えない」を検査できていない。**  
   `.onAppear { bannerNotificationEnabled = false }` を追加しても、検査対象の `UserDefaults`・`.set(`・タブ名入り `onChange` に該当しません。描画ヘルパーからの書き込みも追跡していません。モデルも禁止語の検索だけなので、`all` を `print("生成")` を含む初期化クロージャにしても拒否できません。契約が要求する代入・初期化・ヘルパーの検査が必要です。  
   根拠：[task38-wiring.rb:728](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:728)、[同:510](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:510)、[task-38.md:293](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-38.md:293)。

4. **MEDIUM — task35 の更新は「移動のみ許容」より保護範囲を狭める。**  
   Section 本文と footer だけの比較になり、保存宣言・Binding 実装・Section 外の条件や子 View が保護対象から外れます。また、両検査とも同名 Section を後勝ちで上書きするため、改変した Section の後方に元の同名 Section を未使用コードとして残す偽装が可能です。task38 の `.uniq` も描画の重複を隠します。再配置に無関係なコードの保護と、重複の拒否が必要です。  
   テーマ見本・製品配色の検査本体は維持されています。`094f86a` から確認時 HEAD `5428edd` までの SettingsView 差分はテーマ関連の3構造体なので、同じ SHA で Section 比較が一致する理由自体は正当です。  
   根拠：[task35-wiring.rb:217](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:217)、[同:696](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:696)、[task38-wiring.rb:630](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:630)。

5. **MEDIUM — TASK38_BASELINE が凍結コミットに固定されていない。**  
   未設定・不正 SHA・現在の HEAD の拒否はありますが、指定 SHA が承認済みの凍結コミットか、実装を含まないかは確認していません。実装コミット A の後に別コミット B を置けば、A を基準にできます。一方、凍結時 HEAD の上で未コミット実装を検査する通常の場面は、正しい基準でも拒否されます。HEAD との一致ではなく、凍結基準の同一性と内容を検証する必要があります。  
   根拠：[task38-wiring.rb:484](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:484)、[同:1063](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:1063)、[task-38.md:33](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-38.md:33)。

6. **MEDIUM — selftest の負例が主張した失敗理由を証明していない。**  
   重複分岐の `dup` は作成後に検査されません。「順序違い」は並べ替えではなく ID の欠落、「未使用コード偽装」はコントロールも欠落した例です。`if false` 検査も、内部の Section が `by_title` に登録されるため拒否条件が成立しません。task35 は selftest と本番で別の比較関数を使っています。正しい fixture から違反を一つだけ加え、本番の検査経路で落ちる負例が必要です。  
   根拠：[task38-wiring.rb:970](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:970)、[同:1002](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:1002)、[同:640](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task38-wiring.rb:640)、[task35-wiring.rb:422](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task35-wiring.rb:422)。

7. **MEDIUM — PM ゲートの起動条件だけでは端末ストアを隔離できない。**  
   指定されたデータディレクトリ・agents JSON・defaults suite では、通常 Debug の Keychain は隔離されません。起動時には旧項目削除・期限切れ掃除が実行されます。既存ヘルパーと同じ `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を起動条件に明記してください。実際のデータ削除は観測していません。  
   根拠：[task-38.md:347](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-38.md:347)、[CompositionRoot.swift:357](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/App/CompositionRoot.swift:357)、[MobileDeviceProvisioner.swift:81](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Sources/AgentDomain/MobileDeviceProvisioner.swift:81)、[IsolatedPhloxApplication.swift:88](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/UITests/IsolatedPhloxApplication.swift:88)。

## 掃いた項目

1. **問題なし** — 14 Section、コントロール・表示行、8 footer は実コードと一致し、モバイルの表示条件も記載されています。
2. **問題なし（静的確認）** — 期待値はリテラル。件数・和集合・重複・順序・title/systemImage を反証でき、第二引数も `Comment(rawValue:)` です。
3. **指摘あり** — 描画接続・AX・保存対応・I/O・基準 SHA・selftest に指摘1〜3、5〜6の穴があります。
4. **指摘あり** — 見本検査は維持されていますが、Section 外と重複の保護が弱まっています（指摘4）。
5. **問題なし** — 指定2製品ファイルで実装可能。既存 Settings シーンへの変更は必要ありません。
6. **問題なし（新規矛盾なし）** — 520×640 は実コード由来。task-17 の後続再ベースと既存 ADR の名称不整合は契約で扱われています。
7. **指摘あり** — 保存ドメインの前後比較は現実的ですが、Ruby の書き込み検査と起動時隔離が不足しています（指摘3、7）。
8. **問題なし** — モデル・TabView・Section 移設は「既存設定を分類どおり描画する」という同じ契約を構成します。
9. **問題なし** — グループ名・所属・順序は末尾の PM 決定で採用済みです。

## ユーザーへの問い

ありません。指摘は PM 側の検査・契約修正で扱えます。