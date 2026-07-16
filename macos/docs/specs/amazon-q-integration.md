---
status: superseded
last-verified: 2026-07-04
---

# Amazon Q Developer CLI 統合 実装仕様 (ロードマップ#2 / Tier B)

> **撤去済み（2026-06-11）**: Amazon Q はベンダー撤退（2025-11 に Kiro CLI へ改称、公式 Homebrew cask は `kiro-cli` に置換、新規 Builder ID サインアップ停止・end-of-support 告知）により、Phlox の対応 CLI から `amazonQ` を削除した。本書は導入の経緯・判断の記録として残す。

- 対象: `AgentKind` に `amazonQ` を追加し、Claude/Codex/Cursor/Gemini/opencode/Goose と同列に Amazon Q Developer CLI を起動・制御できるようにする。
- 担当: 実装は Cursor（ヘッドレス）、検証・統合は ClaudeCode(PM)。
- 完了検知方式: **Tier B = idle-fallback のみ**（Phlox 互換 hooks 非対応）。`statusBootstrap = .idleOnSpawnComplete`、hookIntegration `.none`。
- 検証範囲: この環境に `q` は**未インストール**。**build + swift test のみで検証**。runtime は全CLI完了時にユーザーが実機検証（要 AWS Builder ID / IAM 認証）。binary名/フラグは公式 doc/一般知識準拠（確度中、要・実機確認）。

## Amazon Q CLI の事実（doc/一般知識ベース・未検証）
- binary: `q`。対話チャットは `q chat`（サブコマンド）で起動。
- 2025-11 に Kiro CLI へ改称。`q` / `q chat` は後方互換で引き続き利用可。
- 自律実行（bypass）: `q chat --trust-all-tools`（全ツールを承認なしで実行）。
- resume: `q chat --resume`（カレントディレクトリに紐づく直近の会話を再開）。Phlox は per-session 作業ディレクトリのため `--resume` で当該セッションを正しく継続できる（id 非依存）。
- hooks: Phlox 互換の hook 連携は無い → 完了検知は idle-fallback。

---

## 実装タスク（opencode と同型。差分は「base 引数 `chat`」「bypass は `--trust-all-tools`」「resume は `--resume`」）

### 1. `Packages/AgentDomain/Sources/AgentDomain/AgentKind.swift`
- `case amazonQ` を `goose` の後に追加。
- `displayName`: "Amazon Q" / `binaryName`: "q" / `symbolName`: "q.square.fill"。

### 2. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/AgentLaunchPlanner.swift`
- `profile()` に追加:
  ```swift
  case .amazonQ:
      return AgentLaunchProfile(
          // chat: 対話サブコマンド。--trust-all-tools: 全ツールを承認なしで実行（自律実行に必須）。
          extraArgs: ["chat"] + (bypassEnabled ? ["--trust-all-tools"] : []),
          hookIntegration: .none,
          scrollbackPolicy: .keep,
          statusBootstrap: .idleOnSpawnComplete
      )
  ```
- `applyLaunchMode` に追加:
  ```swift
  case (.amazonQ, .newSession):
      return baseArgs
  case (.amazonQ, .resume):
      // カレントディレクトリ(per-session)に紐づく直近会話を再開する（id 非依存）。
      return baseArgs + ["--resume"]
  ```

### 3. `Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift`
- `amazonQKey = "phlox.bypass.amazonQ"` 追加、`defaultsDictionary` に `amazonQKey: true`、`key(for:)` に `case .amazonQ: amazonQKey`。

### 4. `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`
- `initialResumeID(for:sessionID:)` に `case .amazonQ: return nil`（ネイティブ id は使わず、resume は `--resume` で cwd 紐づけ）。

### 5. `Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift`
- `public let agentAmazonQ: RGB` を追加。
- ANSI 由来 `from(...)` 初期化に `agentAmazonQ: ansi[1]` を追加。
- 静的デフォルトに `agentAmazonQ: RGB(0x9B, 0x59, 0xD0)`（紫）を追加。
- ※ コンパイラが全初期化箇所を検出するので漏れなく埋める。

### 6. `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`
- `agentColor(for:)` の switch に `case .amazonQ: theme.agentAmazonQ.color`。既存ケースに触れない。

### 7. `Packages/DashboardFeature/Sources/DashboardFeature/Usage/UsageMonitor.swift`
- 2 つの init の providers 辞書に `.amazonQ: EmptyUsageProvider(kind: .amazonQ)` を追加。

### 8. `App/CompositionRoot.swift`
- バイナリ解決ループに `.amazonQ` を追加（`[.codex, .cursor, .gemini, .opencode, .goose, .amazonQ]`）。

### 9. `App/SettingsView.swift`
- 既存 CLI に倣い amazonQ の bypass トグルを追加。

### 10. テスト
- `AgentLaunchPlannerTests.swift` の kind に対する exhaustive switch / パラメタライズド arguments に `.amazonQ` を追加。
- amazonQ の launch-plan テストを1つ追加: command が q、`extraArgs` 先頭が `chat`、bypass 有効時に `--trust-all-tools` を含む、`statusBootstrap == .idleOnSpawnComplete` を検証。
- `AgentKindTests.swift` を allCases=7 / binaryName="q" に更新。
- `App/PhloxApp.swift` のメニューが allCases 列挙なら自動露出。switch なら追加。

---

## 厳守事項
- サージカル編集のみ。既存スタイル・日本語コメントに合わせる。
- ベースは最新 `feature/ai-cli-integration`（Gemini/opencode/Goose 統合済み）。AppTheme/Tokens/BypassSettings/UsageMonitor/SettingsView には既に gemini/opencode/goose ケースがある前提で amazonQ を追加。
- 実装後に自己検証: `xcodebuild ... build` と `cd Packages/DashboardFeature && swift test` / `cd Packages/AgentDomain && swift test`。結果を正直に報告。テストの削除・skip・期待値改ざん禁止。
- **コミットしない**（PM が検証後に行う）。

## 検証
1. PM: `xcodebuild` 成功 + `swift test` 全 pass を実走確認 + amazonQ launch-plan テスト確認。
2. ユーザー（全CLI完了時・要 q インストール + AWS 認証）: Phlox から amazonQ を spawn → 送受信 → idle 完了検知の通し確認。
