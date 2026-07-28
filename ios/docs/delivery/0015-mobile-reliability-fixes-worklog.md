---
status: completed
last-verified: 2026-07-26
---

# delivery 0015: モバイル信頼性修正 5 件（agentic-loop run `mobile-reliability-fixes`）

> **このファイルの役割**: この run で何をしたか・どう検証したか・何を残したかのスナップショット。
> **書かないもの**: 決定の理由（→ [ADR 0027](../adr/0027-session-list-probe-before-offline.md)・[0028](../adr/0028-input-bar-enabled-on-completed-and-error.md)・[0029](../adr/0029-subagent-window-and-render-budget.md)・[0030](../adr/0030-draft-model-selection-kind-and-id.md)、macOS 側は [同 0020 worklog](../../../macos/docs/delivery/0020-mobile-reliability-fixes-worklog.md)）・現行の実装仕様（→ [architecture/overview.md](../architecture/overview.md)）。

## 発端

ユーザー報告（スクリーンショット2枚付き）4件＋追加1件。

1. 接続チェック中は「接続中」アニメを出し、オフライン画面は**本当に接続できなかった場合だけ**出す
2. エージェントのモデルが更新・追加されたら入力欄で選べるモデルも自動で更新される（→ macOS 側 worklog）
3. モバイルで追加したセッションがエラーで停止すると**入力欄が消えて何も入力できない**
4. 起動中のサブエージェントを押すと**白画面で固まる**（原因特定も依頼）
5. AskUserQuestion の自由入力欄にフォーカスしたら他の選択肢を非選択にし、右端で折り返す

## 進め方

agentic-loop（PM = Claude Code / 実装 = Codex CLI `gpt-5.6-terra` ヘッドレス / 独立レビュー = Claude `persona-reviewer`）。`dev` から `feature/mobile-reliability-fixes` を worktree で切り、**系統レーン単位の worktree 4本**で並列実装した（レーンA = iOS SessionDetail 本体 / B = iOS その他 / C = macOS モデルカタログ / D = macOS AskUserQuestion）。

タスクは 8 件（ユーザー報告 5 件＋派生 3 件）。iOS 側は task-1 / 3 / 4 / 6 / 7 / 8。

**フェーズ0 で fable による敵対的レビュー2本を実施**した。原因特定 5 件はすべて real（誤りゼロ）だったが、修正計画に MUST 2 件・HIGH 5 件の穴が見つかり（spawn 受理側の見落とし・iOS 側 Codex ハードコード・凍結契約との衝突・Codex に respawn 機構なし・永久スピナーの脱出条件なし）、各タスク契約へ織り込んだ。

## 実施内容（iOS）

| task | 変更 | 内容 |
|---|---|---|
| 1 | `PhloxCore/SessionRepository.swift`・`Features/SessionList/SessionListView.swift` | 到達性 `.unknown` を offline 扱いせず `refresh()` で能動判定。判定が付くまで `.loading`、20 秒の締切超過でのみ `.offline`。`.loading` を `DSConnectingIndicator(size: 96)` に。オフライン画面へ渡す理由の丸め（`offlineReachability`）を削除 |
| 3 | `Features/SessionDetail/SessionDetailViewModel.swift` | `inputEnabled` が false になるのを `starting` だけに変更（`completed` / `error` を有効化） |
| 4 | `Features/SessionDetail/SubAgentDetailViewModel.swift`・`SubAgentDetailView.swift` | `TranscriptWindow`（末尾50件）＋「以前のメッセージを読む（N件）」＋ `maxRenderedBytesPerMessage`（16 KiB）の head+tail 切り詰め＋省略注記＋初回ロードの接続中表示 |
| 6 | `Features/SessionDetail/UserQuestionCard.swift`・`UserQuestionFormState.swift`（新規） | 選択状態を値型へ切り出し。`@FocusState` + `freeTextDidFocus` で自由入力フォーカス時に選択肢を解除。`axis: .vertical` + `lineLimit(1...4)` で折り返し |
| 7 | `Features/SessionDetail/SessionDetailViewModel.swift` | Codex のカタログを捨てていた分岐を撤去し、3エージェントすべてのモデル行を並べる。agent-only 行は Codex のカタログが空のときだけ |
| 8 | 同上 | 選択の保持を表示用 ID 文字列から `DraftModelSelection { kind, modelID }` へ。再取得時の解決順を kind 保持で固定 |

## 検証で得た知見

- **task-4 の原因は件数ではなくバイト数**だった。レビュアーが `ImageRenderer` でヘッドレス計測し、1 MB = 0.130 秒 / 6 MB = 0.669 秒、**レイアウト費用は総バイト数に比例し件数にほぼ依存しない**ことを実測。件数窓だけでは単一の巨大出力（サブエージェントの `command` 出力・`fileChange` の diff）に無効と判明し、描画バイト上限を契約へ追加した。
- **切り詰めは head だけでは目的と逆**。この画面の目的は「起動中のサブエージェントが今何をしているか」なので、head+tail 方式へ改訂した。
- **値型だけをテストすると View を巻き戻しても green のまま**になる。task-5 のレビューで `UserQuestionCell.swift` を修正前へ丸ごと巻き戻しても 387 件が1件も落ちないことが実測されたため、以降 task-4 / 6 の受け入れテストに **`#filePath` からソースを読む View 配線の assert** を追加した（同パッケージの `Wave3SessionDetailChromeWhiteboxTests` に前例あり）。
- **task-8 の受け入れテストは PM のハーネス欠陥で最初バグを再現できなかった**。`sendMessage()` を引数なしで呼ぶと 2 回目の `prepareDraft` が走らない。`sendMessage(composeDraft:)` へ修理して初めて 4 パターンが赤になった。実装役はハーネスを書き換えず事実を報告して正しかった。

## 検証（すべて PM が run ブランチ `8d7be60` で実走）

| 検証 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | **exit 0**（XCTest 479 件 / Swift Testing 505 件） |
| `/opt/homebrew/bin/xcodegen generate`（ios） | exit 0 |
| `make build`（iOS シミュレータ・Debug） | **BUILD SUCCEEDED** |

macOS 側の検証結果は [macOS worklog 0020](../../../macos/docs/delivery/0020-mobile-reliability-fixes-worklog.md) 参照。

## 実機確認が要る項目（自動テストで裏が取れない）

- task-1: 接続中アニメの見え方、オフライン画面へ落ちるまでの 20 秒
- task-4: 実際に固まっていたセッションの `subAgentMessages` 件数と1件あたり最大バイト数、タップから描画までの秒数、戻るボタンの応答、省略注記のバイト数
- task-6: 折り返しの実描画、選択肢タップ時の payload、フォーカスを跨いだ再入力

## 申し送り（本 run のスコープ外）

- **Codex に respawn 機構が無い**。ADR 0028 で停止中も入力欄を出すようにしたが、Codex では送信しても復帰しない可能性がある。
