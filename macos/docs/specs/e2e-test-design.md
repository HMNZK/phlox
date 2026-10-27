---
status: active
last-verified: 2026-10-12
---

# Phlox E2E テスト設計書

- 作成日: 2026-06-11
- ステータス: Layer A の実装資産あり。2026-10-25にdev `90a0c801`のテスト定義を静的確認したが、今回の実行成功は未確認。過去のgreenは現在の候補の合格を意味しない。Layer Bは旧XCUITest計画であり、実行禁止。S10の実CLIスモークは必須fake集合に含めない
- 対象: Phlox macOS アプリの主要シナリオ E2E テスト

統合前の必須検査・実機記録・シナリオ変更レビューの正本は [merge-verification-gates.md](merge-verification-gates.md)。同書の開始OIDで13関数を必須fake集合とし、外部CLI不要の`E2ERealPTYTests.realPTY_deterministic_inputEchoThenSilenceReachesIdleCompletion`を含む。以下のシナリオは受入意図を示す設計で、実行済みの証拠ではない。XCUITestは入力ソースを追加し得るため使わず、画面の確認は単体描画・AX/イベント操作・実機観測を区別する。

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
| **Layer B（旧計画）** | GUI E2E | XCUITest（実行禁止、導入計画は現行運用外） | 旧アプリ操作案 | — | — |

**割当の原則**: 「状態遷移・永続化・サーバAPI・PTY 入出力」は Layer A で検証する。Layer B は「GUI の配線（画面に出る・押せる・遷移する）」だけを検証し、ロジックの正しさは Layer A に委ねる。同じアサーションを両層に重複して置かない。

### 2.1 既存資産との関係
- 既存の `RealPTYIntegrationTests`（`PHLOX_E2E=1` ゲート、`Packages/DashboardFeature/Tests/DashboardFeatureTests/RealPTYIntegrationTests.swift`）は Layer A の先行事例。本設計はこれを拡張する形をとる
- ユニットテスト（Mock 注入）で既に検証済みの分岐（レート制限の境界値、パーサ等）は E2E で再検証しない。E2E は各シナリオ1ハッピーパス＋代表的異常系1つまで

## 3. 旧Layer Bの前提改修（履歴）

以下は策定時の改修案・調査記録で、現在の実装状況や実行指示ではない。Layer BのXCUITest案は実行しない。現在の分離方法は [Release/Debug併存ガイド](../guides/running-release-and-debug-together.md)、現行の必須集合・入口は [統合前検証契約](merge-verification-gates.md)を参照する。

### T1. データディレクトリの差し替え（必須・Layer B 前提）
- 策定当時の記述（現行状況の主張ではない）: `App/CompositionRoot.swift:243-266` が `~/Library/Application Support/Phlox` 固定
- 改修: 環境変数 `PHLOX_DATA_DIR`（または launch argument `-PhloxDataDir <path>`）が設定されていればそれを使う。`phloxAppSupportURL()` の1箇所変更で済む想定
- 効果: E2E は一時ディレクトリで完結し、本番 `sessions.json` / `ports.json` / SQLite を汚さない

### T2. UserDefaults suite の差し替え（必須・Layer B 前提）
- 策定当時の記述（現行状況の主張ではない）: `BypassSettings` 等が `UserDefaults.standard` 直接参照（`Packages/DashboardFeature/Sources/DashboardFeature/Environment/BypassSettings.swift:18-33`）。さらに `@AppStorage(ThemeStore.themeKey)` が DesignSystem 4箇所 + DashboardFeature の View に10箇所以上散在しており、全面差し替えは規模が大きい
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
  - **Layer B**: 組込みハーネス（Claude Code）の実行ファイルの場所を、環境変数 `PHLOX_TEST_AGENT_BINARY_PATHS`（JSON。例 `{"claudeCode":"/path/to/fake-agent.sh"}`。`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` のときだけ有効。読む側は `AppBootstrap/BinaryPathResolver.swift` の `testBinaryOverrides`、設定する側は `UITests/IsolatedPhloxApplication.swift`）でフェイクCLI に差し替える。カスタムエージェント（`agents.json`・`PHLOX_AGENTS_JSON`）は 2026-10-12 に廃止された（ADR 0185）ので使わない。組込みの Claude Code には `AgentLaunchPlanner` が `CLAUDE_HOOKS_URL` を注入する（`Spawn/AgentLaunchPlanner.swift`）。フェイクCLI の出力と、組込みハーネスの会話の読み取り方との整合は、Layer B の実装時に確かめる（未検証）
- 実CLI依存のopt-inテストは必須fake集合とは別扱い。未実行/skipを実行成功として数えない
- フェイクCLI 自体の正しさは WP-E1 の最初に「直接 spawn して ready 出力とエコーを確認するスモーク1本」で保証する
- **トレードオフ**: フェイクCLI では実 CLI のプロトコル変更（起動引数・出力形式の変化）を検出できない。この乖離リスクは S10（実CLIスモーク、オプトイン）で補う

### T4. accessibilityIdentifier の付与（必須・Layer B 前提）
- 策定時（2026-07）の記述: `.accessibilityIdentifier` はゼロ（`.accessibilityLabel` が DesignSystem に3箇所のみ）。次の2026-10-12の調査はその後の状態であり、現在の全数確認ではない
- 2026-10-12 時点でコードに実在するのは次の表の `tabs.item.add`・`newChat.composer`・`newChat.sendButton` だけ（ほかは付与の予定。タブ列には `tabs.project.<n>`・`tabs.project.add`・`tabs.item.<n>`・`tabs.overflow` もある）:
- 改修: Layer B のシナリオが触る要素に限定して付与する（全画面網羅はしない）:

| identifier | 要素 | ファイル |
|---|---|---|
| `dashboard.sidebar` | サイドバー | DashboardSidebarView.swift |
| `sidebar.session.<name>` | セッション行 | サイドバーのセッション一覧 |
| `tabs.item.add` | 下段の「＋」（タブを追加）。開くメニューの先頭が「新規チャット」（⌘N でも開く）。新規チャット画面は下段の「新規チャット」タブ | Tabs/SessionTabsContainer.swift（`ChildTabBar`） |
| `newChat.composer` / `newChat.sendButton` | 新規チャット画面のメッセージ入力欄・送信ボタン | NewChat/NewChatView.swift |
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

**Layer B**（旧XCUITest操作案、実行禁止）
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

- 実claude/codex等のプロトコル互換性を別途明示確認する。PATHや認証が必要な実CLI依存検査は、外部依存不要の必須fake集合と分ける
- CI 既定では走らせない（ローカル・リリース前の手動実行用）

### シナリオ × 層 マトリクス（受入意図）

各欄は対象とする検証で、合格実績ではない。旧Layer Bの操作意図を残すが、XCUITestは起動しない。実際に検査する関数・判定範囲は必須集合とコードで照合する。

| # | シナリオ | P | Layer A | 旧Layer B案 |
|---|---|---|---|---|
| S1 | spawn→ready→send→echo | P0 | fake・決定論的PTY | 生成・送受信 |
| S2 | 再起動復元 | P0 | Store/ViewModelの復元 | アプリ再起動 |
| S3 | 削除とプロセス終了 | P0 | プロセス終了 | — |
| S4 | 外部 phlox CLI | P0 | list/send/read・認証異常 | — |
| S5 | API spawn と親子 | P0 | 親子生成・終了 | — |
| S6 | プロジェクト管理 | P1 | 永続化・配置 | — |
| S7 | グリッド切替 | P1 | — | 表示切替 |
| S8 | テーマ設定 | P1 | — | 設定保存 |
| S9 | Bypass 設定 | P1 | 設定選択 | トグル操作 |
| S10 | 実CLIスモーク | P2 | opt-in（必須fake集合の外） | — |

## 5. 実行環境・運用設計

### 5.1 実行入口

dev/verify/mainへの反映前に`macos/scripts/verification-gate.py quality`から、文書保守後の同じ候補でmacOS全19パッケージを既存標準入口へ明示して検査し、iOS lint/単体/build、指定した13関数のfake E2Eも実行する。新パッケージの検査漏れと親環境による対象/並行性の変更も検出する。入口は [統合前検証契約](merge-verification-gates.md)で合意した接続先であり、本書により実装済み・実行成功とは主張しない。CLI引数とJSONの正本は実装コードとし、同書の監査基準OIDとは区別する。

fake E2Eは関数IDを明示して`--no-parallel`で実行し、`PHLOX_E2E=1`はその子プロセスだけに渡す。広い`--filter E2E`や通常検査全体への一括exportは実CLI依存テストまで選び得るため使わない。テストは`~/.agents/scripts/compact-test`、ビルドを伴う検査は`managed-build`に従う。exit 0だけでなく必須IDごとの実行・成功を確認し、0件・必須skip・検査不能は非0とする。

通常検査の既存opt-in skipは未実行として別記する。known issueは`GitHistoryWorkflowTests.GTWRegression_改名前の名前を再利用しても利用順を混同しない`のADR 0209だけを未解決として別記でき、成功件数に含めない。未知のknown issueと、fake必須13関数のknown issue/skipは非0。個別ID・生ログ・結果JSONは共通マージ時に`$GITFLOW_VERIFICATION_DIR`のcandidate外へ保存し、外側のログ要約やcandidate削除で失わない。

シナリオ鮮度はビルド入力と、対象AC行・操作・期待結果の内容を別々に照合する。対応表の独立レビューには明示`decision`を保存し、対象差分の最新`pass`だけを受理する。実機の初期対応表にはiOS統一のAC-8（Usage設定/60秒更新）・AC-9（worktree/起点/Claude-Codex再開）も含める。qualityのテストコマンド成功と、その後のイベント解析を含むゲート全体の成功は別であり、現在の未解決事項は[統合前検証契約](merge-verification-gates.md)を参照する。

### 5.2 隔離と安全（CLAUDE.md の制約への対応）

| 制約 | 対応 |
|---|---|
| ポート競合 | テストのサーバーは動的割当。手動アプリの併存は [ガイド](../guides/running-release-and-debug-together.md)に従い、通常Releaseや他作業のDebugを終了させない |
| 本番データ汚染 | 専用データ・設定・出力先へ分離。作業が作成したことを確認できる不要物だけ片付ける |
| 検証成果物 | worktreeの`.verification/<作業名>/`にまとめ、所有・PIDを記録する。既存キャッシュや他作業の成果物を削除しない |

### 5.3 Flaky 対策（設計ルール）

1. **条件で待つ**: フック・状態・出力の成立を期限付きで確認する。固定待ちだけを合格の根拠にしない
2. **タイムアウト**: テストにある有限の期限を維持し、期限切れは失敗として残す
3. **テスト間独立**: 一意のデータ・ポートを使い、必須fake集合はCPU競合を避けて直列実行する
4. **フェイクCLI の決定性**: 出力は固定文字列のみ。時刻・乱数を含めない
5. **失敗を隠さない**: flakyでもskip/disabledや期待値緩和で通さず、根本原因を確認する。解決できない場合は理由を報告して判断を戻す

### 5.4 CI への組み込み

- dev/verify/main反映前: 既存品質入口に接続した必須自動検査を実行する。mainは実機記録の照合も必要
- S10（実CLI）・人操作/ACK待ちは自動ゲートから一括起動せず、必要に応じて別途明示実行する
- XCUITestは実行しない。ローカルゲートを設けても、サーバー側の必須チェックや保護が設定済みとは扱わない

## 6. 旧実装フェーズ分割（履歴）

以下は策定当時の計画。特にWP-E5〜E7のXCUITest導入・実行案は現行運用外で、実装指示ではない。

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

現在の品質・実機記録の変更は [統合前検証契約](merge-verification-gates.md)に従う。

## 7. リスクと未確定事項

1. **SwiftTerm 領域の検証手段**（T6）: `phlox read` 経由で足りるかは実装時に検証が必要。不足時は accessibilityValue 追加（本体改修）に発展する
2. **画面確認の不足**: XCUITestは実行禁止。単体描画、AX/イベント操作、実機の操作・観測は検証範囲が異なり、互いの成功を代用しない
3. **（解決済み・T3 に反映）** Layer A は SpawnRequest 直接組み立てで registry 不要。Layer B は `PHLOX_TEST_AGENT_BINARY_PATHS` で組込みハーネスの実行ファイルを差し替える（カスタムエージェントは廃止。ADR 0185）
4. **ports.json の共有**: 本番とテストでデータdir を分けることで ports.json も分離されるが、`scripts/phlox` が参照する API URL の解決経路をテスト側で正しく注入できるか WP-E3 で確認する
