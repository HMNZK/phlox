---
status: active
last-verified: 2026-07-04
---

# ADR 0001: Agent Dashboard アーキテクチャ

- ステータス: Accepted
- 作成日: 2026-05-28
- コンテキスト: macOS SwiftUI アプリ「Agent Dashboard」の初期アーキテクチャ決定

## 1. 背景

複数の Claude Code セッションをターミナルで並行運用すると、どのセッションが完了しているか・承認待ちかを把握できなくなる。これを解消するため、Claude Code をアプリ内で起動・管理する macOS ネイティブダッシュボードを構築する。

### 要件

- 対象 OS: macOS 14+
- 言語/フレームワーク: Swift / SwiftUI
- 管理対象: 本アプリから spawn した Claude Code セッションのみ（既存セッションへのアタッチは対象外）
- MVP: 1 セッションをアプリ内ターミナルで起動し、SwiftTerm で表示、状態（実行中/完了/承認待ち/エラー）をバッジ表示
- 将来拡張: 複数セッション管理、Menu Bar Extra、承認操作のリレー

## 2. 決定事項

### 2.1 アーキテクチャパターン: MVVM (@Observable) + Domain 境界分離

ロジックを ViewModel に集約し、`AgentDomain` モジュールに Pure Swift の Value Type を分離する。

採用しなかった案:

- **MV**: PTY/Hook の非同期ストリーム処理が View に滲み出る
- **TCA**: SwiftTerm が AppKit View に直接バッファ書き込みするため、Effect で包む純粋 Reducer モデルに乗らない。PTY 出力の高頻度イベントを Action 化するオーバーヘッドも見合わない
- **Clean Architecture (完全版)**: MVP 規模に対して層が多すぎる

### 2.2 SPM マルチモジュール構成

```
agent-dashboard/
├─ App/                         @main, Composition Root
└─ Packages/
   ├─ AgentDomain               Pure Swift (Foundation のみ)
   ├─ PTYKit                    PTY マネージャ actor
   ├─ HookServer                localhost HTTP サーバー actor
   ├─ TerminalUI                SwiftTerm の NSViewRepresentable ラッパー
   ├─ DesignSystem              共通 UI コンポーネント
   └─ DashboardFeature          画面・ViewModel
```

依存方向:

```
App → DashboardFeature → AgentDomain
                       → PTYKit → AgentDomain
                       → HookServer → AgentDomain
                       → TerminalUI
                       → DesignSystem
```

### 2.3 依存性注入: コンストラクタ注入 + @Environment ハイブリッド

| 対象 | 方式 |
|---|---|
| `PTYManagerProtocol` / `HookServerProtocol` | `@Environment` 注入 |
| `DashboardViewModel` / `SessionViewModel` | コンストラクタ注入 |
| `AppConfig` (ポート番号など) | `@Environment` 注入 |

`swift-dependencies` は TCA を採らないため不採用。

### 2.4 ナビゲーション: NavigationSplitView 駆動

将来の複数セッション対応を見越し、MVP から `NavigationSplitView` 構造を採用する。
専用 Coordinator は階層が浅い（最大 2 階層）ため導入しない。`AppRouter` を `@Observable` 1 つに集約し `@Environment` 注入する。

### 2.5 状態管理: MVP は in-memory + UserDefaults

| データ | 永続化 |
|---|---|
| 実行中セッション | in-memory |
| 出力バッファ | in-memory (SwiftTerm 内部) |
| Hook イベント履歴 | in-memory (リングバッファ) |
| アプリ設定 | UserDefaults |
| 過去セッション履歴 | **未実装**（将来 SwiftData 検討） |

SwiftData の中途半端な導入はスキーマ migration の負担を生むため、MVP では採用しない。

### 2.6 Actor 分離設計

```
PTYManager (actor) ──→ TerminalView (SwiftTerm 直接 feed)
                  └──→ AsyncStream<TerminalOutput>

HookServer (actor) ──→ AsyncStream<HookEvent> ──→ SessionViewModel (@MainActor)
                                                       │
                                                       ↓
                                                  SessionView
```

重要判断:

- **PTY 出力は ViewModel を経由せず、SwiftTerm に直接 feed する**。秒間数百行の出力で `@MainActor` を経由するとフレーム落ちするため
- ViewModel は **Hook イベントのみ** で状態（実行中/完了/承認待ち/エラー）を判定する
- 承認待ち検出は `Notification` フックを一次情報源とする
- 補足（更新 2026-06-08, `StatusReducer`）: `Notification` は承認パターン該当時のみ承認待ちとし、**非該当の通知は現在の状態を維持する**（完了後に届く「入力待ち」等の通知で `running` に固着しないため）。加えて Claude Code のプラン承認は `PreToolUse(toolName: "ExitPlanMode")` を承認待ちのトリガーとして扱う。

### 2.7 テスタビリティ境界

| レイヤ | テスト方法 |
|---|---|
| `AgentDomain` の状態遷移関数 | Pure Swift 単体テスト |
| `SessionViewModel` | Mock の `PTYManagerProtocol` / `HookServerProtocol` を注入し、`AsyncStream.makeStream` でイベント注入 |
| `PTYManager` | 結合テスト（`/bin/echo` 等で実 spawn） |
| `HookServer` | 結合テスト（`URLSession` で実 POST） |
| `TerminalView` (SwiftTerm) | テスト対象外（最低限のスナップショット） |

## 3. 結果

- View にロジックが滲まず、ViewModel が単体テスト可能
- PTY と Hook サーバーが Actor で分離され、スレッド安全
- SPM モジュールにより並列ビルドが効き、依存方向が import で強制される
- MVP では SwiftData を入れないため、初期実装の負担が軽い

## 4. リスクと制約

- **既存ターミナルの Claude Code はアタッチ不可**: 本アプリから起動したセッションのみが対象
- **承認待ち検出は 100% 保証されない**: Claude Code の `Notification` フックがすべての承認シナリオを発火するとは限らない。フォールバックとして PTY 出力パターン照合を将来検討
- **SwiftTerm への依存**: OSS（migueldeicaza/SwiftTerm）が事実上唯一の選択肢

## 5. 一次資料

- WWDC20 Session 10040 "Data Essentials in SwiftUI"
- WWDC22 Session 110359 "Demystify parallelization in Xcode builds"
- WWDC23 Session 10160 "Demystify SwiftUI"
- SwiftTerm: https://github.com/migueldeicaza/SwiftTerm
- Claude Code Hooks: https://docs.claude.com/en/docs/claude-code/hooks
