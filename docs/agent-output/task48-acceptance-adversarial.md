**判定：修正が必要です。** 文言表31件と数値テンプレートの逐語期待値は一致していますが、配線検査には正常な実装を拒否する条件と、契約違反を見逃す穴があります。

指定View・言語経路・関連ADR・task-50境界を確認しました。退避テストとrbは凍結SHAのblobと一致しています。`--selftest` は必須ラッパーの `mktemp: Operation not permitted` で起動できず、以下の変異例の実行再現は **unverified** です。

## MUST

### 1. 通常メニューに存在しない見出しを要求している

- **該当行（実ファイル確認済み）**：`.claude/scripts/task48-wiring.rb:470,472`、`ComposerSettingsControls.swift:222–279,724–732`
- **理由**：通常メニューにも `permissionLabel`・`modeLabel` を要求しています。しかし実物の通常メニューは選択中の値を表示し、`Permission`・`Mode` 見出しは省略メニューにだけ存在します。契約どおり既存表示だけを置換するとNGになり、不要な表示やダミー参照を追加する誘因になります。
- **修正案**：通常メニューは既存の選択中表示、省略メニューは見出しを、それぞれ実在する位置で検査する。

### 2. struct外の既存ヘルパーを追跡できない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:307–342,638–648`、`RichMarkdownView.swift:24–49,157–172`、`ComposerSettingsControls.swift:68–75,490–491`
- **理由**：到達解析の探索範囲をstruct本文に限定しています。Markdownのコピー文言はファイル直下の `chatMarkdownTheme`、未選択のApprovalはファイル直下の `composerPermissionTitle` にあります。既存経路を維持して正本接続しても参照を発見できません。selftestはMarkdownの文言を直接bodyへ置き、この構成差を隠しています。
- **修正案**：実際に呼ばれたファイル直下ヘルパーまで追跡し、実製品と同じ呼び出し構造の正例を追加する。

### 3. 契約が要求する既存検査の改訂が残っている

- **該当行（実ファイル確認済み）**：`tasks/task-48.md:191–197`、`.claude/scripts/task13-wiring.rb:14`、`AcceptanceContextPopoverBranchTests.swift:16,27`、`ComposerModeMenuAcceptanceTests.swift:31–59`、`GridComposerSettingsAcceptanceTests.swift:49–51`
- **理由**：task13は現在も `Text("Projects")` を必須とし、task48の正本接続と両立しません。既存Swiftテストも言語引数なし・旧英語期待値のままです。これは新規型による許容済みのコンパイルREDとは別のハーネス不整合です。
- **修正案**：ディスパッチ前にPMが指定された検査を改訂・凍結する。項目集合、順序、内部値、計算検査を保持し、task-50で変更する権限表示名まで旧英語へ固定し続けない。

## HIGH

### 4. 表示位置とキーの対応を検査していない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:447–482,638–660,1401–1409`、`ChatMessageCopyButton.swift:33–50`
- **理由**：判定は到達範囲に `UIWording`・キー・`languageCode` が存在するかだけです。コピーのLabelとhelpのキーを交換しても識別子集合は同じです。コピー前後のAX分岐逆転も検査しません。未実行のローカルクロージャに正本参照を入れ、表示を別文字列にする偽装も排除していません。また、effortの5キーはView側の検査表にありません。
- **修正案**：各 `Text`・`Label`・help・AX・選択中表示の引数と分岐を固定対応させる。通常／省略のeffort経路、キー交換、未呼出しクロージャを負例へ追加する。

### 5. 環境Localeから表示までの言語伝播を保証しない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:374–379,678–704`、`RichMarkdownView.swift:22–44`、`ComposerContextIndicator.swift:175–181`
- **理由**：環境宣言の存在と、一部の直接リテラル指定しか検査しません。`languageCode` プロパティ自体の固定値化は対象外です。TurnCost・構造化セル・省略メニュー・実際のコンテキスト表示元も環境検査から漏れています。Markdownには既存のテーマキャッシュがあり、言語をキーに含めず翻訳済み文言を捕捉すると切替後も旧言語が残りますが、その経路の検査がありません。
- **修正案**：各呼出しの言語引数を環境Localeまで追跡する。Markdownは同一テーマ・倍率で日→英→日の再取得を検査し、言語を反映しないキャッシュを拒否する。

### 6. 不変条件の大半がbaseline比較になっていない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:824–899`、`ChatSessionAccessories.swift:368–405`、`ComposerSettingsControls.swift:419–443,858–874`
- **理由**：実際に旧ソースと比較する主な内容は承認の `.accept/.decline/.cancel` の出現列です。`respond` の本体を空にしても列は変わりません。送信・停止・コピー本文・ブランチ操作、実Binding・tag、選択肢の内部値や順序の比較がありません。CodexのPlan解除処理も保護されず、ADR 0029の排他条件を壊せます。AXも文字列がファイル内に残れば通る判定です。
- **修正案**：所有対象の操作本体・引数・条件・Binding・識別子の取付先を、文字列を保持した構文単位でbaseline比較する。権限文言だけはtask-50の変更を許容する。

### 7. 数値と動的出力の供給式を保護していない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:720–762,872–887`、`ComposerContextIndicator.swift:53–69`、`ChatMessageCells+Basic.swift:159–180`、`ChatMessageCells+Structured.swift:266–272`
- **理由**：使用率の引数名以外はトークンの存在確認が中心です。トークン使用量の引数交換、金額の固定値化・整形変更、コマンド／説明欠損条件の反転、出力条件の否定追加を検査しません。Swiftテストはテンプレート単体なので、Viewから誤った値を渡しても検出できません。容量0の計算経路も既存の数値テストでは未被覆です。
- **修正案**：供給式と条件式をbaseline比較し、容量0・丸め境界・動的値の欠落／交換を実ヘルパー経由で検査する。

### 8. 必須baseline blobの取得失敗を拒否しない

- **該当行（実ファイル確認済み）**：`task48-wiring.rb:253–256,828–839,908–911,1568–1570`
- **理由**：`git_show` 失敗を `nil` にし、`baseline_files` はそのまま返します。必須の既存ファイルについて取得成功を検査せず、比較が条件分岐で省略されます。契約162行の「必要なblobの取得失敗は非ゼロ」に反します。
- **修正案**：新設 `UIWording.swift` の不在だけを例外にし、既存対象blobの欠落・取得失敗はパス付きで即NGにする。単一blob欠落のselftestを追加する。

## MEDIUM

### 9. ADRの「サブタイトル廃止」と現契約の適用範囲が不明確

- **該当行（実ファイル確認済み）**：`macos/docs/adr/0147-chat-code-card-and-header-dedup.md:55–56`、`tasks/task-48.md:76,116`、`ChatMessageCells+Structured.swift:267`、`ChatMessageCellsCommon.swift:95–98`
- **理由**：ADRはサブタイトルを常にnilと記述する一方、現コードと契約は「実行中／出力あり」を維持します。実コードとの一致は確認済みですが、ADRが単独コマンドセルを例外とする意図は **unverified** です。
- **修正案**：単独セルを維持する今回の範囲をPMが明記し、ADRの適用範囲を追記する。翻訳実装の都合で表示を復活・削除しない。

### 10. 製品を検査しない自己比較が含まれる

- **該当行（実ファイル確認済み）**：`tasks/frozen/staged/AcceptanceUIWordingTests.swift:201–202,210,287–294`
- **理由**：同じキー同士の比較、同一呼出し同士の比較、期待値表だけの禁止語検査は、正しい文言や3入力欄の共通接続を保証しません。独立リテラル比較が別にあるため、その主検査は有効です。
- **修正案**：自己比較を削除し、言語を切り替えた後の独立期待値比較と、実表示位置の配線検査へ置き換える。

### 11. 公開APIであることをSwiftテストが保証しない

- **該当行（実ファイル確認済み）**：`AcceptanceUIWordingTests.swift:15,114–123`、`task48-wiring.rb:609–624`
- **理由**：`@testable import` のため、Keyや関数がinternalでも型検査できます。Rubyも `public` を要求するのは外側enumだけです。別パッケージのViewが利用する公開面としての検査が不足しています。
- **修正案**：この受け入れテストは通常の `import DesignSystem` で公開APIを使用する。