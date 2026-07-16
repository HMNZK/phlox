---
status: active
last-verified: 2026-07-07
---

# ADR 0041: Gemini / OpenCode / Goose の CLI サポートを削除し、既定 CLI を Claude/Codex/Cursor の3種に限定する

> **このファイルの役割**: なぜ 6 CLI から 3 CLI へ削減したかの決定・文脈・結果。
> **書かないもの**: 現行の CLI レジストリ構造（→ `AgentDomain/AgentDescriptor.swift` と architecture）。

## 文脈

Phlox は当初 6 種の CLI エージェント（claudeCode / codex / cursor / gemini / opencode / goose）を `AgentKind` レジストリで宣言的に扱っていた。後者3種（Gemini CLI / OpenCode / Goose）は実験的統合で、それぞれ固有の hook 統合（`GeminiHooksManager`・`.geminiStyle` hook）・launchSpec・bypass 設定・identity 色・多数の個別テストを抱えていた。structured chat 対応（ADR 0015/0017）は claude/codex/cursor の3種に集約されており、gemini/opencode/goose は PTY ターミナルモードの `.idleOnSpawnComplete` 経路のみで、実運用の主対象から外れていた。

保守面では、3種の存在が `AgentKind` 網羅 switch・テストの前提件数・`AppTheme.agentColors`・ブランドアイコン fallback などに常時コストを課していた。

## 決定

Gemini / OpenCode / Goose の CLI サポートを **完全削除**し、既定 CLI を **Claude Code / Codex / Cursor の3種に限定**する。

削除対象:
- `AgentKind` の enum ケース（gemini/opencode/goose）と `AgentRegistry.allDescriptors` の3ブロック
- `AgentHookKind.geminiStyle` / `HookIntegration.geminiHooks` / `GeminiHooksManager.swift`（ファイルごと）
- `AgentLaunchPlanner` / `SessionHookInstaller` の kind 別分岐
- `BypassSettings` の geminiKey/opencodeKey/gooseKey
- `AppTheme.agentColors` の該当エントリ（ANSI/RGB 両定義）
- リポジトリルートの `.goosehints` / `GEMINI.md`
- 各テストの該当ケース（realGoose 実統合テスト削除、E2E の `.opencode`→`.cursor` 置換）

## 棄却案

- **3種を残しつつ非表示にする**: レジストリ・テスト・hook 分岐のコストが残り、削減目的を達しない。
- **共通抽象に寄せて残す**: 実運用されない CLI のための抽象は投機的で、保守負債を増やす。

## 結果

- `AgentKind` は claude/codex/cursor の3ケースのみ。全ビルド・全テスト green（削除に伴うコンパイル連鎖を全追随）。
- `docs/specs/{gemini,opencode,goose}-*.md` は `status: superseded`（本 ADR にリンク）。
- 回帰ガード: `CliRemovalAcceptanceTests`（AgentKind が3種のみ・レジストリ3件・binaryName に gemini/opencode/goose なし）。
- ADR 0015（structured chat の multi-CLI 基盤）の「multi-CLI」は claude/codex/cursor の範囲に縮小されたと解釈する（0015 自体は supersede しない＝基盤設計は不変）。
- テスト側で「非 hook / idle-fallback」用途に使っていた `.opencode` は、同じ `.idleOnSpawnComplete` を持つ `.cursor` へ置換（idle-fallback 機構の検証意図は保持。ただし `.cursor` は hook を持つため、fake agent では hook イベントが発生しない前提での置換）。
</content>
