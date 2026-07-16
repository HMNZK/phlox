---
status: active
last-verified: 2026-07-09
---

# package-structure

**役割（ここにしか書かない）**: Phlox の SPM パッケージ構成と依存の向き（層構造）＝**今こう分かれて・どちら向きに依存している**。

**書かないもの**: なぜこの分割にしたか（→ `adr/`、特に 0001・0055・R1 分割）／各機能の内部設計（→ 各 feature の architecture doc）。

**Diátaxis**: Reference

## 構成（App ターゲット + 16 SPM パッケージ）

App ターゲット（`App/`）が全体を束ね、機能は SPM パッケージへ分割している（ADR 0001: MVVM + @Observable + SPM マルチモジュール）。本番依存は循環のない DAG で、下層ほど依存されるリーフ、上層ほど合成側。

| 層 | パッケージ | 本番依存先（同/下層のみ） | 役割 |
|---|---|---|---|
| L0（リーフ） | `AgentDomain` | なし | ドメイン値型・列挙（`SessionID`・`ApprovalDecision` 等の正本） |
| L0 | `StructuredChatKit` | なし | 構造化チャットの共有 DTO（`FilePatchChange` 正本ほか） |
| L0 | `LocalHTTPServer` | なし | 汎用 HTTP サーバ土台（`HTTPStatusText` 正本） |
| L0 | `TerminalUI` | なし | 端末描画コンポーネント |
| L0 | `MobileProxy` | なし | モバイル連携プロキシ |
| L1 | `DesignSystem` | AgentDomain | デザインシステム（色・フォント・共通 UI） |
| L1 | `MessageStore` | AgentDomain | メッセージ永続化（SQLite） |
| L1 | `PTYKit` | AgentDomain | PTY プロセス管理 |
| L1 | `HookServer` | AgentDomain, LocalHTTPServer | Hook 受信サーバ |
| L1 | `ControlServer` | AgentDomain, LocalHTTPServer | 制御コマンド受信サーバ |
| L1 | `ClaudeAgentKit` | StructuredChatKit | Claude チャットクライアント |
| L1 | `CursorAgentKit` | StructuredChatKit | Cursor チャットクライアント |
| L1 | `CodexAppServerKit` | AgentDomain, StructuredChatKit | Codex app-server クライアント |
| **L2** | **`SessionFeature`** | AgentDomain, DesignSystem, HookServer, PTYKit, TerminalUI, CodexAppServerKit, StructuredChatKit | **セッション UI/VM（チャット・グリッド・トランスクリプト・composer）** |
| L3 | `DashboardFeature` | SessionFeature + 上記 L0/L1 各種（ClaudeAgentKit/CursorAgentKit/MessageStore 等） | ダッシュボード・spawn・使用状況・ルーティング。`import SessionFeature` |
| L4 | `AppBootstrap` | AgentDomain, ControlServer, DashboardFeature, SessionFeature, StructuredChatKit | 起動合成・ControlActionHandler |
| L5 | App ターゲット | AppBootstrap, DashboardFeature, SessionFeature, ControlServer, MobileProxy, MessageStore, PTYKit（+ Sparkle） | CompositionRoot・エントリポイント |

## SessionFeature 分割（R1・2026-07-09）

以前は `DashboardFeature` 1 パッケージが全体の約 6 割を占める God パッケージだった。セッション UI/VM（旧 `DashboardFeature/Sources/DashboardFeature/Session/` 55 ファイル）を **`SessionFeature`（L2）** へ切り出し、`DashboardFeature`（L3）はそれを `import SessionFeature` で参照する一方向依存にした。`Spawn/`・`Dashboard/`・`Usage/`・`Environment/`・`Router/` は `DashboardFeature` に残る。

- Session 系テストは移設せず `DashboardFeatureTests` に留め、`@testable import SessionFeature` で内部アクセスを得ている（Fixtures リソース分割を避ける振る舞い保存判断）。
- クロスモジュール参照のため public 化したのは 3 型のみ: `ChatItemView`・`SessionGridView`・`ChatNativeSessionIDNotification`。

## 依存の向き（循環なしの確認）

本番ターゲットの依存は上表の「下層のみを指す」DAG で、循環はない。特に `AppBootstrap → DashboardFeature` は一方向で、逆向き（`DashboardFeature` 本番ターゲット → `AppBootstrap`）は存在しない（R3 評価: ADR 0055）。`DashboardFeatureTests` は統合検証のため `AppBootstrap`・`ControlServer` に依存するが、これはテストターゲット限定で本番の層構造に循環を生まない。
