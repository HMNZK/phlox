---
task: tests-task-33-34-r2
status: completed
---

## 変更点（ファイル別）

### 1. `AcceptanceNewSessionMenuModelTests.swift`
- primary 入力を重複なしの `[cursorOnly, claude, codex]` に変更（`allDescriptors` 連結を廃止）。`AgentRegistry.descriptor(for:)` で組込を取る。
- `[codex, claude]` で primary が Codex（title「新しいチャット（Codex）」、ref `.builtin(.codex)`、チャット節 id `["chat:codex","chat:claudeCode"]`）を追加。
- 成功基準1の「Claude 不在」として `[cursorOnly, codex]` → primary Codex・チャット節 `["chat:codex"]` を追加。
- custom `AgentDescriptor(ref: .custom("ui01-probe"), …, launchSpec: 既存 claude の launchSpec コピー, supportsStructuredChat: false)` のみ → primary nil、items id `["terminal:ui01-probe"]`、ref `.custom("ui01-probe")`、backend `.pty`。
- 混在 `[claude, custom]` のターミナル節 id が `["terminal:claudeCode","terminal:ui01-probe"]`。
- destinationText に `"\t UI検証A \n"` → `"作成先: UI検証A"`。
- `terminalOnlyCopy` は `kind:` ではなく `ref:` をコピー（custom で `kind` を触ると preconditionFailure）。

### 2. `AcceptanceHitTargetTests.swift`
- 不等式4本は残置。
- 等値を追加: `icon == 24`、`modeSegmentWidth == 30`、`modeSegmentHeight == 24`、`DSSpacing.xxs == 2`、`DSIconSize.l == 15`。
- 指紋側にも `DSIconSize.l == 15` を追加。

### 3. `.claude/scripts/task33-wiring.rb`
- `TASK33_BASELINE` 未設定（空含む）は NG で exit 1。HEAD へフォールバックしない。
- 対象本文は `//` 以降を除去してから検査。
- `NewSessionMenuModel.make(` の括弧対応引数に `projectName:`・`\bprojectID\b`・`\bprojects\b`・空白除去後 `descriptors:viewModel.availableAgentDescriptors`。
- `Text(model.destinationText)` 必須。各 Button の `label: {…}` および `Button(action:){…}` のラベル本文に含まれたら NG。
- `if let \w+ = model.primary`。
- `Section(section.title)` または `header:{Text(section.title)}`。
- `ForEach(model.sections` と `ForEach(section.items`。
- `createSession(` 引数（空白除去）が `ref:primary.ref,projectID:projectID,backend:primary.backend` と `ref:item.ref,projectID:projectID,backend:item.backend` を含む。
- `Label(primary.title,systemImage:primary.systemImage)` と `Label(item.title,systemImage:item.systemImage)`。
- 出現順 `Text(model.destinationText)` < `model.primary` < `ForEach(model.sections`。
- 旧ヘルパー不在。`AgentStartCardsModel.modes(for:` が `newSessionMenuItems` 本文に無い。
- `NewSessionMenuModel.swift` が存在し `AgentStartCardsModel.modes(for:` と `.backend` を含み、`.appServer` / `.pty` リテラルが無い。
- 不変ファイルは `AgentStartCards.swift` と `TeamTimelineView.swift` のみ（`DashboardSidebarView.swift` は対象外）。

### 4. `.claude/scripts/task34-wiring.rb`
- `TASK34_BASELINE` 未設定は NG で exit 1。HEAD へフォールバックしない。
- コメント除去＋空白除去後に検査。
- `ModeSegmentButton` 本文: `.frame(width:DSHitTarget.modeSegmentWidth,height:DSHitTarget.modeSegmentHeight)` がちょうど 1 回、`width:26,height:20` 無し、`size:13`、`.contentShape(Rectangle())`、`.help(help)`、`.accessibilityAddTraits`、`.pointingHandCursor()`、`.accessibilityIdentifier(identifier)`。
- `ViewModeToggle` 本文に `.padding(DSSpacing.xxs)`。
- Sidebar に `.frame(width:DSHitTarget.icon,height:DSHitTarget.icon)` 3 回以上、`width:22,height:22` / `width:20,height:20` 無し。
- `"xmark"` から直後の `.help(` までの部分文字列に icon frame と `.contentShape(Rectangle())`、`width:20,height:20` 無し（`Button(action:){}` と `Button{}label:{}` の両方で同じ範囲が取れる）。
- 3 ファイルの `focusable(`・`focusEffectDisabled(`・`accessibilityHidden(true)`・`.contentShape(Rectangle())`・`.help(` 出現数が `git show $TASK34_BASELINE:<path>` と同じ（コメント除去＋空白除去後。`true`→`false` は個数が変わる）。
- `.frame(height:32)` は現行位置である `DashboardTrailingTopBarControls.body`（`trailingControls` を含む HStack に付いている）に残ることを検査。`trailingControls` プロパティ本体には無い。

## 反例への判定（机上）

指摘 4・5・6 の反例を、改訂後スクリプトと同じ `strip` / `compact` / 部分文字列規則で確認した。

### 指摘4 `projectID: nil`
`createSession(ref: primary.ref, projectID: nil, backend: primary.backend)` の空白除去結果は `ref:primary.ref,projectID:nil,backend:primary.backend`。要求文字列 `ref:primary.ref,projectID:projectID,backend:primary.backend` を含まない → **NG**。

`NewSessionMenuModel.make(projectName: nil, descriptors: viewModel.availableAgentDescriptors)` は `\bprojectID\b` も `\bprojects\b` も無い → **NG**（作成先を固定 nil / 選択中プロジェクト名にすり替える穴）。

### 指摘5 未使用プロパティに DSHitTarget を書くだけ
`ModeSegmentButton` 内に

```swift
private let sizes = (
    DSHitTarget.modeSegmentWidth,
    DSHitTarget.modeSegmentHeight
)
.frame(width: 26, height: 20)
```

を置いても、要求 frame の出現は 0 回、かつ `width:26,height:20` が残る → **NG**。トークン名の存在だけでは通らない。

### 指摘6 `Section {} header: {}`
空白除去後に `header:{Text(section.title)}` が含まれる → **OK**（`Section(section.title)` が無くても許容）。

### 指摘6 `Button {} label: {}` 形の xmark
`"xmark"` から直後の `.help(` までの範囲に `.frame(width:DSHitTarget.icon,height:DSHitTarget.icon)` と `.contentShape(Rectangle())` が含まれ、`width:20,height:20` が無ければ → **OK**。旧 20×20 のままだと range に `width:20,height:20` が残る → **NG**。`Button(action:) { Image("xmark")… }` でも同じ範囲規則。

## 現状コードに対する rb 実行結果（原文）

`ruby -c` 両方 Syntax OK。

```text
===== TASK33_BASELINE=HEAD =====
task33-wiring: NG newSessionMenuItems 本文に NewSessionMenuModel.make( が無い
task33-wiring: NG newSessionMenuItems 本文に Text(model.destinationText) が無い
task33-wiring: NG newSessionMenuItems 本文に if let <name> = model.primary が無い
task33-wiring: NG newSessionMenuItems 本文に Section(section.title) も header:{Text(section.title)} も無い
task33-wiring: NG ForEach( に model.sections が無い
task33-wiring: NG ForEach( に section.items が無い
task33-wiring: NG createSession( に ref:primary.ref,projectID:projectID,backend:primary.backend が無い
task33-wiring: NG createSession( に ref:item.ref,projectID:projectID,backend:item.backend が無い
task33-wiring: NG Label(primary.title, systemImage: primary.systemImage) が無い
task33-wiring: NG Label(item.title, systemImage: item.systemImage) が無い
task33-wiring: NG 出現順検査に必要な Text(model.destinationText) / model.primary / ForEach(model.sections が見つからない
task33-wiring: NG AgentStartCardsModel.modes(for: が newSessionMenuItems 本文に残っている
task33-wiring: NG newSessionMenuTitle が残っている
task33-wiring: NG newSessionMenuSymbol が残っている
task33-wiring: NG macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/NewSessionMenuModel.swift が存在しない
task33-exit:1
===== TASK34_BASELINE=HEAD =====
task34-wiring: NG ModeSegmentButton 本文に .frame(width:DSHitTarget.modeSegmentWidth,height:DSHitTarget.modeSegmentHeight) が 0 回（期待 1）
task34-wiring: NG ModeSegmentButton 本文に width:26,height:20 が残っている
task34-wiring: NG DashboardSidebarView.swift の .frame(width:DSHitTarget.icon,height:DSHitTarget.icon) が 0 箇所（期待 3 以上）
task34-wiring: NG DashboardSidebarView.swift に width:22,height:22 が残っている
task34-wiring: NG DashboardSidebarView.swift に width:20,height:20 が残っている
task34-wiring: NG PaneLayoutView.swift の xmark〜.help( に .frame(width:DSHitTarget.icon,height:DSHitTarget.icon) が無い
task34-wiring: NG PaneLayoutView.swift の xmark〜.help( に width:20,height:20 が残っている
task34-exit:1
```

`TASK33_BASELINE` / `TASK34_BASELINE` 未設定でも先頭に「未設定（HEAD にフォールバックしない）」を出して exit 1。HEAD 指定時は git 自己比較を使わず、上記の配線欠落で落ちる。

## 契約の疑問点（PM 宛）

1. `if let \w+ = model.primary` は束縛名を自由にしているが、`createSession` / `Label` は `primary.` 固定。`if let primaryItem = model.primary` は if-let だけ通り、起動引数検査で NG になる。束縛名まで `primary` に固定するか、検査を束縛名連動にするかを明示した方がよい。
2. `.frame(height: 32)` の現行位置は `trailingControls` プロパティではなく `DashboardTrailingTopBarControls.body`。成功基準2の「trailingControls を含む本文」に合わせ、検査は `body` にした。契約文面を `body` に直した方が実装者の迷いが減る。
3. `make(` 引数そのものに `projects` / `projectID` を要求するため、`let name = viewModel.projects.first { $0.id == projectID }?.name` に切り出す正しい実装は NG になる。インライン必須なら契約にそう書くべき。
4. modifier 出現数の一致は「個数」だけで、適用先の移動は検出しない（指摘5の残り）。契約も個数比較のままなので、意図どおりならその限界を残す。
5. 指摘8（端クリック・キーボード到達）は本4ファイルでは担保できない。PM ゲート側の話。
6. custom の `launchSpec` は敵対レビュー例が `AgentLaunchSpec()`、今回の改訂指示は既存 descriptor のコピー。後者でテストを書いた（`kind` に触れない制約を守るため）。

=== REPORT COMPLETE ===
