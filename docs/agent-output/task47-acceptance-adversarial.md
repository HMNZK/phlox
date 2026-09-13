現状の凍結内容は差し戻しが必要です。Swift 2 ファイルと Ruby は `eb04e86` の blob とバイト一致しましたが、基準コミットと配線検査に欠陥があります。以下は実ファイルの静的確認結果です。Swift・Ruby の実走、変異検査、GUI は **unverified**（read-only 環境と、一時ファイルを必要とする必須テストラッパーの制約）。指定された報告書は未読、ファイル変更はありません。

## MUST

### 1. B47 に必要な task-46 実装が存在しない

- **該当行（実ファイル確認済み）:** [契約34行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-47.md:34)、[Ruby550–553行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:550)。`eb04e86` の `ChatMessageCells+Structured.swift:202–219` は旧 `ReasoningPresentation`／短文直接表示。
- **理由:** `git ls-tree` で B47 の `TranscriptItemPresentation.swift` 不在を確認。task-47 を正しく実装しても、固定された基準を理由に Ruby が失敗する。新規 task-47 型による正常なコンパイル RED とは別問題。
- **修正案:** task-46 統合後の実コードで再凍結する。基準検査も、ファイルの存在だけでなく分類・開閉の実配線を確認する。

### 2. 契約どおりの `AgentMessageBody` を typography 違反にする

- **該当行（実ファイル確認済み）:** [Ruby651–654行・857行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:651)、[実View184–200行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift:184)、[契約360行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-47.md:360)。
- **理由:** Ruby は `AgentMessageBody` 内の `ChatFontSettings.adjusted` を要求する。しかし実Viewは文字倍率を子Viewへ委譲し、task-46 契約172行もこの宣言の変更を禁止している。本文色引数と転送だけの正しい変更では合格しない。自己検査の正例1145–1147行は、実物にない未使用の倍率計算を追加している。
- **修正案:** 実物から作った正例を使い、倍率は `RichMarkdownView`／`CodeBlockView` の実適用箇所で検査する。

## HIGH

### 3. secondary の転送と実キャッシュ利用を保証していない

- **該当行（実ファイル確認済み）:** [Ruby704–716行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:704)、[792–810行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:792)、[Swift439–495行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:439)。
- **理由:** `RichMarkdownView(markdown, bodyColor: DSColor.chatTextPrimary)` への固定化、初期化時の色引数無視、見出しだけ primary 固定を区別できない。`themeCacheKey` 関数が正しくても、実際の `theme` が旧キーを使う変更は検査対象外。Swift もキー関数を直接呼ぶだけ。
- **修正案:** 引数保存→Markdown 呼び出し→テーマ→本文・各見出し、およびキャッシュの読書きに使うキーまで個別に検査する。各接続の単独欠落を負例にする。

### 4. `prepare`／`summary` の名前の存在を、正しい値の接続と誤認する

- **該当行（実ファイル確認済み）:** [Ruby698–701行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:698)、[723–764行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:723)。
- **理由:** `prepare("")` でも入力接続条件を満たす。通常・streaming の結果消費はまとめて検索され、片方の正しい代入が他方の不備を隠す。要約も `summary(text)` と `summary:` の共存を許し、実際にその引数へ戻り値が渡ることを保証しない。
- **修正案:** 各入口を独立して、原入力・戻り値・描画先の対応を検査する。空文字への差し替え、戻り値破棄、要約引数 `nil` を単独負例にする。

### 5. 着手時の変更範囲検査が契約より狭い

- **該当行（実ファイル確認済み）:** [Ruby449–450行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:449)、[951–994行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:951)、[契約403–407行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-47.md:403)。
- **理由:** `AgentMessageBody`・`ReasoningSummaryView` の許可変更以外の残余、`RichMarkdownView` の限定構造を比較していない。Structured の `RunningTurnStatusView` も保護リストから漏れる。変更パス探索は SessionFeature の Sources 内だけで、共有ドメイン・保存・依存定義等を覆わない。
- **修正案:** 許可構造だけを除いた残余を B47 と比較し、契約で保護した他領域も明示的に検査する。

### 6. 恒久検査に折り返し・リンク・コピー等の保護がない

- **該当行（実ファイル確認済み）:** [Ruby873–925行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:873)、[997–1012行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:997)、[実テーマ69–225行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift:69)。
- **理由:** `wrap_ok?` は定義だけで呼ばれない。リンク処理・非表の高さ保護・表セルへの `fixedSize` 禁止・専用色の blob 比較がない。コピー検査は関数不在を成功扱いし、`content` が残れば trim 等を見逃す。禁止先への `summary` 流入も検査しない。ADR 0045・0101・0118 と契約の保護要件が抜けている。
- **修正案:** 対象のテーマ節・リンク関数・コピー関数を構造単位で比較し、呼び出し引数も保護する。`prepare` と `summary` の両方について禁止先を確認する。

### 7. 必須ファイル不在・Git 障害を成功扱いし得る

- **該当行（実ファイル確認済み）:** [Ruby277–289行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:277)、[942–946行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:942)、[1006行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:1006)。
- **理由:** 恒久保護対象の現在値／基準値が `nil` なら比較をスキップする。`git show` と `git cat-file` がともに失敗すると「不存在」へ分類され、新規型の基準不存在として許容され得る。
- **修正案:** 必須ファイルの欠落は失敗にする。Git の実行失敗と、正常に読めた tree 内での不存在を分離する。

### 8. PM ハーネスは常時実行するが、表示の固定シナリオを検証していない

- **該当行（実ファイル確認済み）:** [ハーネス68–100行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:68)、[170–181行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:170)。
- **理由:** 環境変数によるアサーションのスキップはない。ただし検査するのは VM 状態と、直前に書き換えた fixture の値。思考を開く操作、表示本文・要約・色・コピー・更新後の開閉状態の観測がない。実Viewの開閉保持が壊れても、これらのアサーションでは区別できない。
- **修正案:** 同じホスト上で実カードを操作し、既定閉→展開→同一ID更新→空白→再表示を表示状態で照合する。入力モデルの確認だけを受け入れ条件にしない。

### 9. 目視に必要な場面を操作用ウィンドウで再現できない

- **該当行（実ファイル確認済み）:** [ハーネス72–100行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:72)、[221–245行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:221)、[334–354行・467–520行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:334)。
- **理由:** ウィンドウ表示前に Markdown 全種入り回答を `**確認**` へ置換し、復元操作がない。「回答同長置換」は長い回答→`**確` で同長ではない。追記も実イベントを使わない。コード境界の各 fixture がなく、コマンドは常に末尾のエラーより前なので「最新・実行中」に到達しない。
- **修正案:** 完全な回答へ戻す操作、真正の同長更新、実イベントによる追記、契約のコード境界・最新／過去コマンドを選べる固定シナリオを追加する。

### 10. テーマ設定が専用 suite に隔離されていない

- **該当行（実ファイル確認済み）:** [ハーネス29–30行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:29)、[295–306行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:295)、[ThemeStore433–434行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:433)。
- **理由:** 実際の `DSColor` が standard を読むため、ハーネスも `UserDefaults.standard` を書き換えている。終了時の復元では、実行中の他テストとの干渉を防げない。suite 内の `.serialized` は別 suite を直列化しない。
- **修正案:** 実際の色参照先を隔離できる起動方式にし、standard の永続値を書き換えない。

## MEDIUM

### 11. 契約の入力領域に未被覆部分がある

- **該当行（実ファイル確認済み）:** [Swift125–137行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:125)、[190–249行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:190)、[364–385行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:364)。
- **理由:** 分割の境界を `prepare`／`summary` の独立した保護判定へ通す例が不足。候補外ブロックの継続行、単独水平線、ATX の空白／タブ境界、バッククォートを含む不正な情報文字列、終了フェンス後の空白／タブが未被覆。
- **修正案:** 各領域へ独立したリテラル期待値を追加する。例えば `summary("- 項目\n  継続") == nil`、`summary("---") == nil`、終了フェンス後に通常文章が続く保護解除の例を置く。

### 12. 原文保護の一部がトートロジーで、Unicode 正規化を検出できない

- **該当行（実ファイル確認済み）:** [Swift173–177行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:173)、[252–267行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:252)、[304–313行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift:304)。
- **理由:** `source == original` と `code` のリテラル同士比較は製品の保護力を持たない。Swift の文字列等値では正規等価な Unicode 表現が一致し、`summary` が結合文字を正規化しても検出できない。267行も製品結果を見ていない。
- **修正案:** `prepare`／`summary` の実結果を固定 UTF-8 と比較する。保存・コピー原文の保護は、その実経路で確認する。

### 13. `--selftest` が単一違反・偽装検出を満たしていない

- **該当行（実ファイル確認済み）:** [Ruby1464–1469行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:1464)、[1301–1315行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:1301)、[1581–1584行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task47-wiring.rb:1581)。
- **理由:** typography 負例はフォント・余白・行間・倍率の4違反を同時に加える。`if false`・未使用関数・子View上書き等の必要負例がない。また本番接続確認の開始位置は、実際の本番区切りより前にある `PRODUCTION_MARKER` 定数内の文字列に一致し、関数定義を本番接続と数え得る。
- **修正案:** 違反を1件ずつ分け、本番と同じ入口で期待エラー集合を比較する。本番区切りは独立した行として抽出する。

### 14. 幅・倍率変更後の末尾余白が実画面と一致しない

- **該当行（実ファイル確認済み）:** [ハーネス48–56行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:48)、[285–292行・315–327行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:285)、[実画面204–234行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift:204)。
- **理由:** ハーネスは初回の composer 高さを固定し、composer を縦積みする。製品は下端 overlay と実測高さの継続更新を使うため、幅360・倍率2.0等で末尾到達性の前提がずれる。
- **修正案:** 製品と同じ overlay 構成と高さ追随を使う。

### 15. ハーネス固有のアクセス制御エラー候補 — unverified

- **該当行（実ファイル確認済み）:** [ハーネス186–197行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:186)、[377行](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift:377)。
- **理由:** internal の `Task47VisualScenario.client` と初期化引数が private 型 `Task47VisualClient` を公開している。新規製品APIの不足とは独立したコンパイルエラー候補。コンパイラ実走は未確認。
- **修正案:** ハーネス内型のアクセス範囲を揃え、製品API実装後も残るコンパイルエラーとして切り分けて確認する。