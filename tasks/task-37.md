---
id: task-37
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/AgentConfigKit/Tests/AgentConfigKitTests/Acceptance/AcceptanceAgentConsoleStatusSummaryTests.swift
baseline_commit: TBD
contract_tests: []
allowed_paths:
  - macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleStatusSummary.swift
  - macos/App/AgentConsole/Claude/ClaudeStatusPane.swift
  - macos/App/AgentConsole/Codex/CodexStatusPane.swift
  - macos/App/AgentConsole/Cursor/CursorStatusPane.swift
---

## 目的

UX-12 のうち、状態ペインの要約と CLI 詳細。状態ペインでは CLI の検出状況と設定ファイルの有無を先に見せる。
バージョン・実行ファイルパスは初回表示で折りたたみ、必要時に確認できるようにする。
既存の集計・設定・メモリ・Finder 操作・再読み込みは失わない。
列挙の移設と対象 Picker は task-36 の契約。

仕様の観察・改善案・完了条件は `macos/docs/specs/ui-ux-improvement-backlog.md:136`。
対象はSettingsViewではなく、help「エージェント管理」のボタンが開く `AgentConsoleWindowView` の 3 状態ペイン。
元の所在は `Claude/ClaudeStatusPane.swift:18`、`Codex/CodexStatusPane.swift:18`、`Cursor/CursorStatusPane.swift:18`。

## 入出力契約

- 新設 `AgentConsoleStatusSummary`（`AgentConsoleStatusSummary.swift`、public struct、Equatable、Sendable、SwiftUI・AppKit非依存）:
  - `public static func make(isAvailable: Bool, configFileExists: Bool) -> AgentConsoleStatusSummary`
  - `availabilityText: String`:
    - true = `"CLI を検出済み"`。
    - false = `"CLI を検出できていません"`。
  - `availabilityDetail: String`:
    - true = `"認証・通信の状態は未確認です"`。
    - false = `"インストール先と PATH を確認してください"`。
  - `configurationText: String`:
    - true = `"設定ファイルあり"`。
    - false = `"設定ファイル未作成"`。
  - `configurationDetail: String?`:
    - true = nil。
    - false = `"必要な設定は左の項目から変更できます"`。
  - `cliDetailsTitle: String` = `"CLI の詳細"`。
  - CLIパスが見つかっただけで「認証済み」「利用可能」と断定しない。設定ファイル未作成だけで異常・編集不可にしない。
  - ファイルアクセス、CLI呼び出し、UserDefaults、状態保存を行わない。

- 状態ペインの配線:
  - Claude: `AgentConsoleStatusSummary.make(isAvailable: model.isClaudeAvailable, configFileExists: model.status.settingsFileExists)`。
  - Codex/Cursor: `AgentConsoleStatusSummary.make(isAvailable: model.isAvailable, configFileExists: model.status.configFileExists)`。
  - 検出フラグの根拠は `macos/App/AgentConsole/Claude/ClaudeConsoleModel.swift:52`、`Codex/CodexConsoleModel.swift:49`、`Cursor/CursorConsoleModel.swift:43`。
  - make の実引数は上記と完全一致させる（部分一致や追加演算子を置かない）。
  - 各状態ペインの本文先頭にsummaryのavailabilityText/detail、configurationText/detailを表示する。その後に既存の集計・設定・メモリ等を置く。
  - 既存の「CLI」節の2行を、標準DisclosureGroupへ移す。ラベルはsummary.cliDetailsTitle。
  - `DisclosureGroup(isExpanded:) { } label: { }` 形と、タイトル引数を先に取る形のどちらも許容する。
  - 各状態ペインに `@State private var showsCLIDetails = false` を置き、DisclosureGroupのisExpandedへ接続する。初回表示は閉じる。
  - 展開内容は既存のバージョンと実行ファイルパスをそのまま使う。未取得バージョンの `"—"`、コピー可能なパス表示を維持する。
  - 設定値、件数タイル、メモリ一覧、設定ファイルをFinderで表示する操作、再読み込み、Cursorの認証情報を表示しない説明を残す。
  - Codex の再読み込みから `loadMCPServers()` を外さない。
  - 既存messageBarのエラー・操作結果は折りたたない（messageBar 自体は task-36）。ファイル存在やCLI検出の表示で、読み込みエラーを成功扱いにしない。

- 参照可能性:
  - `macos/Packages/AgentConfigKit/Package.swift:10` に既存のAgentConfigKit・AgentConfigKitTestsターゲットがあり、外部パッケージ依存はない。
  - 3状態ペインは既にAgentConfigKitをimportしている。
  - Appの型をパッケージからimportする逆向き依存を作らない。Package.swift・project.ymlの変更は不要。

- 不変条件:
  - 既存の集計・設定節・メモリ・toolbar・Finder操作・再読み込み・Cursorの認証情報説明は変更しない。
  - CLI未検出でも状態ペイン自体への到達は保つ（到達経路のナビは task-36）。
  - `macos/App/SettingsView.swift` と `AgentConsoleWindowView.swift` は変更しない。
  - custom agents.jsonの追加・編集機能は実装しない。
  - custom起動定義の読取は `macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift:5`、
    カタログへの組み込みは `macos/App/CompositionRoot.swift:209`。この系統は変更しない。
  - 3状態ペインの toolbar、設定節、Finder 操作、`loadMCPServers()` は固定SHA（`TASK37_BASELINE`）と比較する。HEADとの自己比較は使わない。
  - 本草案は未凍結。PMが受け入れテストとRuby検査を作成し、未実装によるredを確認してからbaseline_commitを設定する。
  - acceptance_testsのアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PMに報告し承認を得たうえでハーネス部分に限り修理してよい。

## 成功基準

1. 凍結テスト `AcceptanceAgentConsoleStatusSummaryTests` green。
   StatusSummaryのBool2入力の4組すべてで、4つの表示フィールドとCLI詳細ラベルをリテラル比較する。
   `AgentConsoleStatusSummary` は `func requireEquatable<T: Equatable & Sendable>(_: T.Type)` で確認する。
   `~/.agents/scripts/compact-test task37-agent-config bash macos/scripts/run-swift-tests.sh AgentConfigKit` green。
   Appを含む隔離Debugビルド成功。AgentConfigKitのテスト成功だけでApp側のStatusPane配線を検証済みにしない。
   統合時は既存 `.claude/verify.sh` を正本として実行する。

2. 配線検査 `.claude/scripts/task37-wiring.rb` OK。
   PMが凍結し、`~/.agents/scripts/compact-test task37-wiring env TASK37_BASELINE=<凍結SHA> ruby .claude/scripts/task37-wiring.rb` で実行する。
   文字列リテラルを先にプレースホルダ化したうえで `//` と `/* */` を除去し、括弧・波括弧対応で対象本文を抽出して以下を検査する。
   新設ファイルにSwiftUI・AppKit・Color・View・Observable状態・I/Oがない／`static func make(isAvailable:` がある。
   3状態ペインごとにStatusSummary.makeの実引数が契約と完全一致すること、summaryの先頭表示、showsCLIDetails=false、DisclosureGroupのbinding、展開内部のバージョンとパス2行を検査する。
   `DisclosureGroup(isExpanded:) { } label: { }` 形を許容する。
   旧CLI2行がDisclosureGroupの外にも残る二重表示を落とす。
   既存設定節・summaryTiles・メモリ・toolbar・Finder操作・Cursorの認証情報説明、Codex の `loadMCPServers()` が固定SHAから欠落・変更していないことを検査する。
   HEADとの自己比較は使わない。Rubyの文字列一致だけで表示・到達性を合格にしない。
   `--selftest` で、make 実引数の完全一致（負例: `isAvailable: model.isAvailable && false`）、DisclosureGroup の label クロージャ形、文字列内 `//` と `/* */` 除去を自己検査する。

3. 隔離 Debug の App ビルド（`xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build`）成功を PM ゲートの必須項目とする。
   PM目視ゲート:
   この変更から作った隔離Debugを専用DerivedData・専用データディレクトリで起動する。
   起動結果のPID・実行ファイルパス・ウィンドウ所有PIDを照合し、自PIDのAXからhelp「エージェント管理」のボタンを取得してAXPressで開く。
   以後も自PIDへのAX取得・AXPress、必要時のみ遮蔽確認付き座標クリックを使用する。キー送信は禁止。
   標準の管理ウィンドウ寸法（初期900×620、最小900×600。`PhloxApp.swift:141`、`AgentConsoleWindowView.swift:65`）で確認する。
   状態本文の先頭に検出状況・設定ファイルの有無が表示されることを撮影する。
   各対象の状態で、初回のCLI詳細が閉じていること、AXPressで開くと実際のバージョンと実行ファイルパスが確認でき、閉じても検出状況と設定情報は残ることを撮影する。
   長いパスは既存の省略表示とコピー経路が残ることを確認する。
   CLI検出・未検出と設定ファイル有無の4組は凍結テストで検査し、GUIでは実環境で観測した状態を記録する。負例を作るために利用者のCLIや設定ファイルを削除・変更しない。
   管理画面の既存read-onlyな情報取得を除き、課金セッションの起動・メッセージ送信を要求しない。
   `PHLOX_DATA_DIR`はCLI設定ホームを隔離しない（`AgentConfigKit/Sources/AgentConfigKit/Claude/ClaudeConfigPaths.swift:12`）。管理画面から設定を書き換えず、隔離済みと誤記しない。
   AX取得・展開・撮影できなかった項目は未検証とする。終了時は自分が起動したPIDと子プロセスだけを確認して終了する。

## レビュー観点（Rubric）

- CLI検出を認証・通信成功と混同せず、設定ファイル未作成を無条件の異常として扱っていない。
- 技術情報を削除せず、CLI詳細の展開から確認できる。既存エラーは折りたたまれない。
- 既存の集計・設定・メモリ・Finder・再読み込みを、要約の追加のために欠落させていない。
- 設定の保存、権限、秘密情報、CLI実行の既存挙動を変更していない。
- SettingsViewとWindowViewのナビゲーション、custom agents.jsonの系統を巻き込んでいない。
