---
id: task-41
difficulty: standard
depends_on: []
user_visible: false
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift
  - .claude/scripts/task41-wiring.rb
baseline_commit: 1ad3e09
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift
  - docs/agent-output/task-41.md
---

## 目的

UX-01 のうち、一つのユーザーメッセージから短い作業名を導出する純粋関数を実装する。名前状態・チャット接続・保存は task-44、表示は task-45 が担当する。UX-01 の完了は3契約の成立後とする。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。本契約は単一草案 `docs/agent-output/contract-draft-task-41.md` の分割版である。

調査対象 HEAD は `cb17de2193f80010a5126e19b2265b018452a2d7`。草案と実コードを読み合わせた。今回の起草ではファイル変更、テスト作成・実行、ビルド、GUI確認を行っていない。

## 入出力契約

### 担当・境界

- Cursor は `allowed_paths` 内の製品実装と開示レポートだけを担当する。受け入れテスト・Ruby検査・契約・検証ゲートを作成、変更しない。
- PM が本契約の期待値から Swift Testing とRuby検査を作成し、未実装による red を確認して凍結する。レビューはCursorの実装モデルとは別モデルが担当する。
- `AgentDomain/Package.swift` に既存の `AgentDomainTests` がある。新規パッケージ・依存・テストターゲットを追加せず、Appターゲットにテストを置かない。
- task-44、task-45 の `allowed_paths` との交差はない。本タスクで既存ファイルや呼び出し元を変更しない。
- `baseline_commit` は調査時HEADから自動設定しない。

### 新規公開契約

次の型・メンバーは既存シンボルではなく、本契約で新設するAPIである。

```swift
public struct DerivedSessionTitle: Equatable, Sendable {
    public let title: String
    public let fullTitle: String
}

public enum SessionTitleDeriver {
    public static func derive(from text: String) -> DerivedSessionTitle?
}
```

入力は一つのユーザーメッセージ本文。出力は表示用に短縮した `title` と、短縮前の候補行 `fullTitle`。適格な候補がなければ `nil` とする。`fullTitle` は依頼全文やtranscript全文ではない。

導出規則は次の順序に固定する。

1. CRLF・CRをLFとして扱い、元の行順で走査する。
2. コードフェンスの開始・終了行と内部を除外する。開始は行頭の半角空白0〜3個に続く、バッククォートまたはチルダの同一文字3個以上の連続。後続の言語指定は許す。終了は同じ文字が開始時以上の個数続き、その後が空白だけの行。別種・短いフェンスでは閉じず、未閉鎖なら末尾まで除外する。
3. フェンス外で、元の行がタブまたは半角空白4個以上で始まる場合は、貼り付けコードとして除外する。
4. 行の前後の空白を除き、Foundationの幅変換で全角・半角の違いを揃える。ロケールは固定し、大文字・小文字は変更しない。
5. 行内の連続する半角空白・タブ・全角空白を半角空白1個にする。
6. 空行と以下の行を除外し、次の行へ進む。接頭辞判定は大文字・小文字を区別する。
   - `/` で始まる行。引数付きも行全体を除外する。
   - `import `、`from `、`func `、`def `、`class `、`struct `、`enum `、`let `、`var `、`const `、`function `、`return `、`#include `、`#!/`、`$ ` で始まる行。
   - `{`、`}`、`[`、`]` で始まる行。
7. 最初に残った行を `fullTitle` とする。残らなければ `nil`。
8. Swiftの `Character` 単位で32文字以内なら `title == fullTitle`。33文字以上なら先頭31文字と `…` を結合する。絵文字・結合文字を途中で切らない。

Foundationと標準ライブラリだけを使う。ファイル、時計、設定、乱数、ネットワーク、プロセス、Viewに依存せず、元の送信本文・添付・transcriptを変更しない。

コード候補の除外は限定的な規則であり、任意のプログラミング言語を識別しない。この限界と「実例・テストが必要になった時点で拡張する」方針を `ponytail:` コメントに記す。

## 成功基準

### 1. Swift Testing

PMは次の期待値を固定する。製品の戻り値から期待値を生成しない。表の `\n`・`\r`・`\t` は実際の制御文字を入力する。

| 入力 | 期待する結果 |
|---|---|
| `ログイン画面を修正\n詳しい条件` | title/fullTitleともに `ログイン画面を修正` |
| `\r\n  API\t の　接続を修正  \r\n次の行` | 両方 `API の 接続を修正` |
| `ＡＰＩ　１２３を修正` | 両方 `API 123を修正` |
| 空文字、空白のみ、改行のみ | `nil` |
| `/review`、`／review 引数` | `nil` |
| `/review\nログイン画面を修正` | 両方 `ログイン画面を修正` |
| バッククォート3個の開始行、コード、対応する終了行だけ | `nil` |
| 上記の閉じたフェンスの次行が `ログインを修正` | 両方 `ログインを修正` |
| チルダ3個のフェンス | バッククォートと同じ除外規則 |
| バッククォート4個で開始し、3個の行しかない | 開始後から候補を採らない |
| バッククォートで開始し、チルダだけで終了を試みる | 開始後から候補を採らない |
| 未閉鎖フェンスの前に適格な行がある | フェンス前の最初の適格行 |
| `    let value = 1\nログインを修正` | 両方 `ログインを修正` |
| `\t説明\nログインを修正` | 両方 `ログインを修正` |
| `import Foundation\nログインを修正` | 両方 `ログインを修正` |
| 各除外接頭辞の行に続く `ログインを修正` | 両方 `ログインを修正` |
| `APIを修正` | 大文字を維持 |
| `abcdefghijklmnopqrstuvwx12345678` | 32文字をそのまま維持 |
| `abcdefghijklmnopqrstuvwx123456789` | titleは `abcdefghijklmnopqrstuvwx1234567…`、fullTitleは入力33文字 |

さらに、`👨‍👩‍👧‍👦` と結合文字 `e\u{301}` をそれぞれ使った32／33 Character境界を検査する。33 Characterの入力では31 Characterと `…` になり、fullTitleを維持する。同一入力への反復呼び出しが同じ結果を返し、入力文字列が変化しないことも検査する。

### 2. 凍結検査

PMが `.claude/scripts/task41-wiring.rb` を作成する。見本は `.claude/scripts/task38-wiring.rb` と `.claude/scripts/task39-wiring.rb`。文字列導出の正しさはSwift Testingで検査し、Rubyへの再実装で代替しない。

Ruby検査は以下を要求する。

- `TASK41_BASELINE` はコミットSHA必須。契約の `baseline_commit` と完全SHAに解決して一致させる。
- `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックは禁止する。
- `git show <凍結SHA>:<path>` のblobを基準にする。受け入れテストとRuby自身が基準コミットに存在し、現在の内容と一致することを確認する。
- 基準コミットには新規 `SessionTitleDeriver.swift` が存在しないことを確認する。実装入りHEADのSHAを渡す自己比較を拒否する。
- 実装前の凍結時点で指定SHAとHEADが同一であること自体は拒否しない。
- 新規公開APIの存在、許可したimport、I/O・追加AI呼び出しがないことを確認する。コメント・文字列を実コードとして数えない。対象不在・解析不能は非ゼロ終了。
- `--selftest` は実ファイルを変更せず、正例と、SHA未設定・不正・契約不一致・blob欠落・テスト改変・検査改変・実装入り基準・禁止依存・コメントだけの宣言偽装を検査する。

### 3. 検証と開示

凍結時の受け入れ確認：

```sh
~/.agents/scripts/compact-test task41-models bash macos/scripts/run-swift-tests.sh AgentDomain
~/.agents/scripts/compact-test task41-wiring-selftest ruby .claude/scripts/task41-wiring.rb --selftest
~/.agents/scripts/compact-test task41-wiring env TASK41_BASELINE=<凍結SHA> ruby .claude/scripts/task41-wiring.rb
```

実装後の統合確認は既存の正本を使う。

```sh
~/.agents/scripts/compact-test task41-integration bash .claude/verify.sh
```

`<凍結SHA>` はPMが実値に置換する。確認した `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。受け入れテストとRuby検査の実行結果を別に記録する。

変更は純粋関数の新設だけであり、App画面の目視ゲートは対象外。独立したlint・静的解析設定は今回の探索範囲では見つかっていない。PMは凍結時に設定を再確認し、未設定と未実行を区別する。

`docs/agent-output/task-41.md` に、導出契約の実装状況、実行コマンド・結果、未検証事項、変更パスを記録する。製品にも検証にも実claude／codex／cursorセッションの起動を要求しない。

## レビュー観点（Rubric）

- **文字列契約**：除外順序、フェンス対応、幅変換、32／33 Character境界が期待値どおり。
- **純粋性**：入力を変更せず、I/O・設定・追加AI呼び出しに依存しない。
- **責務境界**：名前状態、保存、View、呼び出し元を変更していない。
- **検証の独立性**：Swift Testingが実関数を検査し、凍結blob・`--selftest` が検査の改変と自己比較を拒否する。
- **報告の正確さ**：task-41の成立をUX-01全体の完了と報告していない。

## 敵対レビュー反映（2026-09-13、`docs/agent-output/task41-acceptance-adversarial.md`）

- 1（MUST）: rb を「導出契約の回帰検査（`SessionTitleDeriver.swift` の公開面・純粋性）」と「task-41 着手時の変更範囲検査（AgentDomain 他ファイル不変）」に分け、後者は環境変数 `TASK41_SCOPE_CHECK=1` のときだけ実行する（task-41 の verify 分岐で付与。task-44/45 の回帰再検査では付与しない）。
- 2・3・4・5・8: テスト／rb 側の欠陥として Cursor に修正を委譲し、再凍結する（`String` 非 Optional のコンパイル検査と Optional 変異負例、補間内コード・属性付き import・出力/設定/時計/乱数の独立負例、4 空白除外の単独保護テスト、単一違反 selftest と期待エラー集合の厳密比較、未被覆領域（URL・長文・単独 CR・全角空白のみ・1〜3 空白フェンス・長い終了フェンス・終了フェンス後の文字・除外接頭辞に似た英語・半角カナ）の固定期待値）。
- 6（アサーション RED）: task-40 と同じ運用（凍結はコンパイル RED、実装後に変異検査）。
- 7（課金なし目視）: task-44/45 の PM 目視ゲートは `docs/agent-output/visual-task-27-35-composer.md` の sessions.json 手順（custom kind `ui-chat-probe`・`backend: appServer`・`pid` 無し→`customBinaryNotFound`→プレースホルダ、`pgrep -P` で子プロセス 0 件）を正本とする。両契約に注記する。

## 契約の曖昧点の確定（2026-09-13、`docs/agent-output/tests-task-41-r2.md` の指摘に対する PM 裁定）

1. 終了フェンスも開始と同じく行頭の半角空白 0〜3 個を許す。
2. 幅変換は Foundation の `applyingTransform(.fullwidthToHalfwidth, reverse: false)`（全角→半角）。
3. 濁点・半濁点の扱いは上記 Foundation 変換の結果に従う（独自の合成・分解はしない）。文字数は変換後の Swift `Character` で数える。
4. 極端に長い入力（10,000 文字）でも全文（`fullText`）は欠落せず保持し、`title` は最大長規則で省略する。
5. 「行の前後の空白」には U+3000（全角空白）を含む。
