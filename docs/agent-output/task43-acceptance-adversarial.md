差し戻しです。配線検査が誤配線や未使用コードを合格させ得るため、現状の凍結物だけでは契約を守れません。read-only 制限により指定ファイルには保存していません。以下が報告本文です。

対象テスト2本と rb は `276018d` の blob と一致しています。テスト作成担当の報告は読んでいません。以下の行番号は実ファイルで確認済みです。

入力軸は、名前の欠損・空白・改行・非空文字の保持、Destination、送信条件3 Bool、phase×開始可否、本文・添付、readiness、親参照の形状、プロジェクトの識別、画面3種×討論4状態として照合しました。

## MUST

### 1. task-43 の専用検査が通常の検証入口に登録されていない

- **該当行**：[ui-ux-verify-task.sh:56](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/ui-ux-verify-task.sh:56)、`.claude/verify.sh:5–10`、`tasks/task-43.md:285–288`。
- **理由**：task-43 の分岐がなく、共通 verifier へ進む。既定の `.claude/verify.sh` はパッケージ検査等だけで、task43-wiring・selftest・固定 SHA の照合を実行しない。Swift テストが通っても成功基準2が未検査になる。
- **修正案**：無条件 `exec` より前に専用分岐を登録し、固定 SHA、selftest、配線検査、対象パッケージ検査を実行する。退避テストを復帰した状態で driver 経由の到達を確認する。

### 2. 「コンパイル RED が正常」は指定手順の保護力確認と矛盾する

- **該当行**：[Sessionテスト:5](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceComposerDestinationLabelTests.swift:5)、Dashboardテスト:7–8、指定手順 `phase1_5-acceptance-adversarial.md` の「RED を確認し、その種類を記録する」。
- **理由**：テストは公開シンボル欠落によるコンパイル RED を正常としている。指定手順は「ビルドエラーによる red は、アサーションの保護力を何も証明しない」としてアサーション RED を要求する。現在、新規モデルは未実装である。
- **修正案**：公開面欠落の RED と振る舞い違反の RED を区別し、後者を確認できる手順と結果を契約へ記録する。**過去のアサーション RED・変異検査の実施状況は unverified**。未実施だったとは断定しない。

## HIGH

### 3. プロジェクト名と作業名の実値を追跡していない

- **該当行**：[rb:517](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:517)、576–599、666–697、793–800。
- **理由**：中間 View は引数ラベルの存在しか確認しない。`projectName: nil`、`projectNames: [:]`、initializer 内の `self.projectName = nil` を防げない。`GridChatColumn → GridComposerBar` の受け渡し検査もない。単一の `taskName: viewModel.displayName` と、チームの `rootProjectName` の取得元も固定されていない。
- **修正案**：実経路の各呼び出しと initializer の代入を対応づける。nil・空辞書・別カード名・選択プロジェクトへの差替えを、経路ごとに負例へ追加する。

### 4. 到達性の探索が未使用 helper を描画経路へ混入させる

- **該当行**：[rb:305](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:305)、323–340、611–615、1328–1330。
- **理由**：文字列を含む全識別子を探索し、helper の本文や struct 全体を連結している。`if false` の除去はその後なので、その中から見つけた helper は残る。例えば `if false { destinationLabel }` の helper 本文を到達済みと誤認する構造である。グリッドでは `composerContent` を直接起点にするため、製品の `body` が呼ばなくなっても検査対象に残る。
- **修正案**：文字列・非実行分岐を除外してから、型のスコープを保って実参照を追跡する。各画面の `body` から呼ばれない helper、文字列だけの参照、`if false` 経由の参照を負例にする。

### 5. チームの表示用 action を送信時の action で代替できる

- **該当行**：[rb:762](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:762)、702–705、774–800。
- **理由**：`collect_reachable` は `sendTeamMessage` の**宣言を除いた本文**を追加する。その後の `without_func` は宣言を探すため、その本文を除去できない。結果として送信時の routing 呼び出しが表示側の検査を満たし得る。さらに phase・開始可否は部分文字列の確認なので、開始可否の反転も区別できない。
- **修正案**：`TeamComposer` に渡す Destination の生成式から逆に追跡し、そこで使う action の phase・開始可否の式を送信側と比較する。表示 action の削除・別 action の受け渡し・開始可否の反転を負例にする。

### 6. 送信不可ラベルへ渡す Bool を検証していない

- **該当行**：[rb:591](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:591)、676–686、708–821。実コードは `ChatComposer.swift:156–157`、`GridChatColumn.swift:190–192`、`TeamComposer.swift:20–21`。
- **理由**：単一・グリッドの `hasContent` は `attachments.isEmpty` の存在しか見ない。否定の欠落、`||`→`&&`、trim の削除を区別しない。`hasDestination`・readiness、およびチームの3 Bool の実引数も検査しない。純粋モデルの8組テストは、View が誤った Bool を渡す欠陥を検出できない。
- **修正案**：各ラベルの引数を既存の送信条件へ結び付けて検査する。添付のみ、空白・改行のみ、starting/error、宛先なしで入力値を誤らせる負例を追加する。

### 7. 不変条件の比較対象が足りない

- **該当行**：[rb:824](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:824)、835–884。実コードは `ChatComposer.swift:103–109,330`、`TeamTimelineView.swift:247–249,292–313,451–452`。
- **理由**：`canSubmit` 本体を固定しても、footer に `canSubmit: true` を渡したり、送信ボタンの `.disabled` を変更できる。readiness 更新、親リンクの生成、開始可否の入力元、送信・フォーカス callback の配線も比較対象外。既存関数を残して呼び出しだけ変える変更を防げない。
- **修正案**：契約174–179行の不変条件を、宣言・条件式・呼び出し引数へ対応づける。送信先・本文・disabled・フォーカスをそれぞれ変更する独立した負例を追加する。

### 8. 高さ計測・表示位置・AX の検査が構造を見ていない

- **該当行**：[rb:551](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:551)、566–574、641–664、733–753。
- **理由**：`onGeometryChange` の存在だけではラベルが計測範囲内とは分からない。実際のグリッドには高さ計測と別に幅計測がある（`GridChatColumn.swift:72–75,99–104`）。AX/help も対象 Text への付与を確認しない。宛先なしの非表示は `if let targetDisplayName` だけを検出し、`if targetDisplayName != nil` を扱わない。
- **修正案**：表示 Text の修飾、編集領域との順序、composer 高さを更新する計測範囲を検査する。幅計測だけ残す変更、別 View への AX 移動、別構文での条件付き非表示を負例にする。

## MEDIUM

### 9. 名前の正規化に未被覆の領域がある

- **該当行**：[Sessionテスト:58](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceComposerDestinationLabelTests.swift:58)、94–125、168–191。
- **理由**：空でないプロジェクト名の前後 trim を試していない。作業名の空文字・改行のみ・前後に空白がある非空名の保持も未被覆。親送信でプロジェクト名が欠損し、作業名だけ存在する組合せもない。
- **修正案**：`" \nPhlox\t "`、作業名 `""`・`"\n\t"`・`" 調査 "`、`.parentSession(projectName: nil, taskName: "全体作業")` をリテラル期待値で追加する。

### 10. 「画面×4状態」「starting/error」「添付のみ」が実合成の検査になっていない

- **該当行**：[Dashboardテスト:426](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTeamComposerDestinationLabelTests.swift:426)、435–451。Sessionテスト:322–390、394–488。
- **理由**：`_ = phase` で状態を捨て、同じ conversation を反復している。starting/error も状態を作らず Bool を直書きし、添付も生成しない。文字列関数のテストとしては成立するが、画面や状態との接続を検証したことにはならない。
- **修正案**：モデル単体の確認と明示し、重複を被覆件数へ数えない。実値の取得と引き渡しは上記配線検査で保護する。実状態を使う確認が必要なら、既存の無課金 fixture で別途行う。

### 11. 循環 resolver の結果と表示先の対応が弱い

- **該当行**：[Dashboardテスト:357](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTeamComposerDestinationLabelTests.swift:357)、380–382。`TeamComposerTarget.swift:18–31`。
- **理由**：実 resolver は `a→b→a` を a から開始すると a を返す。一方、テストは表示が A/B のどちらでも合格するため、解決結果と違う名前を表示しても見逃す。
- **修正案**：現在の resolver の結果を固定し、その ID に対応する表示だけを期待する。別の探索規則は追加しない。

### 12. 正しい実装形式を拒否する検査と、実在しない負例がある

- **該当行**：[rb:335](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task43-wiring.rb:335)、554–569、1274–1275、1295–1299。
- **理由**：表示変数名を `destinationText` に固定しており、同じ値を別名で表示する実装を拒否する。計算プロパティにモデル呼び出しを置くと、探索後の文字順が編集領域より後になり、正しい配置も拒否し得る。また selftest の `.ended`・`.concluding` は `AgoraComposerAction` に存在しない case で、実際にコンパイルできる誤配線を表していない。括弧文字列の正例 `parens` は定義するだけで検査していない。
- **修正案**：変数名ではなく値の対応と表示位置を検査する。実在する action の誤対応を負例にし、文字列内括弧を含む抽出結果をアサートする。

### 13. ADR 0046 のパネル高さとの調整が未定義

- **該当行**：[ADR 0046:20](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/adr/0046-composer-default-height-compact-revert.md:20)、task-43:167–172、rb:939–968。
- **理由**：ADR はエディタ単体でなく、パネル全体を約80pxとする決定。検査の正例は既存 VStack 内へ常設行を追加するが、全体高の扱いを決めていない。現在のエディタ最小高36は実コードで確認したものの、追加後のパネル高は **unverified**。
- **修正案**：ラベルを含むパネル高について既存決定との関係を裁定し、実合成で測定する。高さ増加を採択する場合は ADR に追記する。

検証範囲は実ファイルの静的照合と凍結 blob の一致確認です。selftest は必須ラッパーが `mktemp: ... Operation not permitted` で exit 1 となり、Ruby 本体は未実行です。上記の変異例の実行結果、Swift テスト、GUI は **unverified** です。