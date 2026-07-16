---
status: active
last-verified: 2026-07-04
---

# Codexレビュー指摘(重大+中)の修正 仕様

- 対象ブランチ: `feature/ai-cli-integration`。**main マージしない**(コミットまで)。
- 担当: 実装は Codex(シニア)にヘッドレス委譲。検証・コミットは ClaudeCode(PM)。
- 背景: 7CLI追加+レジストリ化+ユーザー定義CLI(JSON)に対する3者レビュー(ClaudeサブエージェントA/B + Codex)。糊塗は無しだが「機能としての未完・誤フラグ」を Codex が指摘。本修正で重大+中に対応する。

## 修正項目

### ① [重大] カスタムCLIの bypass を UI から制御可能にする
- 現状: `BypassSettings.isEnabled` は未設定キーで true。`SettingsView` は `AgentKind.allCases` のみ列挙し custom を出さない → custom の `bypassArgs`/`bypassEnv` が切れない。
- 修正: `SettingsView` の bypass トグル一覧を、組込(`AgentKind.allCases`)に加え**ロード済み custom descriptor も列挙**する形に変更(`availableAgentDescriptors` 等、registry/catalog 由来の全 descriptor を使う)。custom も `phlox.bypass.<id>` キーでトグル可能にする。
- 既定値: 組込と同じく既定 true(整合性)。ただし**UI から無効化可能**にすることが本項の主目的。トグルの label は descriptor の displayName/symbolName を使用。

### ② [中] ControlServer / $PHLOX_CLI を AgentRef 対応にし custom も spawn 可能にする
- 現状: `ControlTypes.swift` / `ControlServer.swift` の spawn は `AgentKind` 固定。custom id は 400。
- 修正: spawn の kind パラメータを **AgentRef 解決**に変更。`phlox spawn --kind <id>` の `<id>` を:
  - 組込 `AgentKind` rawValue に一致 → `.builtin(kind)`
  - ロード済み custom descriptor の id に一致 → `.custom(id)`
  - どちらでもない → 400(明確なエラーメッセージ)
- `ControlActionHandler` / `DashboardViewModel.spawnNewSession(ref:)` に AgentRef を渡す経路で接続。組込の既存挙動は不変(後方互換)。

### ③ [中] custom が `.kind` アクセサの preconditionFailure を踏まない経路整理
- 対象: `AgentDescriptor.swift` / `AgentLaunchPlanner.swift` / `PersistedSessionDescriptor.swift` / `SessionViewModel.swift` 等に残る、custom で `preconditionFailure` する `.kind` アクセサ。
- 修正: ②で API 経路が ref 化された後、custom が到達しうる経路は全て AgentRef ベースにする。真に到達不能な不変条件のみ precondition を残し、custom が踏みうる箇所は ref 対応に置換。custom セッションが spawn→永続化→復元→起動→completion まで `.kind` precondition を踏まないことをテストで保証。

### ④ [中] CLI フラグの是正(再調査済み)
- **opencode**: bypass を `--dangerously-skip-permissions`(非公式・現行不確実)から **環境変数 `OPENCODE_PERMISSION={"*":"allow"}`** に変更。descriptor の bypassArgs を空にし bypassEnv に `OPENCODE_PERMISSION` を設定。resume `--continue` は維持。
  - **opencode の既存 launch-plan テストの期待値を、この修正後の値(bypassEnv に OPENCODE_PERMISSION、bypassArgs 無し)に更新する**。これは誤フラグの是正に伴う正当な期待値変更(糊塗ではない)。コミット/報告で明示。
  - 出典: OpenCode は `OPENCODE_PERMISSION={"*":"allow"}` で全許可(env)。`--dangerously-skip-permissions` は非公式 Easter egg。
- **Amazon Q**: `q chat --trust-all-tools` は **Kiro 改称後も後方互換で有効**のため descriptor は変更不要。`docs/specs/amazon-q-integration.md` に「2025-11 に Kiro CLI へ改称。`q`/`q chat` は後方互換で引き続き利用可」の注記を追記。

## 不変条件・厳守事項
- 組込7 CLI の挙動は opencode の④を除き不変。**opencode 以外の `AgentLaunchPlannerTests` 既存アサーションは unchanged**。opencode のアサーションのみ④に合わせて更新(変更理由をコメントで明記)。
- 既存テスト全 pass(opencode テストは新期待値で pass)。糊塗(skip/削除/握りつぶし)禁止。
- サージカル編集。既存スタイル・日本語コメント遵守。
- 追加テスト:
  - ControlServer spawn: 組込id→builtin ref、custom id(ロード済み)→custom ref、未知id→400。
  - custom セッションが spawn→永続化→復元→launch まで preconditionFailure を踏まないこと。
  - opencode descriptor が bypassEnv に `OPENCODE_PERMISSION` を持ち bypassArgs を持たないこと。
  - BypassSettings が custom id(`phlox.bypass.<id>`)で機能すること。

## 自己検証 & 報告(Codex)
- `xcodebuild ... build` と `swift test`(AgentDomain/DashboardFeature)を実走し、pass/fail を正直に報告。
- 変更/新規ファイル一覧・テスト結果・期待値を変更した箇所(opencode)とその理由・残課題を簡潔に。
- runtime(実アプリ/実バイナリ)は未検証で可。後方互換・ref 経路は単体テストで担保。
- **コミットしない**(PM が検証後に commit)。
