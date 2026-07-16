---
status: superseded
last-verified: 2026-07-07
---

> **SUPERSEDED（2026-07-07）**: この CLI は Phlox から削除された（ADR 0041）。本仕様は歴史的記録として残す。

# Gemini CLI 統合 実装仕様 (ロードマップ#1 / Tier A)

- 対象: `AgentKind` に `gemini` を追加し、Claude/Codex/Cursor と同列に Gemini CLI を起動・制御できるようにする。
- 担当: 実装は Codex（ヘッドレス）、検証・統合は ClaudeCode(PM)。
- 完了検知方式: **Cursor/Codex と同一のハイブリッド** = `.gemini/settings.json` に hooks を設置（`AfterAgent`→`stop` でターン完了を正確検知）しつつ `statusBootstrap = .idleOnSpawnComplete`（hook 未発火でも出力アイドルで完了検知）。
- 既知の制約（未検証点）: Gemini は OAuth ログインを要求するため、本実装時点で **hook の実発火は実機検証できていない**。設計上 idle-fallback に graceful degrade するため動作はするが、hook 経路は要・実機検証（§検証）。

---

## Gemini CLI の事実（確認済み）
- バイナリ: `gemini`（v0.1.7）。ヘッドレスは `-p/--prompt`。
- 自律実行フラグ: `-y/--yolo`（全アクション自動承認）。= Codex の bypass / Cursor の `--force` 相当。
- `--resume <id>` 相当の CLI フラグは無い → resume はネイティブ非対応（新規起動のみ）。
- hooks: プロジェクトローカル `.gemini/settings.json` の `hooks` を読む。stdin で JSON ペイロード受領。ペイロード基本フィールド: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`。
- 主要イベント: `SessionStart`(起動/resume/clear), `BeforeAgent`(プロンプト送信後・計画前), `AfterAgent`(**ターンごとに最終応答後1回**=完了), `BeforeTool`/`AfterTool`, `Notification`, `SessionEnd`(終了)。

## 既存 dispatcher との対応（hook-dispatcher.sh は変更不要）
`scripts/hook-dispatcher.sh` は `$1`=kind を受け、stdin JSON から抽出して POST する汎用実装。Gemini のイベントを既存 kind にマップするだけで流用可。`session_id`→nativeSessionId は抽出済み。`stop` の turn_id/exit_code が無くても既存ロジックが許容（turnId 省略時は無条件で完了カウント+1）。

| Gemini イベント | dispatcher kind |
|---|---|
| SessionStart | `sessionStart` |
| AfterAgent | `stop` |
| BeforeAgent | `userPromptSubmit` |
| BeforeTool | `preToolUse` |
| AfterTool | `postToolUse` |
| Notification | `notification` |

---

## 実装タスク（全13点）

### 1. `Packages/AgentDomain/Sources/AgentDomain/AgentKind.swift`
- `case gemini` を `cursor` の後に追加。
- `displayName`: "Gemini CLI" / `binaryName`: "gemini" / `symbolName`: "diamond.fill"。

### 2. `Packages/AgentDomain/Sources/AgentDomain/AgentLaunchProfile.swift`
- `HookIntegration` に `case geminiHooks(hookURL: URL)` を追加（doc コメント: Gemini は CWD 配下 `.gemini/settings.json` を自動ロード）。

### 3. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/AgentLaunchPlanner.swift`
- `plan()` の hookIntegration switch に `case .geminiHooks(let hookURL): env["CLAUDE_HOOKS_URL"] = hookURL.absoluteString` を追加。
- `applyLaunchMode` に `case (.gemini, .newSession): return baseArgs` と `case (.gemini, .resume): return baseArgs` を追加（resume は CLI フラグ非対応のため引数追加なし。コメントで明記）。
- `profile()` に以下を追加:
  ```swift
  case .gemini:
      return AgentLaunchProfile(
          // -y/--yolo: 全アクションを自動承認（アプリ管理下の自律実行に必須）。
          extraArgs: bypassEnabled ? ["--yolo"] : [],
          hookIntegration: .geminiHooks(hookURL: environment.hookURL),
          scrollbackPolicy: .keep,
          statusBootstrap: .idleOnSpawnComplete
      )
  ```

### 4. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/HookFileInstaller.swift`
- `install(...)` に `fileName: String = "hooks.json"` 引数を追加し、`hooksDir.appendingPathComponent("hooks.json")` を `appendingPathComponent(fileName)` に変更。既存 codex/cursor 呼び出しは引数省略で従来どおり。cleanup は保存済み URL を使うため変更不要。

### 5. 新規 `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/GeminiHooksManager.swift`
- `CursorHooksManager` を雛形に、`.gemini` ディレクトリ + `settings.json`。
- `hooksFileURL`: `.gemini/settings.json`。
- `hookCommand`: dispatcher + kind（env 前置なし、cursor と同様）。
- `hooksSettings`: Gemini スキーマ。各エントリは `["matcher": "*", "hooks": [["type": "command", "command": cmd]]]`。トップレベル `"hooks"` 配下に上表の対応でイベントを登録（SessionStart/AfterAgent/BeforeAgent/BeforeTool/AfterTool/Notification）。
- `install`: `HookFileInstaller.install(directoryName: ".gemini", fileName: "settings.json", settings:..., dispatcherPath:..., in: workingDirectory, fileManager:...)`。
- `cleanup`: `HookFileInstaller.cleanup` 委譲。

### 6. `Packages/DashboardFeature/Sources/DashboardFeature/Spawn/SessionHookInstaller.swift`
- `install()` の `case .codex, .cursor:` を `case .codex, .cursor, .gemini:` に。
- `performFileInstall()` に `case .gemini:` を追加し `GeminiHooksManager.install(...)` を呼ぶ（cursor と同形）。

### 7. `Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift`
- `geminiKey = "phlox.bypass.gemini"` 追加、`defaultsDictionary` に `geminiKey: true`、`key(for:)` に `case .gemini: geminiKey`。

### 8. `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`
- `initialResumeID(for:sessionID:)` に `case .gemini: return nil`。

### 9. `Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift`
- `public let agentGemini: RGB` を追加。
- ANSI 由来 `from(...)` 初期化（agentCursor 付近）に `agentGemini: ansi[6]` を追加。
- 静的デフォルト（agentCursor 付近）に `agentGemini: RGB(0x46, 0x86, 0xF4)`（Gemini ブルー）を追加。
- ※ `agentGemini` を持つ初期化箇所が他にあればコンパイラが検出するので全て埋める。

### 10. `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`
- `agentColor(for:)` の switch に `case .gemini: theme.agentGemini.color` を追加。
- **重要**: このファイルには未コミットの `sessionRowHover` / `newSessionGradient` 変更がある。**その hunk には一切触れず**、`agentColor` の switch のみサージカルに編集すること。

### 11. `Packages/DashboardFeature/Sources/DashboardFeature/Usage/UsageMonitor.swift`
- 2 つの init の providers 辞書に `.gemini: EmptyUsageProvider(kind: .gemini)` を追加（使用量取得は当面 best-effort で「未設定」表示。実 Provider は将来対応）。public init では `EmptyUsageProvider` がファイル内 private のため利用可。

### 12. `App/CompositionRoot.swift`
- バイナリ解決ループ `for kind in [.codex, .cursor]` を `[.codex, .cursor, .gemini]` に。

### 13. テスト
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/AgentLaunchPlannerTests.swift` の kind に対する exhaustive switch（ヘルパ）へ `.gemini` を追加し、テストをコンパイル可能に。
- Gemini の launch-plan テストを1つ追加（codex/cursor のテストを雛形に）: command が gemini バイナリ、bypass 有効時に `--yolo` を含む、`CLAUDE_HOOKS_URL` env がセット、`statusBootstrap == .idleOnSpawnComplete` を検証。
- `App/PhloxApp.swift` の New session メニューが `ForEach(AgentKind.allCases)` なら自動露出。exhaustive switch なら `.gemini` を追加。要確認。

---

## 実装上の厳守事項
- 既存スタイル・日本語コメント慣習に合わせる。サージカル編集（無関係な整形・改善をしない）。
- **未コミット変更（Tokens.swift / UsageSidebarView.swift）の hunk を壊さない**。
- 実装後に自己検証する:
  - `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxBuild build`
  - `swift test`（DashboardFeature / AgentDomain）
  - 結果（成功/失敗・警告）を正直に報告。失敗は隠さない。
- **コミットはしない**（PM 側で検証後に行う）。

---

## 検証（PM 実施 + ユーザー実機）
1. PM: `xcodebuild` ビルド成功 + `swift test` 全 pass を実走確認。
2. PM: Gemini の launch-plan 単体テストで args/env/bootstrap を確認。
3. ユーザー（要・実機）: Gemini に Google ログイン済みの環境で、Phlox から Gemini セッションを spawn → プロンプト送信 → 応答回収 → 完了検知（hook 発火 or idle）を確認。hook が発火すれば正確、しなければ idle-fallback で完了する。

---

## 実装結果（2026-06-09・検証済み）
- 実装担当: Codex（ヘッドレス `codex exec`）。PM(ClaudeCode) が独立検証。
- 変更ファイル（17）: `App/CompositionRoot.swift` / `App/PhloxApp.swift` / `App/SettingsView.swift`(仕様外: bypass トグル追加) / `AgentKind.swift` / `AgentLaunchProfile.swift` / `AgentKindTests.swift` / `DashboardViewModel.swift` / `BypassSettings.swift` / `AgentLaunchPlanner.swift` / `HookFileInstaller.swift` / 新規 `GeminiHooksManager.swift` / `SessionHookInstaller.swift` / `UsageMonitor.swift` / `AgentLaunchPlannerTests.swift` / `AppTheme.swift` / `Tokens.swift`。
- **PM 独立検証（実走）**:
  - `xcodebuild ... build` → **BUILD SUCCEEDED**
  - `cd Packages/AgentDomain && swift test` → **39 tests passed**
  - `cd Packages/DashboardFeature && swift test` → **183 tests passed**
- サージカル確認: 未コミット WIP（`UsageSidebarView.swift` / `Tokens.swift` の hover・gradient）は無傷。`Tokens.swift` は `agentColor` の `.gemini` 追加のみ。
- **未検証（ユーザー実機のみ可能）**: Gemini の OAuth ログイン済み環境での hook 実発火、および Phlox からの spawn→送受信→完了検知の通し動作。コード上は hook 未発火でも idle-fallback で完了検知する設計。
