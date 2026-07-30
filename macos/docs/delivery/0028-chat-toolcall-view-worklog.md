---
status: completed
last-verified: 2026-07-31
---

# 0028: チャットのツール表示の刷新（chat-toolcall-view run）

> agentic-loop run（backend=codex / gpt-5.6-terra）。ブランチ `feature/thinking-orbs`。
> 実装は Codex ヘッドレス、独立レビューは Claude `persona-reviewer`（実装者と別モデル）。

## 何をしたか

最初の 4 要望を 3 タスクで実装したあと、実機で見たユーザーのフィードバックを 3 巡ぶん（task-4〜6）追加で実装した。

| タスク | 内容 | コミット |
|---|---|---|
| task-1 | カードのアイコン・スピナー・完了チェックの撤去、ツールコールの半透明グレー化、チャットのアバター撤去（要望 A・D） | `2413789` |
| task-2 | ツール実行グループの見出しを recap 化、トグルを右端へ、展開時の 2 段表示（要望 C） | `faaff97` |
| task-3 | ファイル変更の diff をコードビュー化（行番号・構文ハイライト・ノイズ除去・パス短縮）（要望 B） | `e888a1e` |
| task-4 | カードヘッダの時刻を撤去、シェブロンをタイトル直後へ、見出しの `〜を実行` 接尾辞を廃止、Reasoning を recap 表示、コピーボタンをホバー表示に | `b389d3d` |
| task-5 | 件数サブタイトルの撤去、見出しと本文の重複解消、diff の帯を連続化、ファイル変更を折りたたみ既定＋`+A -D` 見出しに、時刻をコピーボタンの右へ | `b8f7d6d` |
| task-6 | 共通 `ChatCodeCard` を新設し diff とコマンド実行を枠線付きカードへ統一、「実行中」撤去、hunk ヘッダ非表示、番号列の可変幅、シェル構文ハイライト＋ツール名ラベル | `eae143f` |

決定は ADR へ蒸留した: [0144](../adr/0144-quiet-chat-chrome.md) / [0145](../adr/0145-tool-group-recap-header.md) / [0146](../adr/0146-diff-code-view.md) / [0147](../adr/0147-chat-code-card-and-header-dedup.md)。
task-4〜6 は 0144〜0146 の一部決定を覆しているため、**0147 を新規に起こし、0144〜0146 の冒頭に後継注記を足した**（ADR は追記専用）。
現行構成は [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md) に反映済み。

task-6 だけは実装前に Codex へ設計を依頼し（`docs/agent-output/design-codeview.md`）、
PM が採否を決めてから契約に落とした。設計案のうち「`ChatItem` にツール名フィールドを足す」は採用せず、
表示側のヒューリスティック（`CommandToolLabel.derive`）に変えている（永続型を表示都合で変えないため）。

## 検証

- `swift test`（task-6 完了時点）: DesignSystem 111 / SessionFeature 745 / AgentDomain 240 / DashboardFeature 1484 — いずれも pass（フィルタ・skip なし）。
- `xcodebuild -scheme Phlox -configuration Debug`（別 derivedDataPath `/tmp/phlox-dd-toolcallview`）で **BUILD SUCCEEDED**。
  デバッグ版は `open -n` で別インスタンス起動し、**稼働中のリリース版は一度も終了させていない**。
- 目視: `ImageRenderer` で実行中／完了のツール実行グループ・ファイル変更カード・Bash 実行カードを PNG に落として PM が確認した
  （アイコン・スピナー・時刻・サブタイトル無し、コマンド原文の見出し、タイトル直後のシェブロン、枠線付きカード内の
  フルパス＋連続した帯の diff、`Bash` ラベル＋`$ command` のシェルハイライト）。
  スナップショット用の一時テストは確認後に削除済み。
- 継続行のインデントは独立レビューが `ImageRenderer` のピクセル実測で検証した（誤 x=34 → 修正後 x=18）。
- **未検証**: 実クリックでの開閉操作（`.contentShape` の効き）は自動テスト・静的レンダのみで、GUI 上の操作確認はしていない。

## レビューで実際に潰れた欠陥（独立レビューの効き）

- **複数行コマンドで見出しが末尾断片に化ける**（`ThinkingRecap.summary` を要約器ごと再利用していた）。
- **壊れた hunk ヘッダで index out of range クラッシュ**（`split(...)[0]`）。`Int.max` 起点の算術オーバーフローも同種。
- **`\ No newline at end of file` が行番号を 1 ずらす**。
- **恒真テスト 3 件**（本番未参照の定数同士の検算・恒等関数の検証・配線を消しても落ちないスモーク）。
- **未要求の視覚退行**（ファイル変更／TaskList のサブタイトルが secondary → primary へ濃くなっていた）。
- **性能**: 出力の行分割が body 1 回につき 4 回走っていた（20000 行で 35ms → 8.9ms）。
- **継続行の二重インデント**（`HStack` のインデントと `"\n  "` の文字列置換が両方効いていた）。実測 x=34。
- **テスト専用 init を通す検証**（本番経路 `CommandGroupExecutionDisplayData.outputDisplay` を通らないテスト）。

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
- **`CommandToolLabel` のツール名判定はヒューリスティック**（先頭トークンの完全一致）。生成側が
  `"<Tool> <arg>"` 形式を変えると外れて `Bash` に落ちる。`ChatItem` を変えない代償として受け入れた。
- 非ブロッキングの LOW 残件: `\ No newline at end of file` リテラルが 2 箇所に分散、
  `Label` 分解によるアイコン-テキスト間隔の微差（目視未確認）。
