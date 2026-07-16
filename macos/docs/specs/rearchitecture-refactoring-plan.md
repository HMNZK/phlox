---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-08
---

# Phlox リアーキテクチャリング・リファクタリング計画書

- **基準コミット（監査時点）**: `a420376`（`dev`、2026-07-08）
- **性格**: 振る舞い保存を原則とする構造改善キャンペーンの計画。新機能は含まない。
- **数値の出所**: 本書のファイル数・行数は 2026-07-08 の静的走査（`find`/`wc`）による概算。複雑度（CCN）・重複率・テスト数の正式なベースラインは Phase 0 で計測して確定する（未計測の項目は「未計測」と明記している）。

## 0. 要旨

Phlox は App ターゲット + 15 SPM パッケージの層状構成だが、`DashboardFeature` 1 パッケージが全体の約 6 割（約 19,000 行 / 88 ファイル）を占める God パッケージ化しており、2,000 行超の ViewModel が 2 本、パッケージ間の型重複、`AppBootstrap` ⇄ `DashboardFeature` の双方向依存という構造的な歪みが確認された。本計画は Fowler の振る舞い保存リファクタリングと Parnas の情報隠蔽を判断基準に、**既定アーキテクチャ（ADR 0001: MVVM + @Observable + SPM マルチモジュール）への適合度を上げる**方向で、Phase 0（ベースライン）→ 並列監査 → 計画確定 → WP 分割 → 並列実装 → 統合検証 → 定量評価の 8 フェーズで実施する。別アーキテクチャ（TCA / Clean Architecture）への乗り換えは行わない。

## 1. 目的と背景（なぜやるか）

設計の主目的は複雑性の管理である（McConnell『Code Complete』§5.2）。減らせるのは表現手段に起因する偶有的複雑性であり（Brooks）、現状の Phlox には以下の偶有的複雑性が蓄積している。

### 確認済みの症状（2026-07-08 監査）

1. **God パッケージ**: `DashboardFeature` が Sources 88 ファイル・約 19,006 行で全パッケージ合計（約 31,481 行）の約 60% を占め、他 13 パッケージ中 10 個に依存するハブになっている。→ Parnas 基準では「どの変更が来てもここが影響を受ける」状態で、変更影響の予測可能性が失われている。
2. **God ファイル**（500 行超は Packages 内 10 本 + App 内 2 本）:
   - `DashboardFeature/Session/ChatSessionViewModel.swift` — 2,279 行
   - `DashboardFeature/Dashboard/DashboardViewModel.swift` — 2,002 行
   - `DashboardFeature/Dashboard/DashboardView.swift` — 1,342 行
   - `ClaudeAgentKit/ClaudeChatClient.swift` — 1,101 行（パッケージ唯一のソースファイル）
   - ほか `ChatMessageCells.swift` 978 行、`SessionViewModel.swift` 871 行、`AppServerTypes.swift` 605 行など
3. **パッケージ間の型重複**（統合漏れの疑い・確認済み）:
   - `FilePatchChange`: `CodexAppServerKit/AppServerTypes.swift:595`（`kind: JSONValue?`）と `StructuredChatKit/StructuredChatTypes.swift:3`（`kind: String?`）でほぼ同一構造体を別定義。CodexAppServerKit は StructuredChatKit に依存しているにも関わらず再定義している。
   - `ApprovalDecision`: `ControlServer/ControlTypes.swift:34` と `CodexAppServerKit/Notifications.swift:132` で同じ 4 ケースの enum を独立定義。
   - `HTTPResponseBuilder`: `ControlServer` と `HookServer` に同名・別実装（JSON 用 / plain-text 用）。ステータスコード→テキストの switch がほぼ重複。
   - `ChatScaledFont`: `DashboardFeature` 内で private な同名 enum が 2 箇所（`ChatMessageCells.swift:693`・`RichMarkdownView.swift:178`）。
4. **依存の向き（当初「双方向」と記載）**: 「起動処理の下位層」という名前から期待される責務と実態が食い違っている疑い。〔**Phase 1 訂正 2026-07-09**: 双方向は誤り。実際は `AppBootstrap → DashboardFeature` の一方向・1 ファイルのみで循環なし。詳細は R3 の訂正ノート参照〕
5. **命名パターンの混在**: `DashboardFeature` 内に `*ViewModel`(5)・`*Store`(3)・`*Manager`(3)・`*Provider`(4)・`*Coordinator`(1)・`*Service`(1) が並存し、状態管理の役割語彙に統一基準が読み取れない。

### 既知の残債（過去 worklog から引き継ぎ）— Run 1（2026-07-08・delivery/0028）で更新

- ~~`ClaudeAgentKit` に既存テスト 5 件の red~~ → **存在しなかった**（Run 1 ベースライン実走で 78/78 green。`delivery/0026` の記載は陳腐化）。代わりに検出した PTYKit flaky テスト（openpty 並列割当レース）を根治済み（ADR 0054）。
- ~~`makeRestoreErrorSession` の `PHLOX_TOKEN` 欠落リスク~~ → **実バグと確定し修正済み**（再現テスト先行・runtime 再注入。Run 1 task-3）。
- GUI E2E（Layer B / XCUITest）は未着手（`specs/e2e-test-design.md` WP-E5〜E8）。GUI 配線の回帰保護が薄い（現存する残債）。

## 2. 適用する原理原則（すべての判断の基準）

| # | 原則 | 出典 | 本計画での適用 |
|---|---|---|---|
| P1 | **振る舞い保存はテストの傘で証明する** | Fowler『Refactoring』 | 傘のない箇所は特性化テストで現挙動を固定してから構造変更。「既存テストが数・内容とも無修正で green」を保存の証明とする |
| P2 | **情報隠蔽** — モジュールは「変化しやすい設計決定」を隠す | Parnas (1972) | 分割後の各モジュールが「隠している秘密」を 1 行で言語化できることを分割の合格基準にする |
| P3 | **Deep Module** — 単純なインタフェースの裏に機能を隠す | Ousterhout (2018) | 抽出のためだけの浅い層・浅い protocol を作らない。インタフェース数を増やさず実装を隠す |
| P4 | **依存性逆転（DIP）** | Martin (SOLID) | `AppBootstrap` ⇄ `DashboardFeature` の双方向依存は抽象を下層に置いて一方向化する |
| P5 | **概念的整合性** | Brooks | ADR 0001 の既定（MVVM + `@Observable` + SPM 分割、依存方向 Feature → Domain ← Data）を維持・徹底する。TCA / Clean Architecture への移行は**しない**（ADR 0001 が規模に見合わないと判断済み。本計画は既定への適合度向上であり、アーキテクチャ変更ではない） |
| P6 | **ビッグバン禁止・段階的置換** | Fowler (Strangler Fig) | 常に green を保つ小さなステップ。失敗したら分単位で戻せるコミット粒度 |
| P7 | **バグ修正とリファクタの分離** | Fowler | 別フェーズ・別コミット。混在させると退行時に切り分け不能 |
| P8 | **YAGNI** | — | 投機的な抽象・設定・「将来使うかも」の一般化を作らない |
| P9 | **テストは公開された振る舞いだけを検証** | testing ルール | 特性化テストも実装詳細（内部呼び出し順・private）ではなく観測可能な入出力に対して書く。red の green 化は実装修正のみ（テストを弱めない） |
| P10 | **定量評価** | ISO/IEC 25010 | before/after を同一ツールチェーンで計測し、改善と悪化の両方を報告する |
| P11 | **エージェントの自己申告を信用しない** | agentic-coding | マネージャーが自分のチェックアウトでテストを実走して green を確認してから完了とする |

## 3. スコープ / 非スコープ

### スコープ内

- 振る舞い保存の構造改善（§5 の To-Be に列挙）
- 特性化テスト・安全網テストの追加
- 既知バグの修正（Run 1 実績: PTYKit openpty レース・`makeRestoreErrorSession` の env 欠落。当初想定の ClaudeAgentKit red 5 件は実在せず）— **リファクタとは別コミット**（P7）
- 命名規約の定義と統一（ADR 起票）

### スコープ外（やらない）

- 新機能（モバイル残タスク `delivery/0018`、Liquid Glass UI `specs/liquid-glass-ui.md`、localization 拡張）
- `Vendor/SwiftTerm`（ローカル fork）の改変
- 性能最適化（ADR 0051〜0053 で直近対応済み。ただし退行しないことは検証ゲートで確認する）
- GUI E2E Layer B の本格導入（別計画 `specs/e2e-test-design.md` WP-E5〜E8 のまま。ただしその前提改修 T1/T2 を Stage 0 に含めるかは Phase 2 で判断 → §13）
- TCA / Clean Architecture への移行（P5）

## 4. 現状ベースライン概況

### パッケージ構成と規模（概算・監査時点）

| パッケージ | 行数 | 備考 |
|---|---|---|
| DashboardFeature | 19,006 | **全体の約 60%**。10 パッケージに依存するハブ |
| CodexAppServerKit | 1,883 | `AppServerTypes.swift` 605 行 |
| AgentDomain | 1,571 | 共有ドメイン層（Foundation 依存のみ・健全） |
| DesignSystem | 1,407 | |
| ClaudeAgentKit | 1,101 | **1 ファイルに全量** |
| TerminalUI | 920 | Vendor/SwiftTerm に path 依存 |
| MobileProxy | 817 | SPM 依存グラフから孤立（App 直リンクのみ） |
| PTYKit | 762 | |
| MessageStore | 656 | |
| StructuredChatKit | 655 | 共通 DTO 層（正本化の受け皿候補） |
| CursorAgentKit | 620 | |
| AppBootstrap | 618 | DashboardFeature と双方向依存 |
| ControlServer | 582 | |
| LocalHTTPServer | 573 | |
| HookServer | 310 | |
| **合計（App 除く）** | **約 31,481** | 179 ファイル |

依存方向の健全な部分: `AgentDomain`・`LocalHTTPServer`・`StructuredChatKit` は依存ゼロの最下層で、Feature → Domain ← Data の骨格は既に存在する。問題は最上位の `DashboardFeature` に責務が堆積していることに集中している。

### テスト態勢

- 全 15 パッケージにテストターゲットあり。ヘッドレス E2E（Layer A）は実装・マージ済みで、マージ前の実走が運用ルール（プロジェクト CLAUDE.md）。
- **Phase 0 実施済み（Run 1・2026-07-08・基準コミット d3fe765）**: テスト総数 1,568 件全 green（Stage 0 完了時点 1,598 件）・E2E Layer A 16 件 green・平均 CCN 2.7 / 警告関数 54 件（最悪 CCN 37 `ControlActionHandler.handle`）・重複率 9.76%（Sources+Tests）。確定値と再計測コマンドは `delivery/0028-rearchitecture-run1-worklog.md`。

## 5. 目標アーキテクチャ（To-Be）と改善項目

> 分割境界の最終確定は Phase 1（精読監査）→ Phase 2（実装前レビュー）を通す。ここでは方向と合格基準を定める。God ファイルの内部は本監査では未精読であり、下記の分割案は規模と配置から導いた仮説である。

### R1. `DashboardFeature` の分割（最重要・クロスカット）

- **方向**: `Session/`（42 ファイル、チャット/セッション UI）を `SessionFeature`（仮称）として分離し、`DashboardFeature` はダッシュボード一覧・チームタイムラインに縮退させる。共有状態・共有 UI 部品は既存の下層（`AgentDomain`・`DesignSystem`・`StructuredChatKit`）へ降ろす。
- **合格基準**（P2）: 分割後の各パッケージについて「隠している秘密」を 1 行で言えること。例 —「SessionFeature: 1 セッションの対話 UI と入力合成の詳細を隠す」「DashboardFeature: セッション群の俯瞰と選択の詳細を隠す」。
- **順序**: パッケージ分割は最後（Stage 2）。先にパッケージ内で God ファイルを分解し内部結合を切ってから、まとまったサブディレクトリを機械的に移動する（P6）。
- **Phase 1 訂正＋Run 2 進捗（2026-07-09）**: 監査で Session→Dashboard 方向の**実結合は 2 件のみ**（`TeamTimelineView`・`ResizeGripView`）と確定。両者は Run 2（task-13）で解消済み（TeamTimeline を `Dashboard/` へ移設・ResizeGripView を `DesignSystem` へ下層化）。残る `TeamTimelineView` の `DashboardViewModel` 依存（`sessionNodes` 1 プロパティ読み取り）の protocol 化のみ Run 3 の設計判断として残る。

### R2. God ファイルの分解（振る舞い保存）

- `ChatSessionViewModel.swift`（2,279 行）・`DashboardViewModel.swift`（2,002 行）: Extract Class / Split Phase で責務単位（変更理由単位）に分割。View から参照される公開面は維持。
- `DashboardView.swift`（1,342 行）・`ChatMessageCells.swift`（978 行）: private subview / computed property への抽出。**SwiftUI 制約を遵守**: view body 評価中の `@Observable` mutation 禁止（ADR 0010）、可変高リストは非遅延 VStack 既定（ADR 0030・L-14）。
- `ClaudeChatClient.swift`（1,101 行・1 ファイルパッケージ): ファイル分割 + 責務抽出（Run 1 時点で 78/78 green を確認済み）。
- **合格基準**: 分割は「変更理由が 1 つ」（SRP）になるまで。行数はシグナルであって目的ではない（浅いモジュールの量産は P3 違反）。

### R3. `AppBootstrap` ⇄ `DashboardFeature` 依存の評価

> **Phase 1 訂正（Run 2 蒸留・2026-07-09）**: 監査 8 本＋敵対的検証 3 本で「**双方向依存は実在しない**」と確定。実際は `AppBootstrap → DashboardFeature` の**一方向・1 ファイルのみ**で循環なし。よって本項の当初前提「双方向依存の解消／一方向化」は成立しない。Run 3 では *この一方向依存の妥当性評価*（下層に置くべき抽象があるか、名前と責務の食い違いの是正）に読み替える。当初の相互参照型の特定は不要。

- **方向**（P4）: 一方向依存（AppBootstrap→DashboardFeature）の妥当性を評価し、DashboardFeature が担うべきでない起動時責務があれば下層抽象（`AgentDomain` など）へ寄せる。設計確定時に ADR 起票。

### R4. 型重複の統合

- `FilePatchChange`: `StructuredChatKit` を正本とし、`CodexAppServerKit` は変換 or 直接利用へ（`kind` の型差 `JSONValue?` vs `String?` は契約差分なので、**機械的統合ではなく差分の意味を確認してから**。Phase 1 で裏取り）。
- `ApprovalDecision`: 正本パッケージの選定が必要（`ControlServer` は `AgentDomain` に依存済み、`CodexAppServerKit` は未依存。`AgentDomain` へ寄せて依存を 1 本足すか、`StructuredChatKit` に置くかは Phase 2 で決定・ADR 起票）。
- `HTTPResponseBuilder`: 共通部（ステータステキスト等）を `LocalHTTPServer` へ引き上げ、残る差分は役割が分かる名前に改名。
- `ChatScaledFont`: パッケージ内の単純な重複解消。

### R5. 命名規約の統一

- 状態管理の役割語彙（ViewModel / Store / Manager / Coordinator / Provider / Service）の使い分け基準を定義し（ADR 起票）、既存型を基準に沿って rename（Fowler: Rename / Change Function Declaration）。UI 文字列に波及する rename は `Localizable.xcstrings` の同時更新が必要（L-6）。

### R6. `App/` ターゲットの整理（小規模）

- `CompositionRoot.swift`（430 行）の手続き的 DI の見通し改善と、`App/ControlActionDashboard+DashboardViewModel.swift` のような App 側 extension の責務境界の明確化。**App/ の変更は隣接パッケージの `swift test` では検出できないため、必ず `xcodebuild` でリンク確認する**（L-17）。

## 6. 実施フェーズ

```
Phase 0 ベースライン → 1 並列監査 → 2 計画確定+実装前レビュー → 3 WP 分割
→ 4 並列ディスパッチ → 5 統合(マネージャー検証) → 6 最終検証 → 7 定量評価
```

各フェーズの完了条件を満たすまで次へ進まない。

### Phase 0: ベースライン確立 — **Run 1 で実施済み**（確定値は `delivery/0028`）

1. `dev` から作業ブランチを作成（`gitflow-start.sh rearchitecture --base dev`）。**HEAD ハッシュを記録**し、以降全エージェントの「正しい基底」とする。
2. 全 15 パッケージの `swift test` を実走し、**パッケージ別テスト数と green/red を記録**（振る舞い保存証明と Phase 7 の基準値）。
3. red があれば修正してから先へ進む（Run 1 実績: 想定されていた ClaudeAgentKit red 5 件は実在せず、代わりに検出した PTYKit flaky を根治した=ADR 0054）。
4. E2E Layer A を実走して green を記録(`PHLOX_E2E=1 swift test --package-path Packages/DashboardFeature --filter E2E --no-parallel`。実 Phlox 併走禁止・L-25)。
5. lizard（CCN）・jscpd（重複率）・`wc`（LOC・500 行超ファイル数）のスナップショットを保存。

**完了条件**: 全テスト green（または除外を明示）＋計測値の記録。

### Phase 1: 並列監査（精読）

- パッケージ単位で監査エージェントを並列起動し、スメル・テスト欠落・R1〜R6 の裏取り（相互参照型の特定、`FilePatchChange` の `kind` 型差の意味、God ファイルの責務境界）を **file:line とシンボル名必須**で収集する。
- 高重要度の指摘は**別エージェントによる敵対的検証**（「指摘は誤りだと仮定して実コードで裏取りせよ」）を通し、誤検出を落とす。指摘の基準コミットを記録する。
- 検証済み指摘は共有コンテキストとしてファイル保存（worktree から参照できる共有パスに置く）。

**完了条件**: R1〜R6 それぞれについて「実施可能・要修正・棄却」の判定が根拠付きで揃う。

### Phase 2: 計画確定 + 実装前レビュー

- 指摘を「①安全網テスト → ②バグ修正（再現テスト先行）→ ③構造（振る舞い保存）→ ④性能 → ⑤テスト品質」の順に編成し、WP 分割ドラフト（§7)を確定版に更新する。
- **Codex による実装前レビュー**を実施(`$PHLOX_CLI spawn --kind codex`、プロジェクト CLAUDE.md の規定)。計画全文・前提・観点を 1 メッセージで渡す。
- 設計判断（R1 の分割境界・R3 の抽象配置・R4 の正本選定・R5 の語彙基準）を ADR として「提案中」で起票。

**完了条件**: レビュー指摘を反映した確定版計画と ADR ドラフト。

### Phase 3: WP 分割

分割原則（全 WP に適用）:

1. **ファイル所有権の排他**: 各 WP に編集可能パスを明示列挙し、WP 間で重複させない。スコープ外の問題は「編集せず報告のみ」。
2. **ビルド単位の直列化**: 同一パッケージを触る WP は並列禁止（L-5）。サブディレクトリで排他しつつ直列チェーンにする。
3. **公開 API 凍結**: 他モジュールから参照される public シンボルのシグネチャ変更禁止。必要なら「提案として報告」。
4. **クロスカット項目の隔離**: 複数パッケージにまたがる変更（R1 のパッケージ分割・R3・R4）は並列 WP から除外し、Stage 2 で単独実施。
5. WP 内の作業順序はフェーズ規律（テスト → バグ → 構造 → 性能）を維持。

### Phase 4: 並列ディスパッチ

- 実装は `wp-implementer` エージェント（定義済み）に WP 単位で委譲。worktree 隔離時は `gitflow-start.sh` で作成し、**worktree では先に `xcodegen generate` が必要**（`Phlox.xcodeproj` は生成物・L-26）。
- ディスパッチプロンプト必須要素: ①基底確認（`git log --oneline -1`、違えば `git reset --hard <基底>`）②共有パスの計画書・検証済み指摘 ③編集可能パスの明示列挙 ④順序付き作業項目（file:line・完了条件）⑤チェックポイント義務（主要項目 1 つ green ごとに `git add -A && git diff --cached > <共有パス>/<WP>.patch` を上書き保存。コミット禁止）⑥検証コマンドとベースライン数 ⑦誠実報告形式。
- 各エージェントは自パッケージのテストのみ実行（ビルド競合防止）。タイミング敏感テストは負荷併走下で走らせない（L-20）。

### Phase 5: 統合（マネージャー検証）

- パッチは `git apply --check` で適用可能性を先に確認。適用不能は基底ずれのシグナルであり、黙って force しない。
- 適用後、**マネージャー自身が全対象パッケージのテストを実走**し、エージェントの green 報告と突き合わせる（P11）。
- ファイル削除を含むパッチ適用後は `swift package clean` でキャッシュを掃除してから再判定（stale キャッシュの偽失敗対策）。
- フルビルド（リンク確認）は実装エージェントが residual にいない状態で 1 回。クロスカット項目（Stage 2）はこの後に実施し、影響パッケージを再テスト。

### Phase 6: 最終検証

1. 全パッケージテスト一括（ベースライン + 追加分が全 green、数を記録）。
2. `xcodebuild` フルビルド（App/ を含むリンク確認）。
3. E2E Layer A（`--no-parallel`・実 Phlox 併走禁止）。
4. Debug 実機スモーク 1 回: `open --env PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1 /tmp/PhloxBuild/Build/Products/Debug/Phlox.app`（Keychain 非接触）。**UI/描画に触れた変更は `swift test` green では完了と言えない**（ADR 0010/0030）— 実 Debug を起動し、対象パネル表示後の CPU 収束（`top -l N -s 2 -pid`）まで確認する。
5. 完了報告は計画の全項目を列挙し、実施 / 未実施 / 意図的見送りを明示。

### Phase 7: 定量評価

before（Phase 0 スナップショット）/ after を同一ツールチェーンで計測し、悪化・未改善も同じ表に載せる。

| サブ特性 | 指標 | ツール | 目安 |
|---|---|---|---|
| Modularity | パッケージ数 / 500 行超ファイル数 / 最大ファイル行数 / DashboardFeature の行数比率 | wc | クラス < 500 行 |
| Analysability | 平均 CCN / 警告関数数（CCN>10 or >60 行）/ 最悪関数 | lizard | 関数 CCN < 10 |
| Modifiability | 重複コード率 / 重複型定義の数（監査時点: FilePatchChange・ApprovalDecision・HTTPResponseBuilder・ChatScaledFont の 4 系統） | jscpd + 手動 | < 5% |
| Testability | テスト数 / 特性化テストで初めて守られた領域の列挙 | swift test | — |
| 信頼性 | 修正バグ数（全件に再現テスト） | 修正記録 | — |

解釈の規律: ソース LOC の増加は失敗ではない（重複率が同時に下がっているかで判別）。平均値だけで語らず最悪関数の解消を報告する。SwiftUI ビルダー構文の見かけの長さ（CCN 1）と本物の複雑関数を区別する。

## 7. ワークパッケージ分割ドラフト

> Phase 2 のレビューで確定させる暫定版。基底コミット・検証ベースライン数は Phase 0 の値で確定記入する。

### Stage 0: 安全網（直列・並列実装の前提）— **Run 1 で実施済み**（WP-0a は前提消滅により PTYKit flaky 根治へ差し替え。結果は `delivery/0028`）

| WP | 内容 | 検証 |
|---|---|---|
| WP-0a | ~~ClaudeAgentKit red 5 件の解消~~ → PTYKit flaky 根治に差し替え（ADR 0054） | PTYKit 連続 10 回 `swift test` 全 green |
| WP-0b | `makeRestoreErrorSession` の `PHLOX_TOKEN` 欠落 env 再 spawn の裏取りと修正（再現テスト先行） | 再現テスト red→green |
| WP-0c | God ファイル分解対象の特性化テスト追加（`ChatSessionViewModel`・`DashboardViewModel` の観測可能な振る舞いを固定。実装詳細は検証しない・P9） | DashboardFeature `swift test` green・追加数記録 |

### Stage 1: 並列トラック（所有権排他）

| WP | スコープ（編集可能パス） | 内容 | 直列制約 |
|---|---|---|---|
| WP-A | `Packages/ClaudeAgentKit/**` | R2: `ClaudeChatClient.swift` の分割 | WP-0a 完了後 |
| WP-B | `Packages/CodexAppServerKit/**` | R2: `AppServerTypes.swift`(605 行) の整理（`FilePatchChange` の統合は Stage 2 へ持ち越し・報告のみ） | なし |
| WP-C1→C2→C3 | `Packages/DashboardFeature/Sources/.../Session/**` → `Dashboard/**` → その他 | R2: God ファイル分解。**同一パッケージのため直列チェーン**（L-5） | WP-0c 完了後・C1→C2→C3 の順 |
| WP-D | `App/**` | R6: CompositionRoot 整理 | 検証は `xcodebuild`（L-17） |

### Stage 2: クロスカット（Stage 1 完了後・単独エージェントまたはマネージャー直轄・直列)

| 項目 | 内容 |
|---|---|
| ビルドゲート | フルビルドでリンク確認（マネージャー） |
| R4 型統合 | `FilePatchChange` → StructuredChatKit 正本化、`ApprovalDecision` 正本化、`HTTPResponseBuilder` 共通部の LocalHTTPServer への引き上げ |
| R3 依存解消 | `AppBootstrap` ⇄ `DashboardFeature` の一方向化（ADR 承認後） |
| R1 パッケージ分割 | `Session/` の `SessionFeature`（仮称）切り出し。`Package.swift`・`project.yml`・App リンクの更新を含む |
| R5 命名統一 | 語彙基準 ADR に沿った rename（`Localizable.xcstrings` 同時更新・L-6） |

### Stage 3: 最終検証（Phase 6 に同じ）

## 8. 検証ゲートと完了条件

- **WP 単位**: 自パッケージ `swift test` green（ベースライン数 + 追加分）。エージェント報告はマネージャーの実走で裏取り（P11）。
- **統合**: 全パッケージテスト → フルビルド → E2E Layer A green。
- **UI 変更を含む WP**: `ImageRenderer` オフスクリーン描画での見た目確認（プロジェクト CLAUDE.md の手順）＋ Phase 6 の実機 CPU 収束確認。
- **マージ**: feature → dev は安全順マージ（先に feature 側で dev を取り込み green 確認 → `gitflow-merge.sh`）。dev へのマージ承認・コミット実行はユーザー承認を得る。
- **done の定義**: 計画全項目の実施 / 未実施 / 意図的見送りの列挙 + Phase 7 の定量評価レポート（`docs/delivery/` に worklog として蒸留）。

## 9. リスクと対策

| リスク | 根拠 | 対策 |
|---|---|---|
| SwiftUI の無限再無効化・CPU 固着は `swift test` green でも混入する | ADR 0010 / 0030 の実績 | UI 変更 WP は実 Debug 起動 + CPU 収束確認を完了条件に含める。body 内 `@Observable` mutation 禁止・非遅延 VStack 既定（L-14）を wp-implementer の規律に明記 |
| worktree の基底ずれで「正しい作業」が全滅 | agentic-coding 実績 | 全ディスパッチの最初に基底確認を義務化 |
| 同一パッケージ並列でビルドキャッシュ競合 | L-5 | パッケージ内はサブディレクトリ排他の直列チェーン |
| エージェント死亡で作業消失 | agentic-coding 実績 | 項目ごとのチェックポイントパッチ上書き保存を義務化。死んだら後継に「パッチ適用→現状把握→続行」 |
| worktree ビルドの Debug 版が生きたまま worktree を消すと全セッションの hook が壊れる | プロジェクト CLAUDE.md | worktree 削除前に `ps aux | grep Phlox.app` を確認。クリーンアップは `gitflow-cleanup.sh`（マージ済み・クリーン以外は停止） |
| E2E flaky | PTY settle 窓 400ms | `--no-parallel`・実 Phlox 併走禁止（L-25）・他ビルドと並行させない（L-20） |
| 公開 API 凍結違反による並列 WP の意味的衝突 | agentic-coding 実績 | 凍結を規律化し、変更が必要なら「提案として報告」のみ許可 |
| `Phlox.xcodeproj` は生成物で worktree に無い | L-26 | worktree では先に `xcodegen generate` |
| rename による英語ロケール回帰 | L-6 | UI 文字列 rename は `Localizable.xcstrings` を同時更新 |

## 10. ADR 起票ポイント（Phase 2 で「提案中」起票）

1. `DashboardFeature` 分割の境界と新パッケージ構成（R1）
2. `AppBootstrap` 依存一方向化の抽象配置（R3）
3. 共有型の正本パッケージ規約 — どの種類の型をどの層に置くか（R4）
4. 状態管理の役割語彙基準 — ViewModel / Store / Manager 等の使い分け（R5）

## 11. 体制とブランチ運用

- **マネージャー**（メインセッション）: 計画・分解・委譲・統合・検証。直轄実装は数行規模のみ。
- **実装**: `wp-implementer`（定義済みエージェント）。高難度の設計相談・実装前レビューは Codex（`$PHLOX_CLI spawn --kind codex`）。
- **ブランチ**: `dev` → `feature/rearchitecture`（`gitflow-start.sh`）。WP の worktree 隔離もスクリプト経由。バグ修正とリファクタはコミット分離（P7）、コミットメッセージは日本語、コミット・マージはユーザー承認を得る。

## 12. 未確定事項（Phase 1〜2 で確定）

1. R1 の分割境界（`Session/` 42 ファイルの精読後。`SessionFeature` 1 個か、さらに `Composer` 系を分けるか）
2. R3 の具体設計（相互参照している型の特定が先）
3. R4 `ApprovalDecision` の正本パッケージ（`AgentDomain` へ依存追加 vs `StructuredChatKit`）
4. E2E Layer B 前提改修（T1: `PHLOX_DATA_DIR`・T2: UserDefaults suite 差し替え）を Stage 0 に含めるか — GUI 配線の回帰保護が薄いまま R1 を実施するリスクと、スコープ肥大のトレードオフ。**ユーザー判断を仰ぐ**
5. `MobileProxy` の位置づけ（SPM グラフから孤立・App 直リンクのみ。統合か現状維持かは要件次第で、本計画では現状維持を既定とする）

## 13. 参照

- 手順の正本: `agentic-coding` スキル `references/large-scale-refactoring.md`
- 設計原則: `software-design` スキル（Parnas / Ousterhout / Fowler / ISO 25010）
- 既存決定: ADR 0001（初期アーキテクチャ）・0010/0030（SwiftUI 教訓）・0020（Loopflow 削除 = 過去の大規模削除実績）・0033（責務分離）・0041（CLI 縮退）
- 過去の監査対応: `delivery/0025`〜`0027`（3-PM 体制の監査 remediation）
- テスト戦略: `specs/e2e-test-design.md`
