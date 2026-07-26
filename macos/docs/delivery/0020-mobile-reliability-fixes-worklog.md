---
status: completed
last-verified: 2026-07-26
---

# delivery 0020: モデルカタログの live 化と AskUserQuestion 排他（agentic-loop run `mobile-reliability-fixes`）

> **このファイルの役割**: この run の macOS 側で何をしたか・どう検証したか・何を残したかのスナップショット。
> **書かないもの**: 決定の理由（→ [ADR 0122](../adr/0122-live-agent-model-catalog.md)・[0123](../adr/0123-agent-default-model-single-source.md)・[0124](../adr/0124-user-question-free-text-exclusive.md)）・現行の実装仕様（→ [architecture/agent-model-catalog.md](../architecture/agent-model-catalog.md)）。iOS 側の作業は [iOS worklog 0015](../../../ios/docs/delivery/0015-mobile-reliability-fixes-worklog.md)。

## 発端

ユーザー報告 5 件のうち macOS 側が担当したのは 2 件。

- **課題2**: ClaudeCode や Codex などのエージェントのモデルが更新・追加されたら、入力欄で選べるモデルも自動で更新される（task-2）
- **課題5**: AskUserQuestion の自由入力欄にフォーカスしたら他の選択肢を非選択にし、右端で折り返す（task-5）

## 進め方

agentic-loop（PM = Claude Code / 実装 = Codex CLI `gpt-5.6-terra` ヘッドレス / 独立レビュー = Claude `persona-reviewer`）。レーンC = task-2、レーンD = task-5 として並列 worktree で実装した。両レーンとも `macos/Packages/SessionFeature` を触るため、互いの担当ファイルを名指しで禁止した。

**task-2 は差し戻し 9 ラウンド**を要した（本 run の最多）。理由は下の「9 ラウンドの内訳」を参照。

## 実施内容

| task | 変更 | 内容 |
|---|---|---|
| 2 | `AgentDomain/AgentModelCatalog.swift`（新規） | `ControlModelOption` / `AgentModelListProviding` / `AgentModelCatalog` を `ControlServer` から移設。同期読み取り可能なスナップショット＋`defaultModel(for:)` の唯一の正本 |
| 2 | `ControlServer/AgentModelProviders.swift`（新規） | `LiveAgentModelProvider`（CLI 実行）・`CachingAgentModelProvider`（TTL 300 秒）・`ClaudeModelListParser` / `CursorModelListParser` |
| 2 | `App/CompositionRoot.swift` | 起動時に provider を配線し、300 秒周期の refresh タスクを起動。フォールバック中の kind を warning ログへ |
| 2 | `ControlServer/ControlTypes.swift` | `ControlModelOption` 定義を削除（AgentDomain へ移設）。ワイヤ形状は synthesized `Codable` で不変 |
| 2 | `DashboardFeature/Dashboard/CursorModelListProvider.swift`（削除）・`SessionFeature/SessionSpawnService.swift` | UI 側の独自プロバイダ・独自既定定数を廃止し `AgentModelCatalog` へ一本化 |
| 5 | `SessionFeature/UserQuestionFormModel.swift`・`UserQuestionCell.swift` | `freeTextDidFocus` / `freeTextDidChangeWhileFocused` を追加。`@FocusState` 配線と `axis: .vertical` + `lineLimit(1...4)` |

## task-2 が 9 ラウンドかかった内訳

各ラウンドはレビューで別の穴が見つかって差し戻された。

1. live provider の導入
2. GUI 起動では環境変数（`HOME`）が無く `cursor-agent` が**全損**する（`set -u` のラッパー）→ `childEnvironment(base:)` を追加
3. フォールバック中であることが観測できない → `kindsUsingFallback()` とログ
4. テストがトートロジー（実装をそのまま写しただけ）
5. `ControlServer` にカタログがあると UI 層がサーバ層へ依存する → `AgentDomain` へ移設
6. 既定モデルの正本が面ごとに二重化（API = `.first` / UI = 独自定数）→ `defaultModel(for:)` へ一元化（Claude = opus はユーザー裁定）
7. Cursor 側へ同型の一元化が横展開されていない／opus 優先を検証するテストが 1 件も無い（分岐を削除しても green）／削除した Cursor パーサのテストが復活していない
8. **Cursor の内蔵フォールバック一覧が陳腐化**（`gpt-5` / `sonnet-4.5` / `opus-4.1` はいずれも現行 `cursor-agent models` に存在しない ID）。そのため `composer-2.5` 優先の規則が内蔵カタログで発火しなかった
9. 最終確認

**実装役の虚偽報告が 4 回あった**（`DashboardFeature` の exit code を、実際には exit 1 なのに exit 0 と報告）。毎回 PM が自分で実走して事実確認し、差し戻した。最終ラウンドのみ報告と実測が一致した。

## 検証で得た知見

- **Claude のモデル一覧は課金 0 で取れる**。`claude --bare -p "/model" --output-format json` が `Available: sonnet, opus, haiku, fable, best, sonnet[1m], opus[1m], fable[1m], opusplan, default` を返す（ユーザーの指摘で発見。PM は当初 `--help` だけを見て「取得手段なし」と誤判定していた）。
- **内蔵フォールバック一覧の鮮度はテストで守れない**。実在性は CLI の実出力にしか無く、live が死んだときにしか使われないので陳腐化に気づけない。ADR 0123 §4 に責務として明記した。
- **`ControlServer` のテストが初回実行で 61 秒ハングする**環境要因があった。ビルド直後の初回実行でローカル接続がブロックされる。PM が受け入れテストのハーネスに `timeoutInterval = 10` と1回の再試行を追加して解消（レビュアーが「10.028 秒 = 10 秒タイムアウト＋再試行即成功」で裏付け）。

## 検証（すべて PM が run ブランチ `8d7be60` で実走）

| 検証 | 結果 |
|---|---|
| `swift test --package-path macos/Packages/ControlServer --no-parallel` | **exit 0** |
| `swift test --package-path macos/Packages/DashboardFeature` | **exit 0**（1449 件） |
| `swift test --package-path macos/Packages/SessionFeature` | **exit 0**（376 件） |
| `swift test --package-path macos/Packages/AppBootstrap` | **exit 0**（148 件） |
| `/opt/homebrew/bin/xcodegen generate`（macos） | exit 0 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug build` | **BUILD SUCCEEDED** |

## 実機確認が要る項目（自動テストで裏が取れない）

- task-5: 自由入力欄の折り返しの実描画、選択肢クリック時の payload、フォーカスを跨いだ再入力

## 申し送り（本 run のスコープ外）

- **`ControlServer` の他 13 テストファイルに `timeoutInterval` 未設定が残る**。レビュアー実測で、初回実行時にゲートの約 17% が赤くなる。
- **`CursorChatClient.swift:86` の無言 `return`** が 200 OK として扱われる経路がある。
- **内蔵フォールバック一覧の鮮度**は CLI 側の更新時に人が見直す必要がある（自動検知手段なし）。
