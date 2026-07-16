---
status: active
last-verified: 2026-07-04
---

# 調査レポート: Phlox が対応可能な AI エージェント CLI

- 作成日: 2026-06-09
- 種別: 調査レポート（実装なし）
- 完了検知の方針: hook方式（正確）と idle-fallback方式（best-effort）の**両方を許容**し、対応CLI数を最大化する前提で可否を判定
- 注記（誠実性）: 各 CLI の「対応可否」は ①Phlox のコード実体の読解 と ②各 CLI の公開ドキュメント・先行事例（`coder/agentapi`）からの **評価** である。**各 CLI を Phlox 上で実走検証したものではない**。実証には §7「検証方法」の手順が要る。

---

## Context（なぜこの調査か）
Phlox は複数の AI エージェント CLI をペイン上で起動・制御するオーケストレーター。現状は `AgentKind` enum に **Claude Code / Codex / Cursor の3種をハードコード**して対応している。「あらゆる AI エージェント CLI に対応したい」というゴールに対し、本調査は現アーキで **どの CLI が対応可能か / どの程度のコストか / 対象外は何か** を切り分け、優先度とロードマップを示す。

---

## 1. 対応可能性を決める Phlox 側の事実（コード根拠）

### 1-1. CLI 非依存の中核（=どの CLI でも共通で動く部分）
- **プロンプト送信**: PTY マスター FD へ UTF-8 を書き込み、`submit` 時は 250ms 後に `\r`（CR）を送る（`SessionViewModel.submitKeyDelay`。codex のペーストバースト Enter 抑制窓 120ms を超える値。ADR 0002 §8 参照）。CLI 固有差はない。
  - `Packages/DashboardFeature/.../Dashboard/DashboardViewModel.swift`（`sendMessage`, 行 681-768）
  - `Packages/PTYKit/Sources/PTYKit/PTYManager.swift`（`write`, 行 109-114）
- **出力回収**: 端末ビューポートの可視テキストを取得（`terminalCoordinator.visibleText()`）。CLI 固有差はない。scrollback は未実装（screen モードのみ）。
- **CLI 検出**: login shell の `$PATH` から `command -v <binaryName>` で解決。見つかった CLI だけ起動可能になる。
  - `App/CompositionRoot.swift`（`resolveClaudeBinaryAndPath`, 行 232-329）
- **UI 露出**: メニューは `availableAgentKinds` を動的列挙。enum に case があり PATH 上にバイナリがあれば自動でメニューに出る。
  - `Packages/DashboardFeature/.../Dashboard/DashboardView.swift`（L716-743, L323-339）

### 1-2. CLI ごとに分岐が必要な部分（=対応コストの正体）
新規 CLI 追加時に switch/分岐を足す必要があるファイル群（約11箇所）:
1. `Packages/AgentDomain/.../AgentKind.swift` — enum case + displayName/binaryName/symbolName
2. `Packages/DashboardFeature/.../Spawn/AgentLaunchPlanner.swift` — 起動引数・hook統合・状態初期化（`profile`, `applyLaunchMode`）
3. `Packages/DashboardFeature/.../Spawn/SessionHookInstaller.swift` — hookファイル設置の分岐
4. （hook方式なら）新規 `XxxHooksManager.swift` — `.xxx/hooks.json` テンプレート生成
5. `App/CompositionRoot.swift` — バイナリ解決対象に追加
6. `Packages/DesignSystem/.../Tokens.swift` — エージェント色
7. `Packages/DashboardFeature/.../Environment/BypassSettings.swift` — bypass キー/分岐
8. `Packages/DashboardFeature/.../Usage/UsageMonitor.swift` + 新規 `XxxUsageProvider.swift` — 使用量取得（任意）
9. `Packages/DashboardFeature/.../Dashboard/DashboardViewModel.swift` — resume ID 生成（`initialResumeID`）
10. `App/PhloxApp.swift` — メニュー/コマンド
11. `Packages/ControlServer/.../ControlTypes.swift` — spawn の AgentKind 参照

**設定ファイル/プラグインによる外部追加機構は存在しない**（enum 改修=コード変更が必須）。

### 1-3. 完了検知の2系統（対応可否の主要分岐点）
| 方式 | 対象 | 仕組み | 正確さ |
|---|---|---|---|
| **hook方式** | Claude Code（現）。Codex/Cursor も hooks.json 経由 | CLI が `stop` フックを発火 → `hook-dispatcher.sh` → HookServer → `status=.idle`、`turnId` で誤マッチ防止 | 正確 |
| **idle-fallback方式** | Codex/Cursor（現） | 送信後に出力を検出し、**400ms 新規出力が無ければ完了とみなす** | best-effort |

- 実装: `SessionViewModel.swift`（hook: 行170-203 / idle: `scheduleNonHookIdleFallback`, 行589-627）
- **重要な結論**: idle-fallback は **任意の対話型 CLI に一般化できる**。hook が無い CLI でも「広く対応」できるのはこの仕組みのため。ただし §5 のとおり誤検知リスクがある。

### 1-4. 先行事例（汎用化の実在証明）
`coder/agentapi` は **Phlox と同型の方式**（PTY 上の端末エミュレータ + スナップショット差分で `stable`/`running` 判定）で、`--type` フラグの差分吸収だけで **11種**を1つの HTTP API に統合している:
**Claude Code / Codex / Cursor CLI / Gemini / Goose / Aider / Amazon Q / GitHub Copilot / Amp / Auggie / opencode**。
→ Phlox の現アプローチが「あらゆる CLI 対応」へ拡張可能であることの実例。

---

## 2. 対応可否の判定基準
CLI が Phlox で対応可能なのは、次を満たすとき:
1. **対話型 TUI として PTY 上で常駐する**（必須。ワンショット出力やGUI/SaaS専用は不可）
2. プロンプトを標準入力（キーストローク）+ Enter で受け付ける（ほぼ全 TUI が該当）
3. 応答が端末に可視出力される（同上）
4. 完了検知が **hook対応（Tier A・正確）** または **idle-fallbackで成立（Tier B・best-effort）**

**対象外（Tier C）**: IDE拡張（VS Code 等に常駐し端末 TUI を持たない）/ GUIエディタ製品 / 完全クラウドSaaSエージェント / 非対話バッチ専用。

---

## 3. 対応可否カタログ（評価ベース）

凡例: ✓現=既対応 / Tier A=hookで正確 / Tier B=idle-fallbackで対応可 / Tier C=対象外
「hook確度」: 公開ドキュメント等で確認できた度合い（高/中/要確認）

### Tier A — hook対応（正確な完了検知が見込める）
| CLI | binary（想定） | hook確度 | 備考 |
|---|---|---|---|
| Claude Code ✓現 | `claude` | 高 | `--settings` 経由 |
| Codex ✓現 | `codex` | 高 | `.codex/hooks.json` |
| Cursor (agent) ✓現 | `cursor-agent` | 高 | `.cursor/hooks.json` |
| **Gemini CLI** | `gemini` | 高（`stop`含むライフサイクルhookを公式提供） | 既存パターンに最も近い。追加の本命 |
| **Aider** | `aider` | 中（hook/イベントの記載あり） | 完了検知の実挙動は要確認 |
| **Amp**（Sourcegraph） | `amp` | 中 | agentapi も `--type=amp` を持つ |
| iFlow | `iflow` | 中 | hook対応の記載あり |

### Tier B — 対話型TUI、idle-fallbackで対応可（best-effort）
opencode / Goose（Block） / Amazon Q Developer CLI（`q chat`） / GitHub Copilot CLI / Qwen Code / Crush（Charm） / Cursor CLI（shell/headless） / Kimi CLI（Moonshot） / Grok CLI / Mistral Vibe / Plandex / OpenHands（CLI） / gptme / Continue CLI / Kilo Code CLI / Roo Code CLI（CLI版） / Trae / ForgeCode / Droid（Factory） など多数。
- これらは hook を前提にせず、出力が止まったら完了とみなす方式で取り込める。
- 一部（opencode/Goose 等）は将来 hook を備えれば Tier A に格上げ可能。

### Tier C — 対象外（端末TUIで常駐しない/GUI/SaaS）
- IDE拡張: **Cline / Roo Code（VS Code拡張形態） / Continue.dev / Tabby**
- GUIエディタ・製品: **Cursor（IDE本体） / Windsurf / Zed / Antigravity / Kiro / Warp（端末アプリ自体）**
- クラウド/リモートSaaS: **Devin / Mentat（リモート管理） / Tabnine（Docker配布の形態次第）**
- ※ Cursor は「IDE本体=対象外」だが「`cursor-agent` CLI=対応済み」。製品名と CLI 形態を分けて判断する必要がある。

---

## 4. 追加コスト（現アーキ前提）
- **Tier B の CLI 1個追加**: enum case + §1-2 の分岐（主に Launch/UI/色/検出）。hook不要なので `idleOnSpawnComplete` を流用でき比較的軽い。UsageProvider は任意。
- **Tier A の CLI 1個追加**: 上記に加え `XxxHooksManager`（`.xxx/hooks.json` スキーマ作成）と `hook-dispatcher.sh` の対応（現スクリプトは codex/cursor 形を汎用処理しているため、`stop` の JSON 形が同型なら流用可）。
- **共通の隠れコスト**: resume/session-id の意味づけが CLI ごとに異なる（`initialResumeID`）、bypass フラグ（自律実行許可）の有無と引数、表示色/アイコン。
- **本質的な負債**: §1-2 のとおり「1 CLI = 約11ファイル改修」。CLI を増やすほど switch 分岐が散らばる。将来的には設定駆動レジストリ（`agentapi` の `--type` モデル）への refactor が効く。

---

## 5. 制約・注意点（誤検知と運用リスク）
- **idle-fallback の誤検知**: ストリーミング途中の小停止、思考中のスピナー停止、ツール承認待ちで 400ms 無出力になると **早すぎる「完了」判定**が起こりうる。CLI ごとに settle 時間調整が要る可能性。
- **ready 検知のばらつき**: 起動完了の判定（初回出力+settle）は CLI の起動演出（ロゴ2段描画など）で揺れる。Cursor は実際に `debugDump` で対策済み。新規 CLI でも同様の調整が要りうる。
- **端末UIアーティファクト**: 出力回収は可視テキストそのままのため、CLI 固有の枠線/プロンプト装飾が混ざる。agentapi も「CLI 更新で除去ロジックの保守が要る」と明記。Phlox でも同様の保守が発生する。
- **承認プロンプト処理**: Codex は信頼プロンプト自動応答を個別実装済み。CLI ごとに同種の対話処理が要る場合がある。
- **使用量メータリング**: CLI ごとに取得方法がバラバラ（任意機能）。未実装でも spawn/送受信自体は可能。

---

## 6. 推奨ロードマップ（提言）
1. **短期（既存パターンで足せる本命）**: **Gemini CLI**（Tier A、`stop` hook あり）を追加。既存 codex/cursor の hooks.json パターンに最も近い。
2. **短期（idle-fallbackで広く）**: **opencode / Goose / Amazon Q Developer CLI** を Tier B として追加。hook不要で取り込め、カバレッジを一気に広げられる。
3. **中期（負債解消）**: `AgentKind` enum を **設定駆動レジストリ**へ refactor（binary / 起動引数 / hookスキーマ / 完了検知モード / 色 を宣言的プロファイル化）。`agentapi` の `--type` 抽象が参考。1 CLI=11ファイル改修を解消する。
4. **長期（あらゆる対応）**: ユーザー定義 CLI を JSON で追加できる仕組み（カスタムコマンド）。ここまで来れば「あらゆる AI エージェント CLI」を enum 改修なしで取り込める。

---

## 7. 検証方法（本レポートの主張を実証するなら）
本レポートは未実証評価のため、対応可否を確定するには CLI ごとに次を実行する:
1. PATH に当該 CLI を用意し、Phlox の PTY で対話起動できるか（プロンプト到達 + 初回出力）。
2. プロンプト送信 → 応答が `visibleText()` で回収できるか。
3. 完了検知: hook方式なら `stop` が HookServer に届くか（`scripts/hook-dispatcher.sh` 相当の JSON 形を確認）。idle方式なら 400ms settle で過不足ない完了判定になるか（誤検知の有無）。
4. ビルド/テスト（実装に進む場合）:
   ```bash
   xcodebuild -project Phlox.xcodeproj -scheme Phlox \
     -configuration Debug -derivedDataPath /tmp/PhloxBuild build
   swift test   # 該当パッケージ
   ```

---

## 出典（Web調査分）
- Every AI Coding CLI in 2026: The Complete Map — https://dev.to/soulentheo/every-ai-coding-cli-in-2026-the-complete-map-30-tools-compared-4gob
- coder/agentapi（PTY+stable/running 判定で11種統合）— https://github.com/coder/agentapi
- awesome-cli-coding-agents（網羅リスト）— https://github.com/bradAGI/awesome-cli-coding-agents
- Gemini CLI hooks（stop含むライフサイクル）— https://geminicli.com/docs/hooks/ , https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/reference.md
- Best CLI AI Tools 2026 — https://kilo.ai/articles/best-cli-coding-agents , https://www.tembo.io/blog/coding-cli-tools-comparison
