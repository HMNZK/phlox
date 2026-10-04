---
status: active
last-verified: 2026-10-04
---

# ファイルのシンタックスハイライト

ファイルを読む・少し直すため、原文を保ったまま字句（文字の並び）に色を付ける。[ADR 0180](../adr/0180-syntax-highlighting-with-in-house-lexer.md) の採用済み方針。対応範囲と編集保護の基準を以下に定める。検証結果は作業記録に記載する。

## 1. 共有する部品

| 部品 | 役割 |
|---|---|
| `ChatRenderKit/ChatCodeLanguage.swift` | ファイル名・拡張子・shebang の純関数判定とフェンスの別名表。ファイルの plain と未知フェンスの Swift 互換を分ける |
| `ChatRenderKit/ChatSyntaxRules.swift` / `ChatSyntaxLexer.swift` | 言語別データと共有走査。埋め込み・CSV・diff 等は専用走査。`ChatCodeTokenizer` の既存入口から使う |
| `SessionFeature/CodeSyntaxColor.swift` | 公開部品として字句の種類から既存色へ割り当てる。チャット固有の名前の色は維持する |
| `DashboardFeature/Tabs/CodeSyntaxHighlights.swift` | 全文の背景計算・50 ms 待機・取消・最新結果の反映と属性の分割適用 |
| `DashboardFeature/Tabs/CodeTextEditor.swift` | 本文と表示属性を分け、IME・undo・選択・スクロール・typingAttributes を保護する |
| `SessionFeature/ChatCodeBlock.swift` / `ChatMessageRenderCache.swift` | チャットと変更表示で同じ規則を使う。行のキャッシュはパス・本文・テーマを含む |

検証の実行結果と性能測定値は [作業記録 0040](../delivery/0040-syntax-highlighting-worklog.md) に置く。

## 2. 種類の判定（FR-1）

判定は言語規則から独立した純関数にする。次の最初の一致を採用し、本文全体から言語を推測しない。

1. **ファイル名**: 最終要素の完全一致。`Dockerfile`・`Containerfile`、`Makefile`・`makefile`・`GNUmakefile`、`.gitignore`・`.dockerignore`・`.ignore`・`.gitattributes`、`.editorconfig`、`CMakeLists.txt`。`.env` および `.env.` で始まる名前は明示したファミリー規則（例: `.env.local`、`.env.production`）として最優先にする。ファイル名は大文字小文字を区別する。
2. **拡張子**: §3 の表。大文字小文字を区別しない。`Dockerfile.dev` / `Containerfile.dev` は `dockerfile` / `containerfile` に続く派生名としてこの段で扱う。`.h` は C/C++ の共通規則、`.m` は Objective-C、`.pl` は Perl、`.ts` は TypeScript と決める。
3. **先頭行の `#!`（shebang）**: 拡張子が未知か無い場合だけ。実行名のパス末尾を使い、`/usr/bin/env` と `env -S` の先頭の実行名も読む。`sh`/`bash`/`zsh`/`fish`、`python`/`python3`（数字の版接尾辞を含む）、`ruby`、`perl`、`php`、`lua`、`node`/`nodejs`、`pwsh`/`powershell` をそれぞれの規則へ対応させる。既に読み込み時に分離された BOM を本文へ戻さない。
4. **plain**: 未知の名前・拡張子・shebang は本文色。空ファイルも安全に扱う。

チャットのフェンス言語名は同じ規則表の別名へ対応させる。未知・未指定のフェンスを Swift として扱う現行の互換動作は今回変更しない。ファイルの plain 判定と混同しない。

## 3. 対応する種類と色付け対象（FR-2）

右欄は字句規則の最低範囲であり、厳密な構文解析は求めない。共通の色付け対象は各言語のキーワード・文字列・数値・コメント。文字列とコメントの内部をキーワードとして塗らない。

| 種類 | 拡張子・名前の例 | 色付け対象・補足 |
|---|---|---|
| Swift | swift | 共通対象、`/* */`、複数行・raw 文字列を補強 |
| Objective-C / Objective-C++ | m, mm | 共通対象、`@` キーワード・文字列、プリプロセッサ命令 |
| C / C++ | c, h, cc, cpp, cxx, hpp, hh, hxx | 共通対象、文字リテラル、プリプロセッサ命令 |
| Java / Kotlin / C# | java, kt, kts, cs | 言語別キーワード、文字・複数行文字列、注釈／属性の名前 |
| Go / Rust | go, rs | 共通対象、Go の raw 文字列、Rust の raw 文字列・文字リテラル。寿命名を文字列にしない |
| Python / Ruby / PHP | py, pyw, rb, php, phtml | 共通対象、Python の三重引用符、Ruby のシンボル、PHP の変数・開始終了タグ。PHP のタグ外は HTML |
| Perl / Lua / R | pl, pm, lua, r | 共通対象、Perl の変数、Lua の `--`・長括弧の文字列／コメント、R の言語別キーワード |
| Dart / Scala / Elixir / Haskell | dart, scala, sc, ex, exs, hs, lhs | 共通対象、Elixir の atom、Haskell の `--`・`{- -}`、各言語の複数行文字列。literate 記法はコード行だけ |
| JavaScript / TypeScript | js, mjs, cjs, ts, mts, cts | 共通対象、テンプレート文字列は全体を文字列。式の内部は解析しない |
| JSX / TSX | jsx, tsx | JS/TS に加えてタグ・属性。`{…}` 内は JS/TS の字句規則、入れ子の括弧と文字列・コメントを追跡。構文／型の解決はしない |
| シェル系 | sh, bash, zsh, fish | コマンド・オプション・変数・演算子・文字列・コメントに加え、制御キーワード。fish の語彙は分ける |
| PowerShell | ps1, psm1, psd1 | キーワード・コマンド・変数・文字列・数値・`#` / `<# #>` コメント |
| SQL / GraphQL | sql, graphql, gql | 共通対象、SQL は大文字小文字を無視。GraphQL は操作語・変数・フィールド名・三重引用符 |
| JSON / JSONC / JSON5 | json, jsonc, json5 | キー・文字列・数値・真偽値・null。JSON はコメント無し、JSONC は行／ブロックコメント、JSON5 はそれに単一引用符・非引用キーを追加 |
| YAML / TOML | yaml, yml, toml | キー・文字列・数値・真偽値・コメント。YAML のブロック文字列、TOML の節名・日時・複数行文字列 |
| INI / cfg / conf / EditorConfig | ini, cfg, conf, .editorconfig | 節名・キー・値・`#` / `;` コメント。cfg/conf は INI 風の汎用規則に固定し、製品固有の構文は推測しない |
| env / properties | .env 系, env, properties | キー・代入記号・値・引用文字列・コメント。env の変数参照、properties のエスケープと継続行 |
| plist / XML / SVG | plist, xml, svg, xsd, xsl, xslt | タグ・属性・文字列・実体参照・コメント・宣言。CDATA 内と本文は plain。plist は XML のものだけ |
| Dockerfile / Makefile / CMake | ファイル名（§2）, dockerfile, containerfile, mk, make, cmake | 命令／ターゲット・変数・文字列・コメント・数値。Docker の RUN と Make のレシピはシェルの字句規則 |
| gitignore 系 / gitattributes | §2 のファイル名 | コメント、否定記号・ワイルドカード、パターン、属性名。無視される実ファイルを調べない |
| HTML | html, htm | タグ・属性・値・実体参照・コメント。script/style 内は宣言に応じ JS/TS/JSON/CSS の規則。未知の宣言は本文色 |
| Markdown | md, markdown, mdx | 見出し・強調／リスト等の記号・リンク先・インラインコード・HTML コメント。フェンス内は言語規則、未知／未指定は本文色。先頭 front matter は YAML。mdx の JSX はタグと属性だけ |
| CSS / SCSS / Less | css, scss, less | セレクタ・プロパティ・値・数値／単位・文字列・コメント・at-rule、SCSS/Less の変数 |
| Vue / Svelte | vue, svelte | HTML のタグ・属性、script/style は上記の規則（lang 属性で ts/scss/less 等）。Vue の `{{…}}`・Svelte の `{…}` は JS/TS の字句規則。テンプレート指令はキーワード。複雑な入れ子の完全解析はしない |
| CSV / TSV | csv, tsv | 区切り記号・引用フィールド・フィールド全体が数値の値。引用内の改行・二重引用符を追跡。列の意味やヘッダーは推測しない |
| ログ | log | 行頭の日時、独立した TRACE/DEBUG/INFO/WARN/ERROR/FATAL、数値・引用文字列。本文をコードと解釈しない |
| diff / patch | diff, patch | 行頭の追加／削除、`---` / `+++` 等のヘッダー、`@@` の区間、注記。追加／削除本文の言語解析は行わない |
| Protobuf / Terraform・HCL / Nix | proto, tf, tfvars, hcl, nix | 共通対象、Protobuf の型・フィールド番号、HCL のキー・ブロック名、Nix の属性名と複数行文字列 |
| LaTeX | tex, sty, cls, bib | 命令・環境名・`%` コメント・数式の区切り・数値、BibTeX の項目型・キー・引用値 |
| plain | txt, text、判定できない種類 | 色を付けず原文を表示する |

種類が増えても、判定表・規則・色への割り当てを別々に保つ。規則の優先順位はコメント／文字列の境界を守り、識別子の一部分だけをキーワードにしない。未閉鎖の文字列・コメントでも停止し、分類したテキストを連結すると原文の UTF-8 と一致すること。

## 4. 色・適用先・対象外（FR-3〜5）

新しい色は追加しない。構造の種類は区別して保持し、表示時に既存色へ割り当てる。

判断: ダークのキーワード #FC5FA3 と文字列 #FC6A5D は Xcode の既定ダークテーマ・既存コード表示と揃えるため現状維持。

| 対象 | 既存の色 |
|---|---|
| キーワード・真偽値/null・命令／コマンド・タグ・Markdown の構造記号／フェンスの言語名・演算子・LaTeX 命令・ログレベル・CSS セレクタ・Java/Kotlin の注釈名 | `DSColor.codeSyntaxKeyword` |
| 文字列・属性値・リンク先・インラインコード・パターン・変数 | `DSColor.codeSyntaxString` |
| コメント・差分の注記 | `DSColor.codeSyntaxComment` |
| 数値・属性名・キー・節名・CSS プロパティ・日時・CSV/TSV 区切り・オプション・サブコマンド・C# の属性名・Make のターゲット・LaTeX の環境名 | `DSColor.codeSyntaxNumber` |
| diff の追加行／削除行 | 既存の `DSColor.diffAdded` / `DSColor.diffRemoved`（追加・削除の意味と既存の変更表示に合わせる） |
| diff のヘッダー／区間 | `DSColor.codeSyntaxComment` / `DSColor.codeSyntaxKeyword`。`---` / `+++` は追加・削除より先に判定 |
| 通常の本文 | ファイルは `DSColor.textPrimary`、チャットは従来の `DSColor.chatTextPrimary` |
| チャットの型名 | `DSColor.attentionInk(.question)`（ファイルは `DSColor.textPrimary`） |
| チャットのメンバー名／呼び出し名 | `DSColor.codeSyntaxNumber` / `DSColor.accentInk`（ファイルは `DSColor.textPrimary`） |

ファイル入力欄は `NSLayoutManager` の一時的な前景属性だけを変える。`NSTextStorage` の本文・フォント・段落属性に色の区間を混ぜず、次の入力で全文のフォント修復が発生することを避ける。チャットの既存の型・呼び出し・メンバー等の色とキーワードの太字、変更タブの名前を細分しない見せ方は維持する。

全文の字句計算後、最後に適用が完了した本文・種類の範囲と背景で比較し、編集した段落と種類が変わった範囲だけを表示へ反映する。待機中の実編集範囲も累積し、削除して同じ文字へ戻した範囲を比較から省かない。本文の長さが変わった後半の範囲は UTF-16 の差だけ移動して比較する。単一範囲の置換は日本語変換中も置換前後の長さを記録し、確定後の差分反映へ使う。テーマ・表示先・種類の切替、本文の全設定、複数範囲への置換、途中適用の取消では履歴を使わず全範囲を反映する。比較の履歴は適用が最後まで成功したときだけ保存する。

plain の区間は一時的な前景属性を削除して編集欄の本文色に戻す。本文色自体は既存の `textColor` とテーマ設定を使う。チャットの旧言語なし入口 `swift(_:)` は数値境界の互換性も維持する（例: `0xFF` は従来どおり `0` と `xFF` に分かれる）。ファイルの Swift と明示されたフェンスの新しい規則とは区別する。

本文色は初回に動的な `NSColor` として設定し、その解決先には現在の `DSColor.textPrimary` だけを保持する。テーマ切替は解決先の色を更新して表示を無効化し、全文の保存属性を一度に更新しない。解決先はロックで保護し、描画側から安全に読む。変換中は解決先も更新しない。色の検査は同じ色空間で解決した RGBA と画面外描画で行い、色オブジェクトの同一性と区別する。

AppKit の本文は背景計算の開始時に UTF-8 から新しい Swift 文字列へコピーして解析する。逐次的な内部表現の変換を避け、Unicode の表現と改行をバイト単位で保つ。本文側の保存値は変換しない。

- **FR-3**: ファイルタブのソース表示に適用する。`.md` / `.html` のソース表示も含め、レンダリング表示は変えない。
- **FR-4**: Markdown のブロック編集欄にも適用する。同じ `CodeTextEditor` で原文を編集するため。通常ブロックは Markdown、front matter は YAML。フェンスはブロック全体から開始状態を読み、内部のコードに対応する規則を使う。文書上の位置は維持する。
- **FR-5**: チャットのフェンスと変更タブは同じ部品の規則拡張で対応範囲が広がる。ファイル名優先の判定も変更タブへ共有し、既存の行数・複数行の状態・差分表示を保つ。

色付けをしない対象は以下。未知のテキストを開けなくする理由にはしない。

| 対象 | 扱い・理由 |
|---|---|
| バイナリ・UTF-8 でないファイル・1,000,000 バイト超 | 既存の読込制限を維持。バイナリ plist も対象外。色付けのために復号や上限を変えない |
| 巨大な minified 相当の行 | 1 行が改行を除き UTF-16 で 10,000 単位を超える文書は色付けせず本文色で編集可能にする。長い単一行の属性・レイアウト負荷を避ける。圧縮形式を拡張子だけで決めない |
| 未知の言語、設定製品ごとの方言、上表外の形式 | plain に戻す。すべてのテキストを表示できることと、すべての言語を厳密に解析することは分ける |
| 正規表現と割り算、埋め込み式、ヒアドキュメント等 | ADR 0180 の限界。字句で分かる範囲だけを色付けし、誤判定でも入力・保存を妨げない |

## 5. 編集を守る条件（NFR）

| ID | 要件・受け入れ基準 |
|---|---|
| NFR-1 入力速度 | 上限 1,000,000 バイトまで、入力処理と色付け属性適用がメインスレッドを長く占有しない。初回は全文を背景計算。編集時も全文の再計算を背景で行い、50 ms の待機で連続入力をまとめる。変更行だけの字句再計算は初版では採らない（複数行コメント・文字列の状態が後続へ波及するため）。古い計算は取り消し／破棄し、最新の本文・種類に一致する結果だけを使う。属性は変わった範囲へ適用し、必要なら処理を分ける |
| NFR-2 日本語入力 | `hasMarkedText()` 中は本文の再設定・色付け属性の更新を行わない。計算済みの結果も保留し、確定後に現在の本文で再計算する。色付け処理が `unmarkText()` を呼ばない。既存の明示的なブロック編集確定とは分ける |
| NFR-3 undo | 色付けの属性操作を undo に登録しない。入力・削除・貼り付け・ブロック確定の履歴とまとまりを保つ |
| NFR-4 選択・カーソル | 全選択範囲・挿入位置・スクロール位置を保持。UTF-16 の範囲で属性を付け、絵文字・結合文字・CRLF でずれない。色付け適用時は typingAttributes の辞書を保持し、一時表示属性によって直前のトークン色を入力へ継承させない。初回とテーマ変更時だけ基底の入力色を現在の本文色へ追従させる |
| NFR-5 テーマ | ライト／ダークの切替で現在の DSColor を解決し直す。色を含むキャッシュにはテーマを含める。変換中の切替も NFR-2 を優先し、確定後に追従する |
| NFR-6 原文・保存 | 色付けは表示属性だけ。draft・文書 version・dirty・保存バイト列を変えない。BOM・LF/CRLF/CR・末尾改行・Unicode の表現を保持。属性更新を本文変更通知として再処理しない |

**NFR-1 の測定**: 使用 Mac・OS を記録し、Release 構成で Swift・JSON・Markdown・多言語混在 × 10 KB / 100 KB / 1,000,000 バイトの12例を測る。細かいトークンと複数行文字列を含め、10回のウォームアップ後、先頭・中央・末尾で挿入／削除／貼り付けを計100回行う。入力処理と1回の属性適用はそれぞれ p95 ≤ 16 ms、入力開始から色付け完了までは p95 ≤ 150 ms。初回の同期予約・属性適用とテーマ切替の同期更新・属性適用も16 ms以下とする。未達なら実装を改善し、結果を作業記録へ残す。

操作前にカーソル・可視レイアウトと本文サイズを準備し、入力後も指定上限内で色付けされる状態を測る。計時には入力処理・表示更新を含め、位置移動・準備・完了後の原文バイト一致検査を含めない。上限超過・長行の plain 化は別に検査する。Debug の値は性能基準へ読み替えない。

## 6. テスト方針

字句・編集欄・共有表示の回帰検査を各パッケージに置く。性能測定と画像出力は専用環境変数を指定したときに実行する。実行済みの範囲は作業記録で区別する。

| 層 | 検査すること |
|---|---|
| 字句の単体テスト（AgentDomain / ChatRenderKit） | §3 の各種類の代表例と反例、別名、ファイル名→拡張子→shebang→plain の競合、空・未閉鎖・長行境界、Unicode・改行、コメント／文字列内部の抑制、連結した原文のバイト一致、複数行の状態、埋め込み領域の切替 |
| 入力欄の単体・統合テスト（DashboardFeature） | 生成・binding 更新・編集通知・種類変更・テーマ変更、古い結果の破棄、marked text の保留と確定、undo/redo、選択・スクロール・typingAttributes、保存前後のバイト一致と dirty 不変、Markdown ブロック編集と確定 |
| 共有部品の回帰（SessionFeature） | フェンス言語の対応拡張、未知言語の現行互換、チャット固有の名前分類・太字、変更タブの既存表示。既存テストをスキップ／弱化しない |
| 性能 | §5 のデータ・計測条件で入力時間と色付け時間を分けて記録。背景計算の取消と、初回・テーマ切替でメインスレッドを占有しないことも確認 |
| 見た目 | `NSHostingView.cacheDisplay` 等の画面外描画でライト／ダークを撮り、`specs/ClaudeDesign/` のソース／ブロック編集の見本（4j・4m 等）と行番号・行間・余白・選択を比較。字句の色は §4 と既存のコード表示を基準にする。見本のプレーン表示や太字を新仕様へ無条件に持ち込まない |

触ったパッケージは `~/.agents/scripts/compact-test <ラベル> swift test --package-path <パッケージ>` で全数を実行する。コード変更時のプロジェクト品質ゲートは、その worktree の設定を確認して実行する。画面外描画で本物の IME 操作まで検証したとは扱わない。必要な XCUITest は実装時に一覧を作り、`-derivedDataPath` を worktree 内にした `xcodebuild build-for-testing` のみ実行する。PM 向けに実在する `-only-testing:` 指定を報告し、ユーザーの画面を操作するテストは実行しない。
