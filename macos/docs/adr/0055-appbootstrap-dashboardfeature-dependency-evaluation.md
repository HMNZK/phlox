---
status: active
last-verified: 2026-07-09
---

# ADR 0055: `AppBootstrap → DashboardFeature` 一方向依存の妥当性評価（R3）

> **このファイルの役割**: Run 3 リファクタリング R3 で、`AppBootstrap` と `DashboardFeature` の依存関係を
> 監査で確定した事実（双方向ではなく一方向・1 ファイル・循環なし）に基づいて評価し、「下層へ降ろすべき
> 抽象があるか」「名前と責務の食い違いをどう扱うか」の判断を記録する。
> **書かないもの**: 実装経緯・作業ログ（→ `delivery/`）。命名規約そのものの正本（→ R5 の命名 ADR）。

## 文脈

- 当初の rearchitecture 計画は R3 を「`AppBootstrap ⇄ DashboardFeature` の**双方向**依存を一方向化する」と
  記載していた。しかし Phase 1（Run 2 蒸留・2026-07-09）で監査 8 本＋敵対的検証 3 本により
  **双方向依存は実在しない**と確定した。実態は次のとおり:
  - **ソース依存は `AppBootstrap → DashboardFeature` の一方向のみ・循環なし**。
  - この方向の結合は **1 ファイルだけ**: `Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift`
    が `import DashboardFeature` している。
- `ControlActionHandler` が DashboardFeature から使うシンボルは以下に限られる（`file:line` は 2026-07-09 時点）:
  - `DashboardViewModel.SendOutcome` / `.ReadinessResult` / `.DoneResult`（ネスト型。ControlActionHandler.swift:41,50,55,260,298,309）
    — `ControlActionHandling` プロトコル要件の入出力型として現れる。
  - `ChatItem`（DashboardFeature の表示モデル）を wire DTO へ写像する（同 415）。
- `ControlActionHandling` プロトコルの**適合（witness）は App 層**にあり、本体で `DashboardViewModel` が適合する
  （ControlActionHandler.swift:31 の注記）。テストではモックを注入する。すなわち **依存性逆転は App 境界で
  すでに効いている**——AppBootstrap 自身は具象 `DashboardViewModel` を生成・保持せず、プロトコル越しに使う。
- 加えて、テストターゲットに**テスト専用の逆向きエッジ**が 1 本ある: `DashboardFeatureTests → AppBootstrap`
  （`E2EControlServerTests.swift` が `import AppBootstrap` かつ `@testable import DashboardFeature`）。これは
  ソースの依存グラフには現れない（テストターゲット間のみ）。

## 決定

1. **一方向ソース依存 `AppBootstrap → DashboardFeature` はそのまま受容する**（`要修正` ではなく `実施可能だが不要`）。
   循環はなく、`ControlActionHandling` の依存性逆転が App 境界で成立しているため、構造上の負債はない。
   `ControlActionHandler` は「ControlServer からの制御要求を、稼働中セッションの操作（DashboardViewModel）へ
   翻訳する **制御プレーンのアダプタ**」であり、DashboardFeature の**上**に立つのが責務上正しい。
2. **`SendOutcome` / `ReadinessResult` / `DoneResult` を下層（AgentDomain 等）へ降ろさない**。これらは
   DashboardViewModel の**操作結果語彙**であって、汎用ドメイン型ではない。下層へ移すと「操作の意味を持たない
   下層に操作結果型が居座る」逆転を生む（浅いモジュール化・P3 のスメル）。所有は DashboardViewModel のままとする。
3. **真のスメルは構造ではなく命名**として切り出す: `AppBootstrap` という名前は「起動処理の基盤層」を示唆するが、
   実体（`ControlActionHandler`）は DashboardFeature の上に立つアダプタである。名前と責務の食い違いは
   **R5（命名規約）の対象**として引き継ぐ（本 ADR では改名を実施しない——改名は Localizable/App リンク波及を
   伴うため R5 の語彙基準確定後にまとめて行う）。
4. **テスト専用逆エッジ（`DashboardFeatureTests → AppBootstrap`）は受容する**。`E2EControlServerTests` は
   ControlServer + DashboardViewModel を跨ぐ **エンドツーエンド統合テスト**であり、両者の上に立って両方へ依存するのが
   本質。これを AppBootstrapTests へ移すと (a) 共有ハーネス `E2ETestSupport.swift`（他 4 本の E2E も使用）から
   切り離れ、(b) 文書化済みのマージ前ゲート `swift test --package-path Packages/DashboardFeature --filter E2E` の
   対象から外れて E2E ハーネスが分断される。害（テスト専用エッジ）に比してコストが高く、**移動しない**。

## 棄却した案

- **`AppBootstrap` を DashboardFeature に依存させない（結果型を下層へ移動）**: 上記決定 2 の理由で棄却。
  操作結果語彙を汎用下層へ押し込むのは責務の逆転で、可読性・凝集を下げる。
- **本 ADR 内で `AppBootstrap` を改名**: 改名は `Localizable.xcstrings`・`project.yml`・App リンク・
  import 全書き換えに波及する。R5 の語彙基準（層アダプタの命名）が未確定な段階で単発改名すると二度手間。
  R5 へ引き継ぐ。
- **テスト逆エッジ除去のため `E2EControlServerTests` を AppBootstrapTests へ移動**: 上記決定 4 の理由で棄却。

## 帰結

- R3 の判定は「**構造は受容（循環なし・逆転成立済み）／命名の食い違いのみ R5 へ引き継ぐ**」で確定。R3 として
  実施するソース変更は **なし**。
- Run 3 の依存グラフに関する未解決事項は残らない（双方向依存という当初前提は事実誤認だったと本 ADR が確定）。
- フォローアップ: `AppBootstrap` の命名（またはアダプタ責務の切り出し）は R5 命名 ADR で扱う。
