---
status: active
last-verified: 2026-07-26
---

# ADR-0120: スラッシュコマンド補完の正本を静的リストからセッションの提供一覧（system/init）へ移す

## 文脈

agent-grid-jank run（2026-07-24）で、`ComposerSuggestions.swift` に Claude Code の
組み込みコマンド 23 件をハードコードした（旧 `AcceptanceBuiltinSlashCommandsTests` が
`/config`・`/plugin` の収録を凍結）。

その後、ユーザーが補完から `/plugin` を選んで送ると
`/plugin isn't available in this environment.` が返り、`/config` は引数なしだと
usage 文が返るだけという報告が出た。

Phlox と同じ引数で claude CLI（2.1.220）を起動して stream-json を直接測定したところ、
`system` / `subtype=init` イベントが `slash_commands` として **104 件の配列**を運んでいた。
静的リストと突き合わせると:

- 静的 23 件のうち **13 件がセッションに存在しない**:
  `/help` `/plugin` `/permissions` `/status` `/cost` `/memory` `/output-style`
  `/export` `/statusline` `/todos` `/rewind` `/resume` `/hooks`
- 存在が確認できたのは 10 件だけ:
  `/compact` `/clear` `/model` `/init` `/config` `/mcp` `/context` `/usage` `/doctor` `/review`
- 逆に、実在する約 90 件（`/agents` `/effort` `/fast` `/recap` やユーザーのスキル・
  カスタムコマンド）は一度も候補に出ていなかった。

補完は「このセッションへ送れるコマンド」の表明であるべきなのに、静的リストは
CLI の更新でずれ続ける（実際に 2.1.218 → 2.1.220 の間でずれた）。

また実測で、**init はセッション起動時ではなく最初のメッセージ送信後に届く**ことも確認した
（無送信で 100 秒待っても `hook_started` / `hook_response` しか来ない）。

## 決定

- **セッションが `system/init` で申告した `slash_commands` を補完候補の正本にする。**
  - `StructuredChatKit` の公開 enum に
    `NormalizedChatEvent.availableCommandsUpdated(commands: [String])` を追加する
    （名前は先頭 `/` を含まない素の名前・受信順を保つ全量スナップショット）。
  - `ClaudeChatClient+EventParsing.swift` の `system`/`init` 処理で `slash_commands` を
    読み、`[String]` として取れたときだけ yield する（欠落・型不一致・空配列では yield しない）。
  - `ChatSessionViewModel.availableSlashCommands: [String]?` が全量スナップショットで
    **置き換え**保持する（差分マージしない）。他イベントではクリアしない。
  - `ComposerSuggestionController.availableSlashCommands` を経由して
    `ComposerSuggestionSources.slashCandidates(availableCommands:homeDirectory:workingDirectory:)`
    へ渡す。View 配線はチャット・グリッド双方（`ChatComposer` / `GridChatColumn`）で、
    生成時だけでなく値変化にも追従する（init は最初の送信後に届くため生成時は必ず `nil`）。
- **`nil`（未受領）と `[]`（受領して 0 件）を区別する。** `nil` のときだけ静的フォールバック
  ＋ `.claude/commands` / `.claude/skills` 走査を使う。非 `nil` のときは一覧の名前だけを
  候補にし、走査由来の候補を混ぜ戻さない。
- **静的フォールバックは残すが、実在しない 13 件を削除する**（23 → 10 件）。init 到着前は
  必ずフォールバックが表示されるため、ここが実態とずれていると同じ事故が再発する。
- 一覧由来の候補の扱い: `__` で始まる内部コマンドは除外、重複は一意化、subtitle は
  ①静的リストの同名エントリ ②`.claude/skills/<名前>/SKILL.md` の frontmatter `description`
  ③`.claude/commands/<名前>.md` のカスタムコマンド文言 ④なければ `nil` の優先順で補う。
- 5 秒 TTL キャッシュ（ADR 0053）は維持しつつ、**キャッシュキーに一覧を含める**
  （別セッション・別一覧の候補が混線しないこと）。

## 棄却案

- **静的リストを 10 件へ直すだけ**: 今回のずれは直るが、CLI 更新のたびに再発する。
  実在する約 90 件が出ないままなのも解決しない。init は Phlox が既に受信している
  イベントで追加の通信コストがないため、動的化を採る。
- **init の一覧から「組み込みらしきもの」だけを採用し、スキル/カスタムは従来どおり
  ディレクトリ走査で出す**: 振り分け規則を自前で持つ必要があり、CLI 側の分類変更で
  再びずれる。ユーザー裁定で棄却。

## 結果

- 凍結テスト: `AcceptanceAvailableCommandsEventTests`（StructuredChatKit）・
  `AcceptanceInitSlashCommandsTests`（ClaudeAgentKit）・
  `AcceptanceBuiltinSlashCommandsTests` / `AcceptanceComposerAvailableCommandsTests`
  （SessionFeature）。
- 旧契約を符号化していた `BuiltinSlashCommandsWhiteboxTests` は削除し、
  `AcceptanceBuiltinSlashCommandsTests` は「13 件が**無い**こと・10 件が有ること・
  一覧受領時は一覧に一致すること」へ差し替えた（旧契約は実測で反証されたため）。
- 実機ビジョン検証（1.3.2 Debug ビルド, 2026-07-26）で、init 到着後の補完から
  `/plugin`・`/help` が消え、`/agents`・`/effort`・`/fast`・`/recap` とユーザーのスキルが
  出ることをチャット・グリッド双方で目視確認した。
- 残る制約: **Codex / Cursor セッションには一覧の供給源がない**ため、それらは静的
  フォールバックのまま（Claude 固有の候補が出る問題は別 run で扱う）。
- 残る制約: init は最初の送信後に届くため、**セッション初回送信前の補完は必ず
  フォールバック 10 件**になる。
