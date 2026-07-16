---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-09
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
| `chat-mode-ux-components.md` | チャットモード UX コンポーネント構成（composer/transcript/サジェスト等の現行分割） |
| `chat-orchestration.md` | チャットモードのオーケストレーション（`$PHLOX_CLI` spawn/send/wait の現行配線） |
| `chat-revert-escape-and-interrupt.md` | チャットの中断・Esc・履歴リバート機構 |
| `chat-subagent-display.md` | サブエージェント別チャット表示の現行構造 |
| `claude-chat-session-lifecycle.md` | Claude チャットセッションのプロセスライフサイクル（spawn/respawn/self-heal） |
| `dashboard-empty-state-agent-cards.md` | 空状態のエージェント選択カード（セッション未選択→カードで spawn） |
| `dashboard-pane-layout.md` | Dashboard 3ペインレイアウトと幅クランプ（PaneWidthPolicy・クランプ発火点） |
| `claude-usage-supply.md` | Claude Usage（5h/7d 残量）キャッシュの供給経路（statusLine＋`/usage` プローブ） |
| `design-system.md` | Phlox デザインシステム（macOS 本体・`Packages/DesignSystem`） |
| `mobile-proxy.md` | モバイル連携（Tailscale→MobileProxy→ControlServer、トークン・API・バインド方針） |
| `team-timeline-view.md` | アゴラ（旧チーム表示・グループチャット）の構造 |
| `session-grid-layout.md` | グリッドビューの固定 N×N レイアウト・セッション自由配置・セル結合（配置モデル/永続化/reconcile） |
