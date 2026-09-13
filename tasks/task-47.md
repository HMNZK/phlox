---
id: task-47
difficulty: standard
depends_on: [task-46]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift
  - .claude/scripts/task47-wiring.rb
baseline_commit: "9c0ab65"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptMarkdownPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - docs/agent-output/task-47.md
---

## 目的

UX-05 / P1 のうち、回答・思考文の Markdown を描画し、思考要約から装飾を除き、コード・コマンド・出力中の記号を保護する。未閉じ記法は本契約の有限規則だけで表示用に補正する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。task-46 の表示分類・見出し・開閉・状態、task-40 の文字・余白を維持する。思考の展開本文は **Markdown 描画、body の文字体系、secondary 色**とする。

本書は敵対レビューと PM 裁定を反映した未凍結契約である。今回の改訂担当は read-only であり、ファイル保存、テスト作成・実行、ビルド、GUI 操作は行っていない。新規モデルと試験ファイルは実装予定の契約面である。

## 担当・依存・凍結

- 実装担当は Cursor。PM が Swift Testing、専用 Ruby、目視ハーネスを作成・凍結し、Cursor は変更しない。
- テストは `SessionFeatureTests` 内へ置き、App ターゲットへ追加しない。
- 契約、テスト、Ruby、検証スクリプト、台帳、目視ハーネス・記録、ADR は PM 所有であり、実装担当の `allowed_paths` 外とする。
- task-46 完了後の実コードを確認して凍結する。基準 B47 は task-46 の製品実装と task-47 の凍結テスト・Ruby・ハーネスを含み、`TranscriptMarkdownPresentation.swift` と task-47 の製品変更を含まない。
- B47 作成後に `baseline_commit` を実 SHA へ固定する。調査時 HEAD を自動採用しない。
- 未実装による RED、Ruby の `--selftest`、単一違反の検出、目視ハーネスの操作・撮影確認を凍結条件とする。新規 API 未定義によるコンパイル RED は区別して記録し、実装後の変異検査を必須とする。

### 分割しない理由と先行契約

思考要約と表示用補正は同じ `ReasoningSummaryView` の入口を共有し、コード保護と Markdown 本文への接続を同時に確認する必要がある。別契約へ分けると同じ入口の凍結が1回増えるため、PM 裁定により task-47 は分割しない。要約・補正・分割・配線のテストは独立した期待値を持たせ、片方の成功で他方の失敗を隠さない。

task-40 の Ruby 残余比較は task-40 完了時点の着手時範囲検査であり、後続変更へ適用しない。task-47 自身の Ruby で `TranscriptTypography` 参照の維持を検査する。

ADR 0147 の「見出しはコマンド」「補足は常に nil」「思考の見出しと本文が同一なら折り畳まない」は、task-46 が列挙した新決定へ置き換える。task-47 はその決定を維持する。後継 ADR の起草・関連文書反映は PM がフェーズ5で行う。

## 調査結果

以下の `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`。既存草案・敵対レビューの行番号を再利用しており、凍結時の位置ではない。

| 実ファイル・シンボル | 調査した挙動 |
|---|---|
| `SF/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | キャッシュの分割結果を通常初期化の `RichMarkdownView`／`CodeBlockView` へ渡す |
| `SF/RichMarkdownView.swift:14`・`:18` | 通常・`streaming:` の両初期化で入力をそのまま保持 |
| 同`:52` | Markdown テーマ本文色は primary 固定。外側の secondary 指定だけでは上書きを保証できない |
| `SF/ChatTranscriptFormatting.swift:10` | trim 後の3バッククォート接頭辞で開閉し、長さの対応を判定しない |
| 同`:18`・`:31` | Markdown 端の改行 trim と `.newlines` 分割があり、改行・空行保護の変更対象 |
| `SF/ChatMessageCells+Structured.swift:192` | 調査時の思考本文は `Text` 描画 |
| `SF/ChatMessageRenderCache.swift:66` | 入力文字列をキーとして分割結果を取得 |
| `AgentDomain/Sources/ChatRenderKit/ChatToolPresentation.swift` | `ChatReasoningPresentation` は `ThinkingRecap` に要約を委譲 |
| `AgentDomain/Sources/AgentDomain/ThinkingRecap.swift` | 見出し・末尾行抽出であり、本契約の Markdown／コード判定ではない |
| `DashboardFeature/Tests/DashboardFeatureTests/ChatTranscriptFormattingTests.swift` | 通常フェンスと、未閉じフェンスを Markdown へ戻す固定期待値 |

思考の直接 `Text` 経路と未閉じ入力の無補正経路は確認した。仕様画像の記号露出の原因、MarkdownUI の個別入力に対する実描画結果は本改訂では未検証であり、ライブラリの不具合と断定しない。

## 入出力契約

### 純粋な表示処理

`TranscriptMarkdownPresentation.swift` に次を置く。

```swift
enum TranscriptMarkdownPresentation {
    static func prepare(_ source: String) -> String
    static func summary(_ source: String) -> String?
}
```

同期的な純粋処理とし、毎回その入力から導出する。前回結果への追記、同じ文字数を根拠にした再利用、ViewModel・設定・I/O・時計への依存を追加しない。標準ライブラリ・Foundation・既存依存を使い、新規ライブラリやパッケージを追加しない。

### 改行と原文保護

- 表示処理と分割処理は CRLF／単独 CR を LF へ正規化してよい。本契約の CR を含む固定期待値は LF 正規化を採用する。
- それ以外のタブ、字下げ、行末空白、末尾空行は UTF-8 バイトを保持する。全文 trim やタブの空白展開をしない。
- 保存、エクスポート、メッセージ全文コピーは元の `ChatItem` 原文を維持する。表示用に正規化した文字列へ差し替えない。
- コードカードのコピーは、分割で抽出したコード本文と一致させる。CRLF／CR→LF の許容以外に字下げ・空行・記号を変えない。
- 以下の `\n`、`\r`、`\t` はそれぞれ実際の改行・CR・タブを表す。`\"` は文字列内の引用符である。

## `prepare` の有限規則

### 保護領域

閉じた／未閉じのバッククォート・チルダフェンス、インデントコード、インラインコードを先に識別し、その内部は補正しない。

- フェンスの開始は行頭の半角空白0〜3個の後に、同じ文字のバッククォートまたはチルダが3個以上。
- 終了は同じ文字種・開始以上の長さで、後ろが空白かタブだけの行。終了行も半角空白0〜3個を許す。
- 4空白またはタブ字下げのコード行を通常文章として補正しない。
- インラインコードは開始と同じ長さのバッククォート run で閉じる。短い内部 run を閉じとしない。未閉じのインライン開始以後も、その物理行末までは保守的に保護する。
- エスケープされた区切りを開始・終了として使わない。

### 補正対象

対象区切りは `**`、`*`、`__`、`_` の4種類。`~~`、リンク、括弧、見出し、任意の壊れた Markdown は修復しない。

1. 空行で区切った段落の**最終物理行**に開始があり、その行末まで閉じがない強調だけを対象にする。補正範囲は改行を跨がない。
2. 開始は行頭または空白・タブの直後。開始直後に空白でない本文文字が必要。識別子内部の `_`、演算子、単独の区切り run は対象外。
3. `**`／`__` を `*`／`_` より先に認識する。3個以上連続する同種 run は曖昧な入力として補正しない。
4. 同じ行の閉じた強調はそのまま保持する。閉じた強調の後に別の未閉じ強調があれば、後者だけを補正する。
5. 入れ子は最外の未閉じ強調だけを補正する。内側の未閉じ強調を再帰的に修復しない。既に閉じた最外強調の内部も再補正しない。
6. 閉じ記号を行末空白・タブの直前に補う。二重区切りの末尾に同種1文字の閉じ途中がある場合は、不足する1文字だけ補う。
7. 補正対象外は、許可した改行正規化を除いて入力不変。
8. `prepare(prepare(source)) == prepare(source)` を満たす。

旧草案の単独 `"**"` と `"## "` を空文字列へ変える規則は採用しない。本文のない区切りや見出しは有限な未閉じ強調補正の対象外とし、`prepare` では保持する。要約が空になるかは `summary` が別に判定する。

### 固定期待値

````text
prepare("**確認済み**")       == "**確認済み**"
prepare("## **確認結果**")    == "## **確認結果**"
prepare("**確認")             == "**確認**"
prepare("*確認")              == "*確認*"
prepare("__確認")             == "__確認__"
prepare("_確認")              == "_確認_"
prepare("説明 **確認")        == "説明 **確認**"
prepare("説明 *確認")         == "説明 *確認*"
prepare("説明 __確認")        == "説明 __確認__"
prepare("説明 _確認")         == "説明 _確認_"
prepare("**確認*")            == "**確認**"
prepare("__確認_")            == "__確認__"
prepare("**済み** と *確認")   == "**済み** と *確認*"
prepare("**外 *内")           == "**外 *内**"
prepare("**外 *内**")         == "**外 *内**"
prepare("**確認  \t")         == "**確認**  \t"

prepare("**確認\n次行")       == "**確認\n次行"
prepare("前行\n**確認")       == "前行\n**確認**"
prepare("**確認\n\n次段")     == "**確認**\n\n次段"
prepare("**確認\n\n")         == "**確認**\n\n"

prepare("**")                == "**"
prepare("*")                 == "*"
prepare("__")                == "__"
prepare("_")                 == "_"
prepare("## ")               == "## "
prepare("***確認")           == "***確認"
prepare("___確認")           == "___確認"
prepare("説明**確認")         == "説明**確認"
prepare("a * b")             == "a * b"
prepare("2 ** 3")            == "2 ** 3"
prepare("foo_bar")           == "foo_bar"
prepare("C#")                == "C#"
prepare("##tag")             == "##tag"
prepare("\\*\\*literal\\*\\*") == "\\*\\*literal\\*\\*"
prepare("~~未閉じ")          == "~~未閉じ"
prepare("[未閉じ](url")      == "[未閉じ](url"
prepare("`**未閉じ`")        == "`**未閉じ`"
prepare("`**未閉じ")         == "`**未閉じ"
prepare("    **未閉じ")      == "    **未閉じ"
prepare("\t**未閉じ")        == "\t**未閉じ"
prepare("```\n**未閉じ")     == "```\n**未閉じ"
prepare("~~~\n**未閉じ")     == "~~~\n**未閉じ"
prepare("説明\r\n**確認\r\n\r\n") == "説明\n**確認**\n\n"
````

正常な見出し・太字・斜体・箇条書き・引用・リンク・表は改行正規化を除いて入力不変とする。`"**確"` → `"**確認"` → `"**確認**"` の各原入力から結果を作り、同長の `"**確認"` → `"**更新"` では `"**更新**"` を返す。

## `summary` の候補と固定期待値

### 候補形式

1. コード領域を除き、ATX 見出しを優先する。半角空白0〜3個、`#` が1〜6個、その後に空白・タブまたは行末があるものを見出しとする。
2. 見出し末尾の閉じ `#` run は、直前に空白がある場合だけ装飾として除く。`##tag` は通常文章行、7個以上の `#` は見出しではない。
3. 最後の見出しから逆順に探し、装飾除去後に非空となる最初の見出しを使う。空の最終見出しから前の見出しへ遡る。
4. 有効な ATX 見出しがなければ、最後の通常段落の最後の非空文章行を使う。空になった候補は前の文章行へ遡る。
5. Setext 見出しは候補外。その本文行と下線行を一組として除外する。箇条書き・番号付きリスト・引用・表・水平線も候補外。各ブロックの継続行を通常文章へ混入させない。
6. 通常段落のインライン装飾は段落単位で解釈する。改行を跨ぐ完結した強調・リンクも解釈し、表示テキストの改行を保持した後で最後の非空文章行を選ぶ。リンク先内部の改行は表示テキストへ加えない。
7. 見出し記号、強調、取り消し線の装飾を除き、リンクは表示名を残す。エスケープは表示上の文字へ戻す。
8. インラインコードは区切りだけを除く。内部の `**`・`##`・短いバッククォート等は保持する。
9. 未閉じ強調は `prepare` の有限規則で補正できるものだけ補正してから解釈する。任意の記号を一括削除しない。
10. 候補の前後の空白を除き、装飾解釈後の Swift `Character` で先頭60文字へ制限する。61文字以上なら60文字の後に `…`。候補がなければ `nil`。
11. 入力原文を変更しない。思考要約にだけ使い、コマンド・診断・共通タイトルへ接続しない。

### 固定期待値

````text
summary("**確認済み**")                     == "確認済み"
summary("**確認")                           == "確認"
summary("# 一")                            == "一"
summary("## 二")                           == "二"
summary("### 三")                          == "三"
summary("#### 四")                         == "四"
summary("##### 五")                        == "五"
summary("###### 六")                       == "六"
summary("## **確認結果**")                 == "確認結果"
summary("## 前\n## 後\n本文")               == "後"
summary("## 有効\n## ")                    == "有効"
summary("## **有効**\n## ~~ ~~")            == "有効"
summary("本文\n## ")                       == "本文"
summary("## ")                            == nil
summary("## 確認 ###")                     == "確認"
summary("## C#")                           == "C#"
summary("##tag")                           == "##tag"
summary("####### 見出し外")                 == "####### 見出し外"

summary("一行目\n二行目")                   == "二行目"
summary("タイトル\n====")                   == nil
summary("残す\n\nタイトル\n----")           == "残す"
summary("- 項目")                          == nil
summary("1. 項目")                         == nil
summary("> 引用")                          == nil
summary("| A | B |\n| --- | --- |\n| x | y |") == nil
summary("本文\n\n- 項目")                  == "本文"
summary("本文\n\n> 引用")                  == "本文"
summary("## 見出し\n\n| A | B |\n| --- | --- |") == "見出し"

summary("**前\n後**")                       == "後"
summary("[前\n後](https://example.com)")    == "後"
summary("[詳細](\nhttps://example.com)")    == "詳細"
summary("[詳細](https://example.com/a#b)")  == "詳細"
summary("~~古い~~")                        == "古い"
summary("`**x** ## y`")                    == "**x** ## y"
summary("``a ` b **c**``")                 == "a ` b **c**"
summary("\\*literal\\*")                   == "*literal*"

summary("```\n## コード\n```")             == nil
summary("```\n**未閉じ")                   == nil
summary("~~~\n## コード\n~~~")             == nil
summary("    ## コード")                   == nil
summary("\t## コード")                     == nil
summary("文章\n\n```\n## コード\n```")       == "文章"
summary("")                               == nil
summary(" \t\n")                          == nil
````

60文字境界は ASCII だけで済ませない。PM は次の6個のリテラル文字列を連結した60 `Character` の入力・同一期待値を試験へ固定し、末尾に `"追"` を足した61文字の期待値を同じ60文字＋`"…"` として固定する。

```text
"あいうえおかきくけこ"
"さしすせそたちつてと"
"なにぬねのはひふへほ"
"まみむめもやゆよわを"
"0123456789"
"Ae\u{301}👨‍👩‍👧‍👦BCDEFGH"
```

結合文字 `e\u{301}` と家族絵文字をそれぞれ1 `Character` として数え、Unicode 正規化で原文表現を変更しない。期待値を製品の切り詰め関数から作らない。

## フェンス分割とコード保護

`ChatMarkdownFormatter.splitFencedCodeBlocks` と `ChatMarkdownBlock` の既存 API を維持する。

- バッククォートフェンスは文字種・長さを記録して分割する。短い終了候補、別文字種、後ろに文字がある候補では閉じない。
- バッククォート開始行の情報文字列にバッククォートが含まれる場合、その行を開始フェンスとして扱わない。
- チルダフェンスは独自の `.code` へ分割せず、まとまった `.markdown` として MarkdownUI へ渡す。内部のバッククォートを別の開始と解釈しない。
- 0〜3空白の開始・終了を許し、4空白／タブ字下げはインデントコードとして `.markdown` に残す。
- `.code.text` は開始行と終了行の間の本文行を LF で連結した値。開始・終了フェンス行は含めない。本文の字下げ・タブ・行末空白・空行を trim しない。
- 開始／終了行を分ける改行はフェンス構造の区切りである。本文中の空行に対応する改行は保持する。
- `.markdown` に残るコードは、その字下げ・末尾空行を保持する。
- 未閉じバッククォートフェンスを `.markdown` へ戻す既存契約を維持する。3本・字下げなしの既存言語表記の正規化だけを互換例外とする。
- 3空白字下げ、4本以上、チルダの未閉じ開始行を、3本・字下げなしへ書き換えない。
- 分割後の未閉じ `.markdown` も `prepare`／`summary` がコードとして保護する。

以下で `M(s)` は `.markdown(s)`、`C(lang,s)` は `.code(language: lang, text: s)` を表す。テストでは実 enum 値との等値比較と本文 UTF-8 比較を行う。

````text
split("Before\n```json\n{\"ok\": true}\n```\nAfter")
== [M("Before"), C("json","{\"ok\": true}"), M("After")]

split("Before\n```json\n{\"ok\": true}")
== [M("Before"), M("``` json\n{\"ok\": true}")]

split("```swift\n\t  **x  \n\n```")
== [C("swift","\t  **x  \n")]

split("   ```swift\n\t  **x  \n\n   ```")
== [C("swift","\t  **x  \n")]

split("    ```swift\n    **x  \n\n    ```\n\n")
== [M("    ```swift\n    **x  \n\n    ```\n\n")]

split("\t```swift\n\t**x\n\t```\n\n")
== [M("\t```swift\n\t**x\n\t```\n\n")]

split("```swift\r\n\t  x  \r\n\r\n```")
== [C("swift","\t  x  \n")]

split("```swift\r\t  x  \r\r```")
== [C("swift","\t  x  \n")]

split("```json\n**x\n\n")
== [M("``` json\n**x\n\n")]

split("   ```json\n  **x\n\n")
== [M("   ```json\n  **x\n\n")]

split("````json\n```\n**x\n\n")
== [M("````json\n```\n**x\n\n")]

split("````\na\n```\nb\n````")
== [C(nil,"a\n```\nb")]

split("```\na\n~~~\nb\n```")
== [C(nil,"a\n~~~\nb")]

split("```\na\n```text\nb\n```")
== [C(nil,"a\n```text\nb")]

split("```\na\n````")
== [C(nil,"a")]

split("```\na\n    ```\nb\n```")
== [C(nil,"a\n    ```\nb")]

split("~~~\n```\n**x\n~~~\n\n")
== [M("~~~\n```\n**x\n~~~\n\n")]

split("~~~\n**x\n\n")
== [M("~~~\n**x\n\n")]

split("本文\r\n\r\n")
== [M("本文\n\n")]
````

0空白と3空白フェンスの `.code.text` とコピー対象は、どちらもリテラル `"\t  **x  \n"`。4空白・タブの例は `prepare` へ渡しても改行正規化以外に不変、`summary` は `nil`。

既存未閉じフェンス期待値を変更して検査を通さない。末尾空行を含む追加期待値は既存の不足を補うものであり、コード本文の trim を互換仕様として固定しない。

## 実 View と本文色の配線

### 回答

- `AgentMessageBody` → `ChatMessageRenderCache.markdownBlocks` → `RichMarkdownView`／`CodeBlockView` の経路を維持する。
- 補正は `RichMarkdownView` の通常・`streaming:` 両入口へ接続し、戻り値が実際の `Markdown` 入力へ届くようにする。
- `AgentMessageBody` に本文色を表す限定引数を追加する。既定は primary で、既存の `AgentMessageBody(text:)` 呼び出しを維持する。
- Markdown ブロックへ本文色を渡す。コードブロック、コピー値、キャッシュキー、分割元入力は変更しない。

### 思考

- task-46 完了後の `ReasoningSummaryView` で `summary(text)` を補足へ渡す。
- 展開本文へ要約ではなく原文 `text` 全体を渡し、secondary 本文色を指定した `AgentMessageBody` で描画する。
- 短文も同じ経路。生の `Text` へ逃がす分岐を残さない。
- 要約 `nil` の非空コード思考も「思考の詳細」を表示し、展開本文へ到達できる。
- task-46 の既定閉・見出し・空判定・開閉保持を維持する。保持は同じセルが表示階層に残る更新だけ。非空・開 → 空白 → 非空では再表示時に閉じる。

### `RichMarkdownView` の限定変更

本文色は primary／secondary の2役割に限定し、既存引数を省略できる既定値を持たせる。任意テーマ設定や新規ユーザー設定へ広げない。

- 通常・`streaming:` の両初期化、テーマ生成、テーマキャッシュキーへ本文色の役割を渡す。
- 同じ theme ID・倍率でも primary と secondary のキャッシュを混同しない。
- `.text` の通常本文色と、primary を固定していた見出し色へ渡す。思考の見出しも secondary 系の本文色として描画する。
- body のサイズ、見出しのサイズ・ウェイト、`TranscriptTypography` の行間・余白を維持する。
- リンク、インラインコード、コードブロック、引用帯、コピー操作の専用色・処理は既存を維持する。思考の secondary 指定で構文ハイライトを一括上書きしない。
- 外側の `.foregroundStyle(.secondary)` だけで内部 primary 指定を残す実装は不合格。

`prepare`／`summary` をコマンド、出力、差分、エラー診断、ユーザー本文へ接続しない。`ThinkingRecap`／`ChatReasoningPresentation` の共有実装は変更しない。

## 変更境界と不変条件

- `ChatMessageCells+Basic.swift` は `AgentMessageBody` の本文色引数と Markdown ブロックへの転送だけを変更する。他のセル・コピー・コード分岐は保護する。
- `ChatMessageCells+Structured.swift` は `ReasoningSummaryView` の要約式、本文 Markdown 接続、本文色転送、不要な局所変数の除去だけを変更する。
- 同ファイルのコマンド、差分、サブエージェント、処理中、経過、無応答、中断の宣言は変更しない。
- `RichMarkdownView` は補正入口と本文色の限定配線を変更し、リンク処理、折り返し保護、キャッシュの既存性質、コードコピーを保持する。
- 表・表セルへ `fixedSize` を追加しない。非表本文・見出し・箇条書きの折り返し高さ保護を削除しない。
- ID、順序、表示窓、描画予算、スクロール追従、既存キャッシュキーを保持する。
- コマンド50件・出力20行・差分500行の追加表示と、質問・承認・中断・移動を保持する。
- 保存、エクスポート、クライアント、起動・復元、パッケージ依存を変更しない。
- 描画中の状態更新、`LazyVStack`、非同期ハイライト、無制限キャッシュ、製品用デモモードを追加しない。

task-46 との交差は Basic と Structured の2ファイルであり、依存順で逐次化する。ファイル全体を比較対象から外さず、上記構造だけを変更可能にする。

## 受け入れテスト

### Swift Testing

PM は本契約の `prepare`、`summary`、分割結果を独立したリテラル期待値として凍結する。製品処理の出力から期待値を生成しない。

加えて次を検査する。

- 補正対象4区切り、対象外、部分閉じ、改行境界、閉じた強調との混在、最外だけの補正。
- 固定入力に対する冪等性と元入力の不変。
- 見出しの遡及、候補外ブロック、複数行インライン装飾、60／61 `Character`。
- 分割後の `.markdown` を `prepare` へ渡しても、未閉じコードの内部を補正しない。
- コード本文・コードコピー対象の UTF-8、CRLF／CR 正規化、タブ・字下げ・末尾空行。
- `ChatMessageRenderCache.markdownBlocks` へ同長別内容を渡しても取り違えない。
- 同じ theme ID・倍率に対する primary／secondary のテーマキャッシュキーは異なる。同じ役割の再呼び出しは同じキー。
- 明暗・倍率変更でも本文色の役割を維持する。キーの不一致だけを色の実描画確認と読み替えない。
- task-46 の分類・コマンド表・開閉テストを恒久回帰として再実行する。

### Ruby：固定 SHA・着手時範囲・恒久回帰

PM が `.claude/scripts/task47-wiring.rb` を作成する。task-41 と同じ二段階方式にし、task-46 の Ruby へ task-47 固有検査を混在させない。

**常時実行する凍結検査：**

- `TASK47_BASELINE` は明示 SHA 必須。契約の `baseline_commit` と完全 SHA で一致し、現在の履歴の祖先であること。
- 未設定、プレースホルダ、`HEAD`、`HEAD~1`、`@`、ブランチ名、無効コミット、非祖先を拒否する。
- B47 に task-46 完了状態があり、`TranscriptMarkdownPresentation.swift` が存在しないこと。確認対象は PM が凍結時に固定する。
- `acceptance_tests` の Swift・ハーネス・Ruby 自身を B47 の blob とバイト比較する。
- blob 取得失敗、必要ファイル不在、解析不能は非ゼロ終了。新規製品ファイル不存在と Git 障害を区別する。
- 明示 SHA と実装前 HEAD の一致は許す。実装後 HEAD への差し替え、HEAD 自己比較、HEAD へのフォールバックは禁止する。

**`TASK47_SCOPE_CHECK=1` のときだけ実行する着手時の変更範囲検査：**

- B47 からの変更が許可ファイルと上記の限定構造内であること。
- Structured の他宣言、Basic の `AgentMessageBody` 以外、共通操作等を B47 の blob と比較する。
- RichMarkdownView の許可した入口・本文色・キャッシュキー以外を構造単位で保護する。
- task-47 の実装・完了時だけ実行し、後続タスクの通常回帰へ持ち込まない。

**環境変数なし／`TASK47_SCOPE_CHECK=0` の恒久回帰検査：**

- 回答の通常・`streaming:` 両入口で `prepare` の戻り値が `Markdown` へ届く。
- 思考の補足へ `summary(text)`、本文へ原文全体が届く。
- 思考本文色が `AgentMessageBody` → `RichMarkdownView` → テーマまで secondary として届く。
- 回答の既定 primary、色役割を含むキャッシュキー、コード・リンクの専用処理が維持される。
- 短文の直接 `Text`、要約だけの本文、`nil` 要約による非空思考の非表示を拒否する。
- コード、コマンド、出力、差分、診断、コピー原文への補正流入を拒否する。
- task-46 の空判定・見出し・開閉・状態配線を維持する。
- `TranscriptTypography` の実フォント・余白・行間参照を維持する。文字列や未使用参照だけでは合格にしない。
- リンク・非表折り返し保護・コピー等の恒久不変部分を B47 の構造単位の blob 比較で保護する。着手時の全面残余比較を混在させない。

コメント・文字列中の名前、未使用関数、`if false`、結果を捨てる呼び出しを接続と認めない。正規化はコメントと文字列外空白に限定し、文字列内容・補間内の実コードを消さない。

`--selftest` は実ファイルを変えず本番検査関数を使い、正常 fixture と次の単一違反 fixture の期待エラー集合を照合する。

- 通常入口／streaming 入口未接続、補正結果未使用、短文直接表示、要約だけの本文。
- secondary 転送欠落、テーマ本文 primary 固定、色役割のキャッシュキー欠落、回答既定色の変更。
- コードへの補正、コピー変更、開閉リセット、空判定変更、保護宣言変更、typography 退行。
- 凍結 Swift・ハーネス・Ruby 改変、基準不正・不一致・非祖先・実装済み基準・blob 取得失敗。
- scope だけの範囲違反は `1` で失敗し、恒久契約を守った変更なら scope なしで成功する。
- 恒久契約違反は scope の有無にかかわらず失敗する。

必要な負例をスキップしない。

## 品質ゲート

正本は `.claude/verify.sh` と `macos/scripts/run-swift-tests.sh`。調査した verify は8パッケージ、更新隔離検査、差分の空白検査を実行する。PM が task-47 検査と task-46 恒久回帰を接続する。

task-46 の回帰では `TASK46_SCOPE_CHECK=0`、task-40 の着手時残余比較は実行しない。

以下は実装時の手順であり、本改訂では未実行。

```sh
~/.agents/scripts/compact-test task47-selftest ruby .claude/scripts/task47-wiring.rb --selftest
~/.agents/scripts/compact-test task47-scope env TASK47_BASELINE=<B47> TASK47_SCOPE_CHECK=1 ruby .claude/scripts/task47-wiring.rb
~/.agents/scripts/compact-test task47-regression env TASK47_BASELINE=<B47> TASK47_SCOPE_CHECK=0 ruby .claude/scripts/task47-wiring.rb
~/.agents/scripts/compact-test task47-task46-regression env TASK46_BASELINE=<B46> TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task47-integration bash .claude/verify.sh
```

App ビルドは `macos` ディレクトリで実行する。

```sh
~/.agents/scripts/compact-test task47-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用の絶対パス> -destination platform=macOS build
```

PM は凍結前にパッケージ・App・検証・lint・型チェック・静的解析設定を再確認する。既存 `ChatTranscriptFormattingTests` を維持する。先行検査と許可変更が衝突した場合は PM が検査の責務を修正して再凍結し、Cursor に期待値の弱体化を行わせない。

Swift テスト、Ruby、ビルド、目視を区別し、警告・失敗・未設定・実行不能・未検証を記録する。

## 課金なしの PM 目視ゲート

実 claude／codex／cursor の起動・送信・課金セッションを要求しない。

### ハーネスと凍結前の実行確認

PM は `PMTranscriptVisualTask47Tests.swift` を作成する。task-46 のハーネスを参照・再利用できるが、task-46 の凍結済みテストは変更しない。

- `SessionFeatureTests` 内の Swift Testing、`NSWindow`、`NSHostingView` を使い、製品へテスト用モード・setter を追加しない。
- `StructuredAgentClient` の double と `AsyncStream<NormalizedChatEvent>` を VM へ注入し、公開開始経路で購読を開始する。
- `.turnStarted`／`.turnCompleted(nativeSessionId: nil)` を注入し、実 `status.isRunning` の true→false を確認する。
- 追記は実イベント、同長置換・空白置換は安定したハーネスモデルの transcript 更新で再現してよい。後者も実行状態は VM のイベント経路を使う。
- 同一 ID 更新中は VM・ホスト・ルート identity を保持する。ホスト再生成で開閉保持を検査したことにしない。
- 専用 `UserDefaults(suiteName:)` にテーマ・倍率キーを設定し、`.defaultAppStorage(suite)` をルートへ注入する。明暗 appearance も設定する。
- `ComposerLayout.transcriptContentMaxWidth(mainColumnWidth:)` と製品相当のコンポーザ高さによる `bottomScrollContentMargin` を使い、末尾まで操作する。
- 同じ画面に primary の回答と secondary の思考本文を並べ、同じテーマ・倍率でキャッシュが混同されないことを確認する。
- PM が凍結前に起動コマンド、操作可能なウィンドウ、イベント遷移、同一 ID 更新、AppStorage 反映、スクリーンショット保存、終了処理を実行確認する。旧表示の不足は不足として記録する。

通常実行では固定シナリオを自動検査して終了する。`PHLOX_PM_VISUAL_TASK=47` では操作用ウィンドウを保持し、PM のハーネス終了操作で閉じる。環境変数はテスト専用とし、受け入れアサーションをスキップしない。

```sh
~/.agents/scripts/compact-test task47-pm-visual env PHLOX_PM_VISUAL_TASK=47 bash macos/scripts/run-swift-tests.sh SessionFeature
```

### 実装後の確認

- 見出し・太字・斜体・箇条書き・リンク・引用・表を含む回答。
- `"**確"` → `"**確認"` → `"**確認**"` と同長別内容への置換。
- 4種類の未閉じ強調、改行を跨ぐ対象外、最外だけの補正。
- 空の最終見出しから前の見出しへ遡る思考要約。
- 短文・長文思考の既定閉、装飾除去済み要約、展開本文の Markdown と secondary 色。
- 要約 `nil` のコードだけの思考を開いて全文へ到達。
- 同一 ID・表示継続中の開閉保持と、空白を挟む再表示時の既定閉。
- 0／3／4空白、タブ、3／4バッククォート、チルダ、未閉じ、インライン、CRLF／CR、末尾空行のコード。
- コード・コマンド・出力・診断中の `**`・`##`・パス・演算子と、コピー原文。
- task-46 の単体／1件グループの差、件数、最新／過去の実行中補足。

幅360／720pt × 倍率0.8／1.0／2.0 × 明暗テーマで、重なり・切れ・操作不能を確認する。正常な Markdown の装飾記号が不意に露出する、コード記号・空白が欠落する、コピー原文が変わる、更新後に旧内容が残る、思考本文が primary になる場合は不合格。

復元失敗プレースホルダは実 App の到達性・エラー表示の補助証拠に限る。回答・思考 Markdown・状態遷移の検証へ読み替えない。

PM は `docs/agent-output/visual-task-47.md` にコミット、起動コマンド、入力・イベント、ID、幅、末尾余白、倍率、テーマ、操作、画像、合否、未検証項目を残す。必要な表示を再現できなければ目視ゲート未達とし、課金セッションで代替しない。

終了時はホスト、stream、VM 購読を閉じ、専用 defaults suite を清掃する。作業で起動したプロセスの親子関係を確認し、不要なものだけ終了して `ps` で残存確認する。リリース版・共有プロセスは停止しない。

## レビュー観点と完了条件

- 補正・要約・分割それぞれが有限規則と独立した固定期待値を満たす。
- 正常な Markdown と、コード・コピー原文を保護する。
- 改行正規化と、タブ・字下げ・末尾空行の保持を区別する。
- 通常／streaming の両入口、思考要約、原文本文へ接続されている。
- secondary が本文色引数・テーマ・キャッシュまで届き、回答は primary を維持する。
- task-46 の分類・見出し・開閉・状態と task-40 の文字体系を維持する。
- scope 検査と恒久回帰が分離され、凍結 blob と単一違反 selftest が機能する。
- 凍結テストを実装担当が変更せず、必須品質ゲート・独立レビュー・課金なし PM 目視が成立する。
- 未検証・失敗・警告を記録し、PM がフェーズ5で ADR 0147 の後継決定と関連仕様を反映する。

旧単一草案を第三の実装契約として併用しない。UX-05 の完了には task-46・task-47 の検査、独立レビュー、PM 目視、フェーズ5の文書反映を必要とする。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task47-acceptance-adversarial.md` を PM 裁定）

- MUST1（基準に task-46 実装が無い）: 採択（工程）。task-46 done 後に再凍結し、基準検査は分類・開閉の実配線を確認する。
- MUST2（`AgentMessageBody` 内の `ChatFontSettings.adjusted` 要求が task-46 契約と衝突）: 採択。倍率は `RichMarkdownView`／`CodeBlockView` の実適用箇所で検査し、正例は実物から作る。
- HIGH3〜9: 採択（secondary 転送とキャッシュキーの実使用、`prepare`／`summary` の入口ごとの原入力→戻り値→描画先対応、許可構造以外の残余比較と保護領域、折り返し・リンク・コピー・表セル `fixedSize` 禁止・専用色の構造比較、必須ファイル欠落と git 障害の区別、PM ハーネスは実カード操作で既定閉→展開→同一 ID 更新→空白→再表示を表示状態で照合、完全な回答への復元操作・真正の同長更新・実イベント追記・コード境界／最新コマンドの固定シナリオ）。
- HIGH10（テーマが standard を書き換える）: PM 裁定。ハーネスは `UserDefaults.standard` の永続値を書き換えない。テーマ差はハーネスでは扱わず、PM 目視ゲートで起動引数（`-phlox.theme`）により確認する（task-40 ゲート A と同方式）。
- MED11〜15: 採択（未被覆領域のリテラル追加、`prepare`／`summary` 実結果の固定 UTF-8 比較、selftest の 1 違反 1 集合と本番区切り行の独立抽出、製品と同じ overlay 構成と高さ追随、ハーネス内型のアクセス範囲統一）。
