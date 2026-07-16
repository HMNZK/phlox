---
status: superseded
last-verified: 2026-07-07
---

> **SUPERSEDED（2026-07-07）**: この CLI は Phlox から削除された（ADR 0041）。本仕様は歴史的記録として残す。

# Goose 統合 実装仕様 (ロードマップ#2 / Tier B)

- 対象: `AgentKind` に `goose` を追加し、Claude/Codex/Cursor/Gemini/opencode と同列に Goose(Block/AAIF) を起動・制御できるようにする。
- 担当: 実装は Cursor（ヘッドレス）、検証・統合は ClaudeCode(PM)。
- 完了検知方式: **Tier B = idle-fallback のみ**（Goose は Phlox 互換 hooks 非対応）。`statusBootstrap = .idleOnSpawnComplete`、hookIntegration `.none`。
- 検証範囲: この環境に goose は**未インストール**。**build + swift test のみで検証**し、runtime は全CLI完了時にユーザーが実機検証。binary名/フラグは公式 doc/一般知識準拠（未インストールのため確度は中、要・実機確認）。

## Goose CLI の事実（doc/一般知識ベース・未検証）
- binary: `goose`。対話セッションは `goose session`（サブコマンド）で起動。
- 自律実行（bypass）: 環境変数 **`GOOSE_MODE=auto`**（値: auto/approve/chat/smart_approve。auto は承認なしで全ツール/シェルを実行）。フラグではなく env で制御。
- セッション: `--name <名前>` で命名、`-r`/`--resume` で再開。Phlox は session 名に Phlox セッション UUID を使い 1:1 対応させる。
- hooks: Phlox 互換の hook 連携は無い → 完了検知は idle-fallback。

---

## 実装タスク（opencode と同型。差分は「base 引数 `session`」「bypass は env」「resume は名前付き」）

### 1. `Packages/AgentDomain/Sources/AgentDomain/AgentKind.swift`
- `case goose` を `opencode` の後に追加。
- `displayName`: "Goose" / `binaryName`: "goose" / `symbolName`: "bird.fill"。

### 2. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/AgentLaunchPlanner.swift`
- `profile()` に追加:
  ```swift
  case .goose:
      return AgentLaunchProfile(
          extraArgs: ["session"],
          // GOOSE_MODE=auto: 承認なしで全ツール/シェルを自律実行（フラグではなく env で制御）。
          extraEnv: bypassEnabled ? ["GOOSE_MODE": "auto"] : [:],
          hookIntegration: .none,
          scrollbackPolicy: .keep,
          statusBootstrap: .idleOnSpawnComplete
      )
  ```
- `applyLaunchMode` に追加（base 引数 `session` の後に名前付け/再開を付与）:
  ```swift
  case (.goose, .newSession(let resumeID)):
      guard let resumeID else { return baseArgs }
      return baseArgs + ["--name", resumeID]
  case (.goose, .resume(let resumeID)):
      return baseArgs + ["-r", "--name", resumeID]
  ```

### 3. `Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift`
- `gooseKey = "phlox.bypass.goose"` 追加、`defaultsDictionary` に `gooseKey: true`、`key(for:)` に `case .goose: gooseKey`。

### 4. `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`
- `initialResumeID(for:sessionID:)` に `case .goose: return sessionID.rawValue.uuidString.lowercased()`（Phlox セッション UUID を Goose の session 名に使う）。

### 5. `Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift`
- `public let agentGoose: RGB` を追加。
- ANSI 由来 `from(...)` 初期化に `agentGoose: ansi[5]` を追加。
- 静的デフォルトに `agentGoose: RGB(0xE5, 0x7C, 0x23)`（オレンジ）を追加。
- ※ コンパイラが全初期化箇所を検出するので漏れなく埋める。

### 6. `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`
- `agentColor(for:)` の switch に `case .goose: theme.agentGoose.color`。既存ケースに触れない。

### 7. `Packages/DashboardFeature/Sources/DashboardFeature/Usage/UsageMonitor.swift`
- 2 つの init の providers 辞書に `.goose: EmptyUsageProvider(kind: .goose)` を追加。

### 8. `App/CompositionRoot.swift`
- バイナリ解決ループに `.goose` を追加（`[.codex, .cursor, .gemini, .opencode, .goose]`）。

### 9. `App/SettingsView.swift`
- opencode/gemini に倣い goose の bypass トグルを追加。

### 10. テスト
- `AgentLaunchPlannerTests.swift` の kind に対する exhaustive switch / パラメタライズド arguments に `.goose` を追加。
- goose の launch-plan テストを1つ追加: command が goose、`extraArgs` 先頭が `session`、bypass 有効時に env `GOOSE_MODE=auto` を含む、`statusBootstrap == .idleOnSpawnComplete`、newSession 時に `--name <uuid>` が付く、を検証。
- `AgentKindTests.swift` が exhaustive なら `.goose` 追加。
- `App/PhloxApp.swift` のメニューが allCases 列挙なら自動露出。switch なら追加。

---

## 厳守事項
- サージカル編集のみ。既存スタイル・日本語コメントに合わせる。
- ベースは最新 `feature/ai-cli-integration`（Gemini/opencode 統合済み）。AppTheme/Tokens/BypassSettings/UsageMonitor/SettingsView には既に gemini/opencode ケースがある前提で goose を追加。
- 実装後に自己検証: `xcodebuild ... build` と `cd Packages/DashboardFeature && swift test` / `cd Packages/AgentDomain && swift test`。結果を正直に報告。テストの削除・skip・期待値改ざん禁止。
- **コミットしない**（PM が検証後に行う）。

## 検証
1. PM: `xcodebuild` 成功 + `swift test` 全 pass を実走確認 + goose launch-plan テスト確認。
2. ユーザー（全CLI完了時・要 goose インストール）: Phlox から goose を spawn → 送受信 → idle 完了検知の通し確認。GOOSE_MODE=auto の自律実行も確認。
