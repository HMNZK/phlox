---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-26
---

# architecture/

**役割（ここにしか書かない）**: 現行アーキテクチャ（構成・データモデル・I/F・コンポーネント）＝**今こう動いている**

**書かないもの**: なぜそうしたか（→ adr/）

**Diátaxis**: Explanation / Reference

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 現在あるファイル（すべて status: active）

| ファイル | 内容 |
|---|---|
| `package-structure.md` | SPM パッケージ構成と依存の向き（層構造・SessionFeature 分割・循環なしの確認） |
| `app-data-storage-and-flavor.md` | アプリのデータ保存先とビルド種別（AppFlavor: Release/Debug 分離） |
| `agent-model-catalog.md` | spawn 前モデル一覧の live 取得・保持・消費（AgentModelCatalog、CLI パース、フォールバックと観測） |
| `chat-mode-ux-components.md` | チャットモード UX コンポーネント構成（composer/transcript/サジェスト等の現行分割） |
| `chat-orchestration.md` | チャットモードのオーケストレーション（`$PHLOX_CLI` spawn/send/wait の現行配線） |
| `agent-management-console.md` | 「エージェント管理」ウィンドウと `AgentConfigKit`（Claude Code / Codex / Cursor の設定・対話 TUI 専用スラッシュコマンドの置き換え・会話エクスポート） |
| `chat-revert-escape-and-interrupt.md` | チャットの中断・Esc・履歴リバート機構 |
| `chat-subagent-display.md` | サブエージェント別チャット表示の現行構造 |
| `claude-chat-session-lifecycle.md` | Claude チャットセッションのプロセスライフサイクル（spawn/respawn/self-heal） |
| `dashboard-empty-state-agent-cards.md` | 空状態のエージェント選択カード（セッション未選択→カードで spawn） |
| `dashboard-pane-layout.md` | Dashboard 3ペインレイアウトと幅クランプ（PaneWidthPolicy・クランプ発火点） |
| `claude-usage-supply.md` | Claude Usage（5h/7d 残量）キャッシュの供給経路（statusLine＋`/usage` プローブ） |
| `design-system.md` | Phlox デザインシステム（macOS 本体・`Packages/DesignSystem`） |
| `mobile-proxy.md` | モバイル連携（Tailscale→MobileProxy→ControlServer、トークン・API・バインド方針） |
| `team-timeline-view.md` | チームビュー (Beta)（旧アゴラ・グループチャット）の構造 |
| `session-pane-layout.md` | グリッドビューの分割ツリーレイアウト（モデル/幾何/操作/描画制約/永続ツリーと実効ツリー） |
| `session-grid-layout.md` | **superseded** → session-pane-layout.md（旧 固定 N×N・セル結合） |
