---
task: task-44
status: completed
---

# tests-task-44

UX-01b セッションタイトルの状態・永続化・ライフサイクル受け入れ検査。製品コード・契約・台帳は未変更。コミットしていない。

## 作成物

- `macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleStateTests.swift`
- `macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDescriptorTests.swift`
- `tasks/frozen/staged/AcceptanceSessionTitleLifecycleTests.swift`（実パス: `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift`）
- `tasks/frozen/staged/AcceptanceSessionTitlePersistenceTests.swift`（実パス: `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift`）
- `.claude/scripts/task44-wiring.rb`

SessionFeature / DashboardFeature / DesignSystem の実テストパス、`SessionFeature/Sources`、`.claude/scripts/task40-wiring.rb`、`AcceptanceHistoryTitleSourcesTests.swift`、`Harness/` には触っていない。

## 期待値の出所

すべて `tasks/task-44.md` の独立リテラル。被検査関数や `SessionTitleDeriver.derive` の戻り値から生成していない。task-41 の `SessionTitleDeriver.swift` は前提として読んだが、導出規則は複製していない。

- 公開 API・正規化順序・リテラル表・状態遷移: 契約「公開名前状態 API」
- descriptor 四フィールド・legacy / 未知 source / updating / token 非 encode: 契約「descriptor の後方互換」と成功基準 1
- チャット候補採用・PTY 非導出・PID 書き戻し順序: 契約「チャット本文の候補採用」「保存・復元・rename」「PTY 方針」と成功基準 2
- 固定本文: `ログイン画面を修正` / `ログイン画面を修正\n詳細` / `/review` / `通知を修正` / `Rose` / fallback `abc123`
- 配線: 契約「3. Ruby 検査の分離と凍結」（`TASK44_BASELINE` 必須、HEAD/ブランチ名拒否、祖先確認、基準に task-41 あり・`SessionTitleState.swift` なし、凍結テスト 4 本と rb の blob 同一性、SHA==HEAD でも実装前 blob なら拒否しない、恒久検査と `TASK44_SCOPE_CHECK=1` の分離）

## AgentDomain RED 原文

コマンド: `(cd macos/Packages/AgentDomain && swift build --build-tests)`
終了コード: 1

error 種別（原文の `error:` 以降を集計）:

```
 118 'nil' requires a contextual type
  66 cannot infer contextual base in reference to member 'manual'
  50 cannot find 'SessionTitleState' in scope
  40 cannot infer contextual base in reference to member 'derived'
  38 cannot infer contextual base in reference to member 'flower'
  20 cannot find type 'SessionTitleSource' in scope
  16 cannot find type 'SessionTitleState' in scope
   6 cannot find 'SessionTitleSource' in scope
   2 value of type 'PersistedSessionDescriptor' has no member 'titleState'
   2 extra arguments at positions #18, #19, #20 in call
   2 extra arguments at positions #10, #11, #12 in call
   2 cannot infer contextual base in reference to member 'appServer'
   1 emit-module command failed with exit code 1 (use -v to see invocation)
```

未定義の `SessionTitleState` / `SessionTitleSource` と、現行 `PersistedSessionDescriptor` に無い `titleSource` / `flowerName` / `fullDerivedTitle` / `titleState` が一次原因。`.flower` / `.derived` / `.manual` / `nil` の型推論失敗と `.appServer` の推論失敗は、その後続である。構文エラーや無関係シンボル欠落は無い。

原文抜粋:

```
Building for debugging...
[0/4] Write sources
[1/4] Write swift-version--58304C5D6DBC2206.txt
[3/7] Compiling AgentDomainTests AcceptanceSessionTitleStateTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleStateTests.swift:17:18: error: cannot find type 'SessionTitleState' in scope
 15 | struct AcceptanceSessionTitleStateTests {
 16 |     private func expectState(
 17 |         _ state: SessionTitleState,
    |                  `- error: cannot find type 'SessionTitleState' in scope

.../AcceptanceSessionTitleDescriptorTests.swift:50:32: error: value of type 'PersistedSessionDescriptor' has no member 'titleState'
 50 |         expectState(descriptor.titleState, name, source, flowerName, fullDerivedTitle, label)
    |                                `- error: value of type 'PersistedSessionDescriptor' has no member 'titleState'

.../AcceptanceSessionTitleDescriptorTests.swift:65:35: error: extra arguments at positions #18, #19, #20 in call
 65 |         PersistedSessionDescriptor(
    |                                   `- error: extra arguments at positions #18, #19, #20 in call
.../PersistedSessionDescriptor.swift:80:12: note: 'init(id:kind:workingDirectory:name:projectID:startedAt:command:args:env:backend:codexThreadId:chatNativeSessionId:appServerUserAgent:codexSettings:token:resumeID:parentSessionID:pid:launchContext:role:)' declared here
```

## 退避テスト parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceSessionTitleLifecycleTests.swift
lifecycle_parse_exit:0

$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceSessionTitlePersistenceTests.swift
persistence_parse_exit:0
```

標準出力・標準エラーは空。

## selftest 原文

```
$ ruby .claude/scripts/task44-wiring.rb --selftest
task44-wiring --selftest: OK
```

終了コード: 0。メモリ fixture。正例は空 NG。負例は違反 1 件ごとの期待エラー配列を `==` で比較。

## 契約の曖昧点（テストが採った解釈）

1. 新規 VM の花名は init の `titleState:`（既定 `.generated(flowerName: "Rose")`）で渡す。公開 `name` 代入は `renamed(to:)` による手動化であり、花名初期化には使わない。
2. PID 書き戻しの「導出名へ変更」はチャット経路のみ。PTY は自動導出しないため、PTY の rename なし期待は `("Rose", .flower, "Rose", nil)`。チャットの rename なし期待は `("ログイン画面を修正", .derived, "Rose", "ログイン画面を修正")`。
3. 識別不能なサーバー履歴は `ChatItem.userMessage` の本文が `/review\nログイン画面を修正` の補足付き文字列。独立識別可能は本文そのものが適格行（`ログイン画面を修正` / `通知を修正`）。文字列類似性では対応付けない。
4. 未知 `titleSource` は decode 成功＋手動退避＋正規化花名保持＋導出全文解除。診断ログの文言自体はアサートしない。
5. `DashboardViewModel.renameSession` は契約の `renamed(to:)`（`.whitespacesAndNewlines`）を期待する。`" 通知を修正 \n"` → `"通知を修正"`。保存完了待ちは既存窓口 `waitForPendingPersistenceWritesForTesting()`（内部 `waitForPendingWrites()`）。
6. 退避 2 本の関数名から空白を除いた。`swiftc -parse` が `flowerName` 等を別識別子と見なすため。`@Test` 説明文の契約リテラルは維持。

=== REPORT COMPLETE ===
