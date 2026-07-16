---
status: active
last-verified: 2026-07-09
---

# Phlox E2E テスト設計書

- 作成日: 2026-06-11
- ステータス: Layer A 実装完了（WP-E1〜E4 完了、2026-06-11 マージ済み。`E2EFakeAgentSmokeTests` / `E2ESessionLifecycleTests` / `E2EControlServerTests` / `E2EPersistenceTests` が green。件数は腐敗しやすいため明記せず、実行コマンド（§5.1）で都度確認する）。Layer B（WP-E5〜E7）と S10 の codex スモークは未実施
- 対象: Phlox macOS アプリの主要シナリオ E2E テスト

## 1. 目的とスコープ

### 1.1 目的
主要ユーザーシナリオが「実際に通る」ことを自動で検証し、リファクタリング・機能追加時の回帰を検出する。既存のユニット/結合テスト（60+ ファイル、約11,000行）がカバーしない「コンポーネント結合部〜GUI」の欠陥を対象とする。

### 1.2 スコープ外
- 実 codex / claude / cursor CLI の品質（外部製品）。実CLIを使うテストは少数のオプトイン実行に限定する
- 性能・負荷（`swift-performance-optimization` の領域）
- アクセシビリティ監査（別途 `performAccessibilityAudit` で実施可能）

## 2. テスト戦略: 2層構成

テストピラミッドに従い、E2E を2層に分けて「GUI を通す本当の E2E」を最小限に絞る。

| 層 | 名称 | 基盤 | 起動対象 | 実行時間目標 | 本数目安 |
|---|---|---|---|---|---|
| **Layer A** | ヘッドレス E2E | `swift test`（Swift Testing、`PHLOX_E2E=1` ゲート） | 実 PTYManager + 実 HookServer/ControlServer + フェイクエージェントCLI。GUI なし | 1本 < 10秒 | 10〜15本 |
| **Layer B** | GUI E2E | XCUITest（新規 `PhloxUITests` ターゲット） | アプリ本体（Debug ビルド）を実起動 | 1本 < 60秒 | 4〜6本 |

**割当の原則**: 「状態遷移・永続化・サーバAPI・PTY 入出力」は Layer A で検証する。Layer B は「GUI の配線（画面に出る・押せる・遷移する）」だけを検証し、ロジックの正しさは Layer A に委ねる。同じアサーションを両層に重複して置かない。

### 2.1 既存資産との関係
- 既存の `RealPTYIntegrationTests`（`PHLOX_E2E=1` ゲート、`Packages/DashboardFeature/Tests/DashboardFeatureTests/RealPTYIntegrationTests.swift`）は Layer A の先行事例。本設計はこれを拡張する形をとる
- ユニットテスト（Mock 注入）で既に検証済みの分岐（レート制限の境界値、パーサ等）は E2E で再検証しない。E2E は各シナリオ1ハッピーパス＋代表的異常系1つまで

## 3. 前提改修（テスタビリティ向上）

E2E 実装前に必要な改修。**特に Layer B はこの改修なしでは本番データを破壊するため着手禁止**。

### T1. データディレクトリの差し替え（必須・Layer B 前提）
- 現状: `App/CompositionRoot.swift:243-266` が `~/Library/Application Support/Phlox` 固定
- 改修: 環境変数 `PHLOX_DATA_DIR`（または launch argument `-PhloxDataDir <path>`）が設定されていればそれを使う。`phloxAppSupportURL()` の1箇所変更で済む想定
- 効果: E2E は一時ディレクトリで完結し、本番 `sessions.json` / `ports.json` / SQLite を汚さない

### T2. UserDefaults suite の差し替え（必須・Layer B 前提）
- 現状: `BypassSettings` 等が `UserDefaults.standard` 直接参照（`Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift:18-33`）。さらに `@AppStorage(ThemeStore.themeKey)` が DesignSystem 4箇所 + DashboardFeature の View に10箇所以上散在しており、全面差し替えは規模が大きい
- 改修方針: **動作に影響する設定（Bypass・通知・Usage）のみ** `PHLOX_DEFAULTS_SUITE` 指定時に `UserDefaults(suiteName:)` へ切り替える。テーマ・言語等の表示系 `@AppStorage` は差し替え対象外とし、E2E は表示系設定を変更した場合にテスト終了時へ元値復元する運用で汚染を許容範囲に抑える（S8 はこの前提で設計）
- 効果: 設定系シナリオ（S9〜S10）が本番の動作系 Preferences を汚さず、テスト間で独立する

### T3. フェイクエージェント CLI（必須・両層共通）
- 実 codex/claude は遅く・課金され・出力が非決定的なので、E2E の既定は**フェイクCLI**で駆動する
- 仕様（`Packages/DashboardFeature/Tests/DashboardFeatureTests/Fixtures/fake-agent.sh` として新規作成）:
  - 起動時にプロンプト文字列 `FAKE_AGENT_READY>` を出力
  - stdin 1行受信ごとに `ECHO: <入力>` を出力
  - 環境変数 `FAKE_AGENT_HOOK_URL` / `PHLOX_SESSION_ID` が**両方設定されている場合のみ**、起動時に `sessionStart`、各行処理後に `stop` の JSON を hook URL へ POST する（未設定なら一切 POST しない = idle-fallback 動作）
  - 引数 `--exit-after <n>` で n 行処理後に自プロセス終了（プロセス死亡系の検証用）
- **注入経路は層で異なる（重要）**:
  - **Layer A**: テストが `SessionViewModel.SpawnRequest`（command/args/env）を直接組み立てるため、registry を使わない。フック検証が必要なテストはテスト側で実 `HookServer` を起動し、その URL を `FAKE_AGENT_HOOK_URL` として env に注入する（既存 `realPTY_deterministic_*` の発展形）
  - **Layer B**: カスタムエージェントは `hookKind: .none` で生成され（`CustomAgentDefinition.swift:99`）、`AgentLaunchPlanner.swift:131` は `CLAUDE_HOOKS_URL` を注入しないため、**フェイクCLI は idle-fallback 前提**とする。フック駆動の状態遷移は Layer B では検証しない（Layer A の責務）。また registry のパスは `~/.config/phlox/agents.json` 固定（`CustomAgentDefinition.swift:6-8`、`PHLOX_DATA_DIR` に連動しない）のため、`PHLOX_AGENTS_JSON` での上書き改修を T1 と同時に行う（WP-E5 に含める）
- 実 CLI を使うテストは既存方針どおり「PATH に存在しなければ自動スキップ」（`realGoose_*` と同形式）
- フェイクCLI 自体の正しさは WP-E1 の最初に「直接 spawn して ready 出力とエコーを確認するスモーク1本」で保証する
- **トレードオフ**: フェイクCLI では実 CLI のプロトコル変更（起動引数・出力形式の変化）を検出できない。この乖離リスクは S10（実CLIスモーク、オプトイン）で補う

### T4. accessibilityIdentifier の付与（必須・Layer B 前提）
- 現状: `.accessibilityIdentifier` はゼロ（`.accessibilityLabel` が DesignSystem に3箇所のみ）
- 改修: Layer B のシナリオが触る要素に限定して付与する（全画面網羅はしない）:

| identifier | 要素 | ファイル |
|---|---|---|
| `dashboard.sidebar` | サイドバー | DashboardSidebarView.swift |
| `sidebar.session.<name>` | セッション行 | サイドバーのセッション一覧 |
| `session.newButton` | 新規セッションボタン | DashboardTopBarControls.swift / トップバー |
| `session.inputField` | メッセージ入力欄 | SessionView |
| `session.sendButton` | 送信ボタン | SessionView |
| `session.terminal` | ターミナル表示領域 | SessionView (TerminalUI ホスト) |
| `dashboard.viewModeToggle` | single/grid 切替 | ツールバー |
| `session.grid` | グリッドコンテナ | SessionGridView.swift |
| `settings.bypass.<kind>` | Bypass トグル | SettingsView.swift / BypassToggleRow |
| `settings.theme` | テーマ Picker | SettingsView.swift |

### T5. XcodeGen テストターゲット追加（Layer B 前提）
- `project.yml` に `PhloxUITests`（type: bundle.ui-testing, target: Phlox）を追加し、scheme の Test アクションに登録
- UI テスト側から T1/T2 を `XCUIApplication().launchEnvironment` で注入する

### T6. ターミナル出力のテスト用読み出し口（Layer B で必要になった時点で）
- SwiftTerm の描画内容は XCUITest のアクセシビリティツリーから読めない可能性が高い
- 対策（優先順）: ① ControlServer の `read` API（`phlox read`）を XCUITest 内から HTTP で叩いて画面内容を取得する（アプリ改修不要） ② それで不足なら `session.terminal` に表示テキストの accessibilityValue を載せる
- 設計判断: まず①で実装し、②は必要が実証されてから行う

## 4. 主要シナリオカタログ

優先度: P0 = クリティカルパス（壊れたら製品が成立しない）/ P1 = 主要機能 / P2 = あれば良い。

### S1. セッション生成 → ready 検知 → メッセージ送受信（P0、Layer A + B）

製品のコア。Layer A で状態機械、Layer B で GUI 配線を検証。

**Layer A**（`PHLOX_E2E=1`、フェイクCLI）
- Given: 一時作業ディレクトリ、テスト内で実 `HookServer` を起動し、その URL を `FAKE_AGENT_HOOK_URL` としてフェイクCLI の env に注入した `SessionViewModel`
- When: `start()` → ready 待ち → 入力送信（`sendInput`）
- Then:
  1. SessionStatus が `.idle` へ遷移する（sessionStart フック経由。`SessionStatus` の実列挙子は `.starting/.idle/.running/.awaitingApproval/.completed/.error`）
  2. PTY 出力（TerminalCoordinator 経由）に `ECHO: hello` が現れる
  3. stop フック受信で完了検知（`.idle` + `hasUnseenCompletion`）になる
- 異常系 A-1b: フック env なしのフェイクCLI で idle fallback により ready 検知できる（既存 `realPTY_deterministic_*` の発展）
- 異常系 A-1c: `--exit-after 0`（即死 CLI）でセッションがエラー/終了状態になり、テストプロセス全体は無事

**Layer B**（XCUITest）
- Given: `PHLOX_DATA_DIR`=一時dir、フェイクCLI registry 配置済み、アプリ起動
- When: `session.newButton` をクリック → `session.inputField` に "hello" を入力 → `session.sendButton`
- Then: サイドバーに新セッション行が現れ、`phlox read`（T6①）の取得結果に `ECHO: hello` が含まれる

### S2. アプリ再起動でセッション・UI 状態を復元（P0、Layer A + B）

- **Layer A**: ViewModel/Store を生成→セッション2本 spawn→破棄→同じデータディレクトリで再生成。Then: セッション一覧・選択状態・メッセージログ（SQLite）が復元される
- **Layer B**: アプリ起動→セッション作成→`app.terminate()`→同じ `PHLOX_DATA_DIR` で再 `launch()`。Then: サイドバーに同名セッション行が表示される
- 異常系 A-2b: `sessions.json` が壊れている（不正JSON）場合に起動が失敗せず空状態で立ち上がる

### S3. セッション削除と子プロセス終了（P0、Layer A）

- Given: フェイクCLI セッション1本が稼働中（PID 取得済み）
- When: `removeSession()`
- Then: ① セッションが一覧から消える ② フェイクCLI プロセスが終了している（`kill -0` で確認） ③ `sessions.json` から消えている
- Layer B では実施しない（GUI 上の削除メニューは S1 の配線確認で十分代表される）

### S4. 外部 CLI（`scripts/phlox`）からの send / read / list（P0、Layer A）

エージェント間オーケストレーションの生命線。

- Given: ControlServer 起動済み（動的ポート）、フェイクCLI セッション "alpha" 稼働中、`PHLOX_API_URL`/`PHLOX_TOKEN`/`PHLOX_SESSION_ID` の3変数を子プロセス環境に設定（`scripts/phlox` の `require_env` は3つすべて必須）
- When/Then:
  1. `phlox list` → "alpha" が含まれる JSON が返る
  2. `phlox send --to alpha -- "ping"` → PTY 出力に `ECHO: ping`
  3. `phlox read --to alpha` → `ECHO: ping` を含む画面内容が返る
  4. `phlox wait --to alpha --timeout 10` → stop フックで復帰する
- 異常系 A-4b: 不正トークンで 401、存在しないセッション名でエラー終了コード

### S5. API spawn（セッション内からの子セッション生成）と親子カスケード終了（P0、Layer A）

- Given: 親セッション稼働中
- When: ControlServer `POST /sessions`（`phlox spawn --kind <fake>` 相当）
- Then: ① 子セッションが生成され親IDが記録される ② `wait-ready` が成功する ③ 親を削除すると**子孫セッションがすべてカスケード終了・削除される**（実装仕様: `DashboardViewModel.removeSession` が subtree を深い順に再帰 terminate＋一覧/永続化から除去する。ADR 0013 参照。reparent は廃止）
- 制限系（深さ・レート）は既存 `SpawnLimitTests`（ユニット）に委ねる。総数上限は撤廃済み（ADR 0058）のため、上限到達のエラー応答を検証する E2E は無い

### S6. プロジェクト（ワークスペース）管理（P1、Layer A）

- Given: 一時ディレクトリ2つをプロジェクトとして追加
- When: `addProject()` → プロジェクト指定 spawn → `moveSession()` → 再起動（S2 と同手順）
- Then: セッションがプロジェクト配下に配置され、再起動後も配置が保持される
- Layer B では実施しない（NSOpenPanel の自動操作は脆く、価値が低い）

### S7. グリッド表示切替と複数セッション（P1、Layer B）

- Given: フェイクCLI セッション3本作成済み
- When: `dashboard.viewModeToggle` をクリック
- Then: `session.grid` が存在し、グリッド内にセッション3本分のセルが表示される。再度トグルで single に戻る
- グリッド列数計算・並べ替えロジックはユニットテストに委ねる

### S8. 設定: テーマ変更の反映（P1、Layer B）

- Given: アプリ起動、Settings ウィンドウを開く（Cmd+,）
- When: `settings.theme` で別テーマを選択
- Then: ① suite（T2）に保存される ② アプリを再起動しても選択が保持される
- 「ターミナル配色が実際に変わった」のピクセル検証はしない（スナップショットテストの領域とし、本設計のスコープ外）

### S9. 設定: Bypass 権限の次セッション反映(P1、Layer A + B)

- **Layer B**: `settings.bypass.claudeCode` をトグル → suite に保存されることを確認
- **Layer A**: BypassSettings ON/OFF それぞれで spawn し、生成される hooks 設定ファイル（hooks.json / restricted）が切り替わることを確認
- 「現行セッションには反映されない」仕様は Layer A で検証

### S10. 実 CLI スモーク（P2、Layer A、オプトイン）

- 既存 `realGoose_*` 方式の踏襲: 実 claude / codex が PATH にあるときだけ、spawn → ready → 1メッセージ → stop 検知を1本ずつ
- CI 既定では走らせない（ローカル・リリース前の手動実行用）

### シナリオ × 層 マトリクス

| # | シナリオ | P | Layer A | Layer B |
|---|---|---|---|---|
| S1 | spawn→ready→send→echo | P0 | ✅ 3本（正常+no-hooks+即死） | ✅ 1本 |
| S2 | 再起動復元 | P0 | ✅ 2本（正常+破損JSON） | ✅ 1本 |
| S3 | 削除とプロセス終了 | P0 | ✅ 1本 | — |
| S4 | 外部 phlox CLI | P0 | ✅ 2本（正常+認証異常） | — |
| S5 | API spawn と親子 | P0 | ✅ 2本 | — |
| S6 | プロジェクト管理 | P1 | ✅ 1本 | — |
| S7 | グリッド切替 | P1 | — | ✅ 1本 |
| S8 | テーマ設定 | P1 | — | ✅ 1本 |
| S9 | Bypass 設定 | P1 | ✅ 1本 | ✅ 1本 |
| S10 | 実CLIスモーク | P2 | ✅ 2本（オプトイン） | — |
| 計 | | | 14本 | 5本 |

## 5. 実行環境・運用設計

### 5.1 実行コマンド

```bash
# Layer A（ローカル・CI 共通。フェイクCLIのみで完結）
# スイート命名規約: スイート表示名は @Suite("E2E <領域>")、構造体型名も E2E プレフィックス
# （--filter は表示名ではなく型名・関数名にマッチするため）
# --no-parallel 必須: 実 PTY の settle 窓(400ms)がテスト並列実行の CPU 競合で
# 破られ flaky になるため、E2E は直列で実行する
PHLOX_E2E=1 swift test --package-path Packages/DashboardFeature --filter E2E --no-parallel

# Layer B（要ビルド。CLAUDE.md の規約どおり頻度を絞る）
xcodebuild -project Phlox.xcodeproj -scheme Phlox \
  -configuration Debug -derivedDataPath /tmp/PhloxBuild \
  test -only-testing:PhloxUITests
```

### 5.2 隔離と安全（CLAUDE.md の制約への対応）

| 制約 | 対応 |
|---|---|
| ポート競合 | ポートは `preferredPort: 0` で動的割当（CompositionRoot.swift:29,66。CLAUDE.md の「57398/57399 固定」記述はコード実態より古い）。データdir 分離により `ports.json` も分離されるため本番との並走が**理論上**可能。ただし実機で並走無害を確認できるまでは、**Layer B 実行前に既存インスタンスを終了する暫定ルールを維持**する（確認は WP-E5 の完了条件に含める） |
| 本番データ汚染 | T1/T2 で一時ディレクトリ・専用 suite に完全分離。テスト終了時に削除 |
| リリース版破壊 | Layer B は `/tmp/PhloxBuild` の Debug 版のみ起動。`/Applications/Phlox.app` に触れない |

### 5.3 Flaky 対策（設計ルール）

1. **sleep 禁止**: 待機はすべて「フック受信イベント」「`waitForExistence(timeout:)`」「`phlox wait --sentinel`」のいずれかで行う
2. **タイムアウト統一**: Layer A = 10秒、Layer B = 30秒を既定とし、定数で一元管理
3. **テスト間独立**: 1テスト = 1一時データディレクトリ。共有状態なし。Layer A の Suite は `.serialized` 不要な設計を保つ（ポート動的割当のため並列可）
4. **フェイクCLI の決定性**: 出力は固定文字列のみ。時刻・乱数を含めない
5. **quarantine 運用**: flaky 化したテストは `.disabled("理由", .bug("issue"))` で即隔離し Issue 化

### 5.4 CI への組み込み

- PR ごと: 既存ユニット + Layer A（フェイクCLI のみなので外部依存ゼロ）
- main マージ後 or 日次: Layer B（ビルドが重いため）
- S10（実CLI）は CI 対象外

## 6. 実装フェーズ分割

| WP | 内容 | 依存 | 規模感 |
|---|---|---|---|
| WP-E1 | T3 フェイクエージェント CLI + Layer A 基盤（一時dir fixture、E2E用ヘルパ） | なし | 小 |
| WP-E2 | Layer A: S1, S3（セッションライフサイクル） | WP-E1 | 中 |
| WP-E3 | Layer A: S4, S5（ControlServer / phlox CLI / API spawn） | WP-E1 | 中 |
| WP-E4 | Layer A: S2, S6, S9-A（永続化・復元・設定） | WP-E1 | 中 |
| WP-E5 | T1, T2（データdir・UserDefaults 差し替え）+ 回帰確認 | なし | 小 |
| WP-E6 | T4, T5（identifier 付与・PhloxUITests ターゲット）+ Layer B: S1, S2 | WP-E5 | 中 |
| WP-E7 | Layer B: S7, S8, S9-B + CI 組み込み | WP-E6 | 中 |
| WP-E8 | S10 実CLIスモーク（オプトイン） | WP-E2 | 小 |

WP-E1〜E4（Layer A）はアプリ本体の改修がほぼ不要で先行着手できる。WP-E5〜E7（Layer B）は本体改修を含むため、実装前に Codex レビューを挟む。

## 7. リスクと未確定事項

1. **SwiftTerm 領域の検証手段**（T6）: `phlox read` 経由で足りるかは実装時に検証が必要。不足時は accessibilityValue 追加（本体改修）に発展する
2. **XCUITest の権限**: 実行マシンに Automation 権限付与が必要。CI ランナー（セルフホスト想定）での事前設定手順を WP-E7 で文書化する
3. **（解決済み・T3 に反映）** Layer A は SpawnRequest 直接組み立てで registry 不要。Layer B はカスタムエージェントの `hookKind: .none` 制約により idle-fallback 前提とし、registry パス上書き（`PHLOX_AGENTS_JSON`）を WP-E5 で改修する
4. **ports.json の共有**: 本番とテストでデータdir を分けることで ports.json も分離されるが、`scripts/phlox` が参照する API URL の解決経路をテスト側で正しく注入できるか WP-E3 で確認する
