---
task: tests-task-33-34
status: completed
---

## 作成したファイルとテスト名一覧

1. `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceNewSessionMenuModelTests.swift`
   - `destinationTextTrimsEmptyAndNil`
   - `primaryIsFirstChatCapableDescriptorInOrder`
   - `chatIncapableOnlyHasNoPrimaryAndNoChatSection`
   - `chatAndTerminalItemsFollowDescriptorOrder`
   - `itemIDsAreUnique`
   - `emptyDescriptorsYieldNoPrimaryAndNoSections`
   - `sectionTitleConstants`
2. `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceHitTargetTests.swift`
   - `iconIsAtLeast24`
   - `modeSegmentHeightIsAtLeast24`
   - `modeSegmentWidthIsAtLeastHeight`
   - `modeSegmentFitsIn32ptRow`
   - `iconGlyphSizesUnchanged`
3. `.claude/scripts/task33-wiring.rb`
4. `.claude/scripts/task34-wiring.rb`

`ruby -c` は両 rb とも Syntax OK。製品コードは未変更。NewSessionMenuModel / DSHitTarget 未実装のため、受け入れテストはコンパイル RED が正しい。

## 契約から読み取れず自分で決めた点

- チャット非対応 descriptor は `AgentRegistry.allDescriptors` の既存値を `AgentDescriptor(kind:displayName:binaryName:symbolName:colorRGB:bypassKey:usageProviderKind:launchSpec:supportsStructuredChat:)` でコピーし、`supportsStructuredChat: false` だけ変えた（helper `terminalOnlyCopy`）。
- builtin の `ref.id` 字面は契約に無い。`chat:` / `terminal:` の id は AgentKind の rawValue（`claudeCode` / `codex` / `cursor`）を固定した。
- task-33 の DashboardView 検査は、削除対象ヘルパー以外を `newSessionMenuItems` 本文（括弧対応で抽出）に限定した。
- `createSession(` の引数照合は空白改行除去後に `ref:primary.ref` / `backend:primary.backend` と `ref:item.ref` / `backend:item.backend` を探す。`Task { await ... }` の有無は見ない。
- task-34 の「出現数が基準コミットと同じ」対象は配線に出る3ファイル（TopBar / Sidebar / PaneLayout）。`Tokens.swift` は含めない。
- xmark Button は `"xmark"` より前で最後の `Button` の trailing closure 本文とした。`width: 20, height: 20` 無しもその本文に限定。
- ヒットターゲット凍結テストは成功基準 1 の不等式（`>=` / `<=`）を符号化し、入出力契約の `= 24/30/24` は固定していない。
- id 一意性テストは空配列で vacuous green にならないよう、`primary` と 3 エージェント分の chat/terminal id の存在も同時に固定した。

## 現状コードに対する rb 実行結果（原文）

```
task33-wiring: NG newSessionMenuItems 本文に NewSessionMenuModel.make( が無い
task33-wiring: NG newSessionMenuItems 本文に destinationText が無い
task33-wiring: NG newSessionMenuItems 本文に if let primary が無い
task33-wiring: NG newSessionMenuItems 本文に .primary が無い
task33-wiring: NG newSessionMenuItems 本文に Section( が無い
task33-wiring: NG ForEach( に model.sections が無い
task33-wiring: NG ForEach( に section.items が無い
task33-wiring: NG createSession( に ref: / backend: が primary から渡っていない
task33-wiring: NG createSession( に ref: / backend: が item から渡っていない
task33-wiring: NG AgentStartCardsModel.modes(for: が newSessionMenuItems 本文に残っている
task33-wiring: NG newSessionMenuTitle が残っている
task33-wiring: NG newSessionMenuSymbol が残っている
task34-wiring: NG ModeSegmentButton 本文に DSHitTarget.modeSegmentWidth / modeSegmentHeight の frame が無い
task34-wiring: NG DashboardSidebarView.swift の DSHitTarget.icon の frame が 0 箇所（期待 3 以上）
task34-wiring: NG DashboardSidebarView.swift に width: 22, height: 22 が残っている
task34-wiring: NG DashboardSidebarView.swift に width: 20, height: 20 が残っている
task34-wiring: NG PaneLayoutView.swift の xmark Button 内に DSHitTarget.icon が無い
task34-wiring: NG PaneLayoutView.swift の xmark Button 内に width: 20, height: 20 が残っている
```

compound_exit: 1（両スクリプトとも exit 1）

## 契約の疑問点・矛盾（PM 宛）

- SessionBackend の定義は AgentDomain。指示どおり `import SessionFeature` も入れたが、SessionFeature 側の再 export は契約に無い。
- 成功基準 1 は `DSHitTarget.icon >= 24` 等、入出力契約は `icon = 24` / `modeSegmentWidth = 30` / `modeSegmentHeight = 24`。凍結テストは成功基準 1 に合わせた。等式で縛るかは PM 判断。
- 配線文面の「`.primary` の `if let`」は契約本文の `if let primary` と表記がずれる。両方を検査している。
- `AgentRegistry.allDescriptors` は3種とも `supportsStructuredChat: true`。チャット非対応ケースは kind イニシャライザのコピーでしか作れない（custom `ref:` は指示対象外）。
- 成功基準 2 の `createSession(` は現行実装が `Task { await createSession(...) }`。引数の出所だけを見ており、同期/非同期の形は契約に無い。

=== REPORT COMPLETE ===
