## 判定

**needs_changes**

契約を破る実装を通す検査の穴と、正しい実装を拒む条件があります。指定対象を読み、7項目を確認しました。ファイル変更はしていません。

受け入れテスト2本と配線検査2本は、指定の `compact-test --full` 経由で実行を試みましたが、すべてラッパー内で exit 1。本体は起動していません。代表ログ：

```text
mktemp: mkstemp failed on /tmp/tmp.WPTJI4A6Jq: Operation not permitted
/Users/ryosuke/.agents/scripts/compact-test: line 26: : No such file or directory
cat: : No such file or directory
```

Swiftテスト・Ruby検査・GUI挙動は未検証です。以下の反例と追加テスト案は静的レビューによるもので、実走結果ではありません。凍結コミット `73a66ca` と比較し、対象の受け入れテスト・配線検査に差分がないことは確認しました。

## 指摘

### 1. [HIGH] task-33の「最初のチャット対応」とcustom対応を十分に反証できない

**対象:** [AcceptanceNewSessionMenuModelTests.swift:43](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceNewSessionMenuModelTests.swift:43)、同ファイル:80、:160。

**根拠:** primaryを具体的に検査する入力では、最初のチャット対応が常にClaudeです。「チャット対応があればClaudeを優先する」という誤実装を排除できません。節の順序検査も、チャット対応同士はClaude→Codexのままです。

custom descriptorは一度も渡していません。製品の `availableAgentDescriptors` はcustomを含みますが、`AgentDescriptor.kind` はcustomで `preconditionFailure` になります。テストのコピー用ヘルパーも `source.kind` を使うため、そのままcustomケースへ流用できません。

**修正案:** 組込の逆順・Claude不在・custom非対応を固定入力で追加する。コピーが必要なら `kind:` ではなく `ref:` を保存する。

```swift
let codex = AgentRegistry.descriptor(for: .codex)
let claude = AgentRegistry.descriptor(for: .claudeCode)
let reordered = NewSessionMenuModel.make(
    projectName: "P", descriptors: [codex, claude]
)
#expect(reordered.primary?.ref == .builtin(.codex))
#expect(reordered.primary?.title == "新しいチャット（Codex）")
#expect(reordered.sections[0].items.map(\.id) ==
        ["chat:codex", "chat:claudeCode"])

let custom = AgentDescriptor(
    ref: .custom("ui01-probe"),
    displayName: "Probe",
    binaryName: "probe",
    symbolName: "terminal",
    colorRGB: AgentRGB(0, 0, 0),
    bypassKey: "probe",
    launchSpec: AgentLaunchSpec(),
    supportsStructuredChat: false
)
let customOnly = NewSessionMenuModel.make(
    projectName: "P", descriptors: [custom]
)
#expect(customOnly.primary == nil)
#expect(customOnly.sections.flatMap(\.items).map(\.id) ==
        ["terminal:ui01-probe"])
#expect(customOnly.sections.flatMap(\.items).map(\.ref) ==
        [.custom("ui01-probe")])
#expect(customOnly.sections.flatMap(\.items).map(\.backend) == [.pty])
```

### 2. [MED] descriptorの重複に対する契約が未定義で、テスト自身にも重複入力がある

**対象:** [task-33.md:30](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-33.md:30)、同ファイル:42、AcceptanceNewSessionMenuModelTests.swift:49、:109。

**根拠:** 「descriptorごとに項目を作る」「IDは `terminal:\(ref.id)`」「IDは一意」を、重複入力に対して同時には満たせません。primaryテストの `[cursorOnly] + AgentRegistry.allDescriptors` はCursorのrefを重複させていますが、その出力の一意性は検査しません。

製品の `AgentCatalog` は `ref.id` を重複排除します（[AgentDescriptor.swift:245](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Sources/AgentDomain/AgentDescriptor.swift:245)）。製品経路の重複バグを観測したわけではなく、モデルの入力契約とテスト入力の不整合です。

**修正案:** 最小の対応は「入力の `ref.id` は一意」を事前条件にし、primaryテストを `[cursorOnly, claude, codex]` に修正すること。重複を許すなら採用規則を別途固定する。

空名・nil・ASCII空白は既に検査されています。一方、trim対象の改行・タブは未固定なので、対象文字を契約に明記して次も追加する。

```swift
#expect(NewSessionMenuModel.make(
    projectName: "\t UI検証A \n", descriptors: []
).destinationText == "作成先: UI検証A")
```

### 3. [HIGH] DSHitTargetの不等式だけでは契約値24/30/24を固定できない

**対象:** [AcceptanceHitTargetTests.swift:13](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceHitTargetTests.swift:13)、[task-34.md:30](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-34.md:30)、同ファイル:46。

**根拠:** `icon = 1000`、`modeSegmentWidth = 1000`、`modeSegmentHeight = 28` でも、現在の `DSSpacing.xxs = 2` なら寸法に関する4検査を満たします。契約値とAXゲートの30×24・24×24には違反します。

不等式はトートロジーではなく、最低寸法・行への収まりの検査として有効です。ただし、**具体値を指定した今回の契約に対しては不足**です。また、変更禁止の `DSIconSize.l` は指紋検査の対象外です。

**修正案:** 不等式を残し、独立したリテラルとの等値検査を追加する。

```swift
#expect(DSHitTarget.icon == 24)
#expect(DSHitTarget.modeSegmentWidth == 30)
#expect(DSHitTarget.modeSegmentHeight == 24)
#expect(DSSpacing.xxs == 2)
#expect(DSIconSize.l == 15)
```

### 4. [HIGH] task33-wiringは作成先・表示内容・描画順・操作との対応を検査していない

**対象:** [.claude/scripts/task33-wiring.rb:67](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task33-wiring.rb:67)、同ファイル:72、:84。

**根拠:** 検査するのは識別子や呼び出し引数の部分文字列です。次を排除できません。

- `projectName: nil` 固定、別プロジェクトの名前、組込だけのdescriptor配列を渡す。
- `createSession` の `projectID:` を省略・nil化する。
- `destinationText` をButtonのラベルにする、描画順を逆転する。
- `Label` のtitle・symbolを別項目の値にする。
- 必要な呼び出しを到達しない分岐へ置く。

特に、正しい実装の `projectID: projectID` だけを `projectID: nil` に変えても検査条件は変わりません。現行の `createSession` はnilを既定プロジェクトへ解決するため（[DashboardView.swift:740](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:740)）、**B行から作ったセッションが選択中のAへ入る**反例になります。

**修正案:** 名前取得とdescriptor入力、各Buttonの表示値・起動引数を対応づけて検査する。さらに「A選択中にB行の＋から作成し、表示先も生成セッションの所属もB」という受け入れケースを固定する。400文字以内の近接判定を、Button内であることの証明として扱わない。

### 5. [HIGH] task34-wiringは寸法参照の存在と実際の適用を区別できない

**対象:** [.claude/scripts/task34-wiring.rb:75](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task34-wiring.rb:75)、同ファイル:82、:95、:100、:116。

**根拠:**

- `ModeSegmentButton` 内に2つのトークン名と任意の `frame(` があれば通ります。旧26×20を残し、次の未使用プロパティを追加しても該当条件を満たします。

  ```swift
  private let sizes = (
      DSHitTarget.modeSegmentWidth,
      DSHitTarget.modeSegmentHeight
  )
  ```

- サイドバーはファイル全体の3箇所以上を数えるだけで、対象3操作との対応を検査しません。
- ×は `DSHitTarget.icon` の存在だけで、幅・高さの両方への適用を要求しません。
- `.contentShape`、hover、help、選択trait、トラックpaddingなどの削除を検査しません。
- フォーカス関連modifierは個数比較だけなので、`accessibilityHidden(true)` → `false` や適用先の移動を検出しません。
- `.frame(height: 32)` が別のViewに移っても通ります。
- コメントを除去しないため、検査文字列をコメントで充足できます。

**修正案:** 各対象操作のlabelとmodifierを限定して検査する。上記の誤配置・削除をNGにする検査用fixtureを追加し、実際の操作範囲は指摘8のGUIゲートで確認する。

### 6. [MED] 正しいSwiftUI構文を拒む偽陽性がある

**対象:** task33-wiring.rb:69、:72、task34-wiring.rb:40。

**根拠:**

- task-33は `Section(section.title)` を認識しますが、同じ見出しを表示する次の形式は `Section(` がないためNGです。

  ```swift
  Section {
      ForEach(section.items) { item in
          // 項目を描画
      }
  } header: {
      Text(section.title)
  }
  ```

- `if let primary = model.primary` は現在の検査で認識されます。この表記自体に問題はありません。一方、束縛名を `primaryItem` にすると、対応箇所を正しく変更してもNGです。
- task-34は現行の `Button(action: onRemove) { ... }` を扱えます。しかし次の等価な形式では、labelではなくactionの `{ onRemove() }` を切り出し、トークン不在でNGにします。

  ```swift
  Button {
      onRemove()
  } label: {
      Image(systemName: "xmark")
          .imageScale(.small)
          .frame(width: DSHitTarget.icon, height: DSHitTarget.icon)
          .contentShape(Rectangle())
  }
  ```

**修正案:** 契約が要求する表示・動作と、推奨する記法を分ける。少なくとも上の等価構文を検査用fixtureに追加する。記法まで固定するなら、それを機能要件ではなく検査上の制約として明示する。

### 7. [HIGH] 比較基準がHEADで移動し、task-33と34の不変条件も衝突する

**対象:** task33-wiring.rb:7、:101、task34-wiring.rb:11、[ui-ux-verify-task.sh:35](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/ui-ux-verify-task.sh:35)、task-33.md:4、:43、task-34.md:4、:37。

**根拠:** 契約の基準は `73a66ca` ですが、両Ruby検査は環境変数未指定時に `HEAD` を使います。確認した呼び出しスクリプトはその環境変数を設定していません。変更をコミットした後のクリーンなツリーでは、ファイル不変・modifier個数の検査が自身との比較になります。

一方、単純に `73a66ca` へ固定すると、task-34が正当に変更する `DashboardSidebarView.swift` を、task-33の「ファイル全体に差分なし」が拒みます。両タスクは `depends_on: []` なので、この組合せを契約上排除していません。

**修正案:** 検査基準を契約から明示的に渡す。task-33の不変条件は、そのタスク自身の変更範囲について判定するか、task-34完了後の基準へ再凍結する。HEADとの自己比較で衝突を隠さない。

### 8. [HIGH] PMゲートが仕様の「実際に押せる・キーボードで操作できる」を満たしていない

**対象:** task-33.md:44、:51、task-34.md:46、:51、[ui-ux-improvement-backlog.md:162](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/specs/ui-ux-improvement-backlog.md:162)。

**根拠:** task-34のゲートは主にAX要素枠・スクリーンショット・プログラムからのフォーカス設定です。仕様自身が区別している「要素枠」と「実際のヒット領域」を検証上は区別できていません。

不足する確認は次のとおりです。

| 対象 | 必要な受け入れ操作 |
|---|---|
| モード3個・サイドバー＋・行の…／＋・タイル× | 拡張領域の端をクリックし、意図した操作だけが発火する |
| 隣接する…／＋ | 境界付近のクリック、hover移動で誤操作・表示欠落がない |
| プロジェクト行 | 同じ幅・選択状態で変更前後を測定し、hover前後でも高さ・名前・バッジが崩れない |
| キーボード | キーボード操作で到達し、起動できる。選択済み／未選択の両方でフォーカスを識別できる |
| メニュー作成先行 | 表示され、クリックしても作成されない。キーボード選択・起動の対象にならない |
| メニュー起動経路 | primaryと既存6経路で、ref・backend・作成先が一致する |

task-33の目視ゲートはcustomターミナルの作成を要求しますが、primaryや既存6経路の起動先までは確認しません。Menu内の `Text` の実際の描画・非活性挙動も、このレビューでは未検証です。

**修正案:** 上記をPMゲートの必須結果として追記する。フォーカス設定が拒否された場合は「未検証」の記録に加え、その条件を未達として残す。

### 9. [MED] ADR 0082との差分と、既存のモード規則を再利用する方針が未整理

**対象:** [0082-agent-mode-launch-cards-and-menu.md:20](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/docs/adr/0082-agent-mode-launch-cards-and-menu.md:20)、同ファイル:22、task-33.md:28、:36、[AgentStartCards.swift:11](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentStartCards.swift:11)、同ファイル:35。

**根拠:** ADRは「表示名 — モード」のフラット項目と、`modes(for:)`・`AgentStartCardMode.backend` への規則集約を決定しています。今回の節分け・主操作追加は表示構成の更新ですが、その関係が記録されていません。モデル内で対応判定とbackend写像を再実装する余地もあります。

ただし、**Sectionによる同一メニュー内の分類は、ネストMenuへの後退ではありません**。ADRの最小アクションという目的とは両立します。また、既存規則の再利用を契約が禁止しているわけでもありません。

**修正案:** モデルから既存の `modes(for:)` と `.chat.backend`／`.terminal.backend` を再利用する方針を明記する。表示構成の更新はADRへの追記または後継決定で記録する。ADRはallowed_paths外なので、PM側の更新として扱うか許可範囲を追加する。

### 10. [MED] 厳密な「1タスク1契約」ではtask-33が複合契約になっている

**対象:** task-33.md:27、:28、:36、:42。

**根拠:** 「作成先の解決・表示」と「起動候補の選択・分類・起動」は独立に失敗します。例えば全項目を正しく起動できても作成先表示だけ誤る状態と、その逆が成立します。モデル・配線という実装層の違いではなく、受け入れる成果が2つあります。

**修正案:** 厳密に運用するなら、この2成果で契約を分ける。同一メニューの改善として一括で扱う場合も、複合契約であることを明示し、双方の合格を必須にする。

task-34のトークン追加と対象操作への適用は、押せる範囲を変える同一成果の上下流です。hover・行高・フォーカスの**維持**だけを理由に、別タスクへ分割する必要はありません。

## 掃いた観点

| # | 観点 | 見解 |
|---|---|---|
| 1 | 1タスク1契約 | 指摘10。task-33は複合。task-34は単一成果として扱える。 |
| 2 | 入力空間 | 指摘1・2・8。custom、対応エージェントの逆順、入力重複、改行・タブ、Menu非活性行、拡張領域・hover・隣接操作が不足。空名・nil・非対応のみ・descriptor空の検査は存在する。 |
| 3 | 反証可能性 | 指摘1・3・4・5・7。モデルの文言・backend・IDをリテラルで固定する検査は有効で、空出力だけで全部がgreenになる構成ではない。寸法の等値と配線の意味の検証が不足。 |
| 4 | allowed_paths | **製品コードの実装には十分。** `projects` は読み取り可能、`Project.name` はpublic。対象3ファイルはDesignSystemをimport済みで、パッケージ依存も存在する。ADR更新を含める場合だけ指摘9。 |
| 5 | Ruby検査 | 指摘4・5・6・7。未接続の文字列でも通る穴、等価構文を拒む条件、基準コミットの問題を確認。 |
| 6 | ADR | 指摘9。0082の表示構成・単一規則との関係を更新すべき。0071の既定チャット、0086のプロジェクト選択導線との新たな矛盾は検出せず。 |
| 7 | ユーザーにしか答えられない問い | 現契約の技術的修正を進めるための必須質問はなし。下記参照。 |

補足として、**24pt化の対象frameはサイドバーファイル全体で3箇所、`ProjectSidebarHeader` 内では2箇所**です。[DashboardSidebarView.swift:100](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift:100) が見出し＋、同ファイル:358が…、:372が行の＋です。「ProjectSidebarHeader内に対象が3箇所」という解釈は誤りですが、現契約とRuby検査はファイル全体を対象にしています。

allowed_pathsの裏取り箇所：

- [DashboardViewModel.swift:69](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift:69)：`projects` のgetter。
- [Project.swift:18](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Sources/AgentDomain/Project.swift:18)：publicな `name`。
- [DashboardTopBarControls.swift:3](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift:3)、DashboardSidebarView.swift:3、[PaneLayoutView.swift:4](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift:4)：`import DesignSystem`。
- [DashboardFeature/Package.swift:36](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Package.swift:36)、[SessionFeature/Package.swift:26](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Package.swift:26)：ターゲット依存。

persona-reviewの追加確認：契約適合・正しさ・構造・テスト品質は上記指摘に対応。到達性・アクセシビリティは指摘8に加えて実機未検証。根本原因は検査が実際の配線・操作ではなく文字列や寸法に留まる点です。凍結テストの弱体化・skip化は検出せず。実装前のAPI未存在を、今回の契約レビューの欠陥としては数えていません。

## ユーザーへの問い

**必須の問いはありません。** 主操作の選択規則、表示文言、24/30/24の寸法は既に契約で決まっています。技術的な検証不足を埋めるために、これらの再承認を求める必要はありません。