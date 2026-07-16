---
status: superseded
last-verified: 2026-07-07
---

> **SUPERSEDED（2026-07-07）**: この CLI は Phlox から削除された（ADR 0041）。本仕様は歴史的記録として残す。

# opencode 統合 実装仕様 (ロードマップ#2 / Tier B)

- 対象: `AgentKind` に `opencode` を追加し、Claude/Codex/Cursor/Gemini と同列に opencode を起動・制御できるようにする。
- 担当: 実装は Cursor（ヘッドレス）、検証・統合は ClaudeCode(PM)。
- 完了検知方式: **Tier B = idle-fallback のみ**（opencode は hooks 非対応）。`statusBootstrap = .idleOnSpawnComplete`。hookIntegration は `.none`。
- 検証範囲: この環境に opencode は**未インストール**。**build + swift test のみで検証**し、runtime（実起動・完了検知）は全CLI完了時にユーザーがまとめて実機検証する。binary名/フラグは公式 doc 準拠。

## opencode CLI の事実（公式 doc 確認済み）
- binary: `opencode`。引数なしで TUI を cwd に起動。
- 自律実行（bypass）: `OPENCODE_PERMISSION={"*":"allow"}`（環境変数で全 permission を許可）。
- resume: `--continue`/`-c`（直近セッション継続）、`--session`/`-s <id>`。Phlox は per-session 作業ディレクトリを使うため、`--continue` で当該セッションを正しく継続できる。
- hooks: 非対応（完了検知は idle-fallback のみ）。

---

## 実装タスク（Gemini より単純。hooks 関連の改修は不要）

### 1. `Packages/AgentDomain/Sources/AgentDomain/AgentKind.swift`
- `case opencode` を `gemini` の後に追加。
- `displayName`: "opencode" / `binaryName`: "opencode" / `symbolName`: "terminal.fill"。

### 2. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/AgentLaunchPlanner.swift`
- `profile()` に追加:
  ```swift
  case .opencode:
      return AgentLaunchProfile(
          // OPENCODE_PERMISSION: 全 permission を許可（自律実行に必須）。
          extraEnv: bypassEnabled ? ["OPENCODE_PERMISSION": #"{"*":"allow"}"#] : [:],
          hookIntegration: .none,
          scrollbackPolicy: .keep,
          statusBootstrap: .idleOnSpawnComplete
      )
  ```
- `applyLaunchMode` に追加:
  ```swift
  case (.opencode, .newSession):
      return baseArgs
  case (.opencode, .resume):
      // per-session 作業ディレクトリ内の直近セッションを継続する（id 非依存）。
      return baseArgs + ["--continue"]
  ```
  ※ `hookIntegration` switch（plan 内）は `.none` を既存処理するため変更不要。

### 3. `Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift`
- `opencodeKey = "phlox.bypass.opencode"` 追加、`defaultsDictionary` に `opencodeKey: true`、`key(for:)` に `case .opencode: opencodeKey`。

### 4. `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`
- `initialResumeID(for:sessionID:)` に `case .opencode: return nil`（ネイティブ session id は取得しない。resume は `--continue` で代替）。

### 5. `Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift`
- `public let agentOpencode: RGB` を追加。
- ANSI 由来 `from(...)` 初期化（agentGemini 付近）に `agentOpencode: ansi[2]` を追加。
- 静的デフォルト（agentGemini 付近）に `agentOpencode: RGB(0x3F, 0xB9, 0x50)`（緑）を追加。
- ※ コンパイラが全初期化箇所を検出するので漏れなく埋める。

### 6. `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`
- `agentColor(for:)` の switch に `case .opencode: theme.agentOpencode.color` を追加。
- **重要**: このファイルには既存の `sessionRowHover`/`newSessionGradient` 変更がある（コミット済み）。`agentColor` の switch のみ編集すること。

### 7. `Packages/DashboardFeature/Sources/DashboardFeature/Usage/UsageMonitor.swift`
- 2 つの init の providers 辞書に `.opencode: EmptyUsageProvider(kind: .opencode)` を追加（使用量は当面 best-effort で「未設定」表示）。

### 8. `App/CompositionRoot.swift`
- バイナリ解決ループ `for kind in [.codex, .cursor, .gemini]` を `[.codex, .cursor, .gemini, .opencode]` に。

### 9. `App/SettingsView.swift`
- Gemini のトグルに倣い、opencode の bypass トグルを追加（`BypassSettings.opencodeKey` を `@AppStorage`、`AgentKind.opencode` の displayName/symbolName を使用）。

### 10. テスト
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/AgentLaunchPlannerTests.swift` の kind に対する exhaustive switch（ヘルパ・パラメタライズドテストの arguments 配列）へ `.opencode` を追加し、テストをコンパイル可能に。
- opencode の launch-plan テストを1つ追加: command が opencode バイナリ、bypass 有効時に `OPENCODE_PERMISSION={"*":"allow"}` を env に含み、bypass args を持たず、`statusBootstrap == .idleOnSpawnComplete` を検証。
- `Packages/AgentDomain/Tests/AgentDomainTests/AgentKindTests.swift` が kind を exhaustive に扱うなら `.opencode` を追加。
- `App/PhloxApp.swift` の New session メニューが `ForEach(AgentKind.allCases)` なら自動露出。exhaustive switch なら `.opencode` を追加。要確認。

---

## 厳守事項
- サージカル編集のみ。既存スタイル・日本語コメントに合わせる。
- ベースは最新の `feature/ai-cli-integration` ブランチ（Gemini 統合済み）。AppTheme/Tokens/BypassSettings/UsageMonitor/SettingsView には既に gemini ケースがある前提で opencode を追加する。
- 実装後に自己検証する:
  - `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxBuild build`
  - `cd Packages/DashboardFeature && swift test` / `cd Packages/AgentDomain && swift test`
  - 結果を正直に報告。失敗は隠さない。テストの削除・skip・期待値改ざんは禁止。
- **コミットしない**（PM が検証後に行う）。

## 検証
1. PM: `xcodebuild` 成功 + `swift test` 全 pass を実走確認 + opencode launch-plan テスト確認。
2. ユーザー（全CLI完了時にまとめて・要 opencode インストール）: Phlox から opencode を spawn → 送受信 → idle 完了検知の通し確認。
