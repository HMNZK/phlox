---
status: completed
last-verified: 2026-07-30
---

# 0028: チャットのツール表示の刷新（chat-toolcall-view run）

> agentic-loop run（backend=codex / gpt-5.6-terra）。ブランチ `feature/thinking-orbs`。
> 実装は Codex ヘッドレス、独立レビューは Claude `persona-reviewer`（実装者と別モデル）。

## 何をしたか

ユーザーの 4 つの要望を 3 タスクに分けて実装した。

| タスク | 内容 | コミット |
|---|---|---|
| task-1 | カードのアイコン・スピナー・完了チェックの撤去、ツールコールの半透明グレー化、チャットのアバター撤去（要望 A・D） | `2413789` |
| task-2 | ツール実行グループの見出しを recap 化、トグルを右端へ、展開時の 2 段表示（要望 C） | `faaff97` |
| task-3 | ファイル変更の diff をコードビュー化（行番号・構文ハイライト・ノイズ除去・パス短縮）（要望 B） | `e888a1e` |

決定は ADR へ蒸留した: [0144](../adr/0144-quiet-chat-chrome.md) / [0145](../adr/0145-tool-group-recap-header.md) / [0146](../adr/0146-diff-code-view.md)。
現行構成は [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md) に反映済み。

## 検証

- `swift test`: DesignSystem 111 / SessionFeature 751 / DashboardFeature 1484、AgentDomain 240 — いずれも pass（フィルタ・skip なし）。
- `xcodebuild -scheme Phlox -configuration Debug`（別 derivedDataPath）で **BUILD SUCCEEDED**。稼働中のリリース版は終了させていない。
- 目視: `ImageRenderer` で実行中／完了のツール実行グループとファイル変更カードを PNG に落として PM が確認した
  （アイコン・スピナー無し、recap 見出し、右端シェブロン、件数サブタイトル、行番号付きハイライト diff）。
  スナップショット用の一時テストは確認後に削除済み。
- **未検証**: 実クリックでの開閉操作（`.contentShape` の効き）と、実セッションでの live recap の時間追従は
  自動テスト・静的レンダのみで、GUI 上の操作確認はしていない。

## レビューで実際に潰れた欠陥（独立レビューの効き）

- **複数行コマンドで見出しが末尾断片に化ける**（`ThinkingRecap.summary` を要約器ごと再利用していた）。
- **壊れた hunk ヘッダで index out of range クラッシュ**（`split(...)[0]`）。`Int.max` 起点の算術オーバーフローも同種。
- **`\ No newline at end of file` が行番号を 1 ずらす**。
- **恒真テスト 3 件**（本番未参照の定数同士の検算・恒等関数の検証・配線を消しても落ちないスモーク）。
- **未要求の視覚退行**（ファイル変更／TaskList のサブタイトルが secondary → primary へ濃くなっていた）。
- **性能**: 出力の行分割が body 1 回につき 4 回走っていた（20000 行で 35ms → 8.9ms）。

## 積み残し・既知の制約

- **Claude セッションの diff では行番号が出ない**。生成側（`ClaudeAgentKit/ClaudeChatClient+Formatting.swift`）が
  `@@` としか出さず、実ファイルの行番号を持たないため。1 起算の偽番号を出すのは誤情報なので見送った。
  番号付き hunk ヘッダを出すかは別 run の判断（生成側は old/new を丸ごと並べる方式なので、
  そもそも「本物の diff」にするかどうかから検討が要る）。
- **`SubAgentDrawerPresentation.reasoningPreview` が本番未使用の孤児**になった。task-2 で
  `SubAgentDrawerView` から `reasoningPreview:` を落とした結果で、残っているのは `AcceptanceSubAgentDrawerParityTests` /
  `SubAgentDrawerParityWhiteboxTests` だけ。畳むには allowed_paths 外のテストに手が要るため見送った。
- **`descriptor` が 3 セルで未使用の格納プロパティ**として残っている（`DashboardFeatureTests` が
  イニシャライザを呼ぶため）。
- 非ブロッキングの LOW 残件: `\ No newline at end of file` リテラルが 2 箇所に分散、
  `Label` 分解によるアイコン-テキスト間隔の微差（目視未確認）。
