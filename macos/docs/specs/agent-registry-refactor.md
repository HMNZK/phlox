---
status: completed
last-verified: 2026-07-08
---

> **歴史的ロードマップ（実施済み）**: 本書は CLI が7種（claudeCode/codex/cursor/gemini/opencode/goose/amazonQ）だった時点でのレジストリ化設計ゴール。現行の組込 CLI は ADR 0041 により **claudeCode/codex/cursor の3種に限定**されている（`AgentDescriptor`/`AgentRegistry` によるレジストリ駆動化自体は本書の設計どおり実施済み）。本文の「7エントリ/7 CLI」等の記述は当時の実態としてそのまま残す。

# 設定駆動レジストリ化 refactor 設計ゴール (ロードマップ#3)

- 目的: CLI 追加コストの根本解消。現状「1 CLI 追加 = enum + 約12ファイルの switch 分岐」を、**「enum case + レジストリ1エントリ」**で済む構造に変える。
- 担当: 設計・実装は Codex(シニア)にヘッドレス委譲。検証・コミットは ClaudeCode(PM)。
- スコープ: #3 はレジストリ集約まで。ユーザー定義 JSON(#4) は別タスク。
- ブランチ: `feature/ai-cli-integration`。**main へはマージしない**(コミットまで)。

## 現状の per-kind 分散箇所(集約対象)
- `AgentKind.swift`: displayName / binaryName / symbolName
- `AgentLaunchPlanner.swift`: `profile(for:)`(起動引数・bypass・hookIntegration・statusBootstrap) と `applyLaunchMode`(resume/サブコマンド)
- `AppTheme.swift` + `Tokens.swift`: per-kind 色
- `BypassSettings.swift`: per-kind bypass キー
- `DashboardViewModel.swift`: `initialResumeID`(resume id 戦略)
- `SessionHookInstaller.swift`: hook ファイル設置の kind 分岐
- `UsageMonitor.swift`: per-kind UsageProvider
- `CompositionRoot.swift`: バイナリ解決対象リスト
- `SettingsView.swift` / `PhloxApp.swift`: UI(多くは allCases 列挙で自動)

## 設計方針(Codex が詳細設計してよい。下記は指針)
1. `AgentDescriptor`(AgentDomain) を新設し、per-kind の **純データ + 宣言的起動spec** を保持:
   - 表示: displayName, binaryName, symbolName, colorRGB(DesignSystem 側の color token はこの RGB を引く)
   - 設定: bypassKey
   - 起動spec(宣言的): baseArgs(例 `["session"]`/`["chat"]`), bypassArgs(例 `["--yolo"]`), bypassEnv(例 `["GOOSE_MODE":"auto"]`), hookKind(none/claudeSettings/codexStyle/cursorStyle/geminiStyle), statusBootstrap, resumeSpec(none / flag(["--resume"]) / namedFlag(["--name"]) / claudeSessionId / codexResumeSubcommand / cursorResume)
   - resumeID 戦略(initialResumeID): none / phloxUUID / cursorCreateChat / codexNativeFromHook
2. `AgentRegistry`: `AgentKind -> AgentDescriptor` を1箇所で定義(7エントリ)。
3. 既存の散在 switch を**レジストリ参照に置換**:
   - `AgentLaunchPlanner` は descriptor の起動spec を解釈して `AgentLaunchPlan` を組み立てる(環境依存値=hookURL/settingsPath は spec の hookKind から planner が解決)。
   - `AgentKind.displayName/binaryName/symbolName`、`Tokens.agentColor`、`BypassSettings.key`、`initialResumeID`、`CompositionRoot` の解決対象、`UsageMonitor` の provider 既定、`SessionHookInstaller` の分岐 を、可能な限り registry 駆動にする。
4. `AgentKind` enum は**残す**(Codable 永続化・[AgentKind:Value] 辞書キー・セッション復元のため)。enum は識別子、データは registry。

## 不変条件(最重要・回帰ガード)
- **既存7 CLI の `AgentLaunchPlan`(command/args/env/hookIntegration/statusBootstrap)はバイト等価で不変**であること。
- `AgentLaunchPlannerTests.swift` の**既存アサーションを一切変更せず pass** させる(これが挙動保持の回帰ガード。弱体化・期待値改変は禁止)。`AgentKindTests` の displayName/binaryName も不変。
- 既存テスト(AgentDomain 39 / DashboardFeature 186)が**全て pass**。色解決(`agentColor`)も従来と同一。
- サージカル: 無関係な整形をしない。未コミット WIP は無い(クリーン)。

## 受け入れ条件
1. `xcodebuild ... build` 成功。
2. `cd Packages/AgentDomain && swift test`(39) と `cd Packages/DashboardFeature && swift test`(186以上) が全 pass。既存アサーション unchanged。
3. 「CLI 追加手順」が **enum case 追加 + registry 1エントリ + (hook方式なら HooksManager)** に縮小したことを `docs/specs/agent-registry-refactor.md` の末尾に追記(Before/After の手順比較)。
4. レジストリ駆動を示す軽いテスト(例: 全 AgentKind が registry に descriptor を持つ、registry の binaryName が enum と一致)を追加。

## 自己検証 & 報告(Codex)
- 上記 build/test を実走し、結果を正直に報告。失敗は隠さない。テスト削除・skip・期待値改変での糊塗は禁止。
- **コミットしない**(PM が検証後に commit)。変更ファイル一覧・build/test 結果・設計判断・残課題を簡潔に報告。

## CLI 追加手順 Before / After

### Before

1. `AgentKind` に enum case を追加する。
2. `AgentKind.displayName` / `binaryName` / `symbolName` の各 switch に case を追加する。
3. `AgentLaunchPlanner.profile(for:)` と `applyLaunchMode` に起動引数・bypass・resume 分岐を追加する。
4. `BypassSettings` に key 定数、defaults、`key(for:)` 分岐を追加する。
5. `Tokens.agentColor(for:)` と `AppTheme` に CLI 色の分岐・プロパティを追加する。
6. `CompositionRoot` のバイナリ解決対象、`DashboardViewModel.initialResumeID`、`SessionHookInstaller`、`UsageMonitor` に必要な分岐を追加する。
7. `SettingsView` / `PhloxApp` の UI 列挙を追加する。
8. hook 方式がある場合は専用 `HooksManager` と installer 分岐を追加する。

### After

1. `AgentKind` に enum case を追加する。
2. `AgentRegistry.allDescriptors` に `AgentDescriptor` を 1 エントリ追加し、表示名・binary・symbol・色・bypass key・usage provider・launch spec・resume strategy・hook kind を宣言する。
3. hook ファイル設置が必要な新方式の場合だけ、対応する `HooksManager` と `AgentHookKind` の解釈を追加する。
4. 既存の設定 UI、セッションメニュー、bypass defaults、任意バイナリ解決、usage default、起動 plan は registry から自動で反映される。
