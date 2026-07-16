---
status: active
last-verified: 2026-07-09
---

# ADR 0056: 状態管理の役割語彙（ViewModel / Store / Manager / Provider / Coordinator / Service）（R5）

> **このファイルの役割**: `DashboardFeature`（および派生パッケージ）で状態・振る舞いを担う型の
> **役割サフィックスの使い分け基準**を定義し、将来のドリフトを防ぐ。Run 3 R5 の判定＝「既存はほぼ準拠、
> 大量 rename は不要。基準を明文化し、以後の逸脱のみ是正する」の根拠。
> **書かないもの**: 個別型の実装詳細。`AppBootstrap` の命名（→ [ADR 0055](0055-appbootstrap-dashboardfeature-dependency-evaluation.md) の引き継ぎ事項。別途検討）。

## 文脈

- 監査（Phase 1）で `DashboardFeature` 内に役割サフィックスが 6 種並存すると指摘された:
  `*ViewModel`・`*Store`・`*Manager`・`*Provider`・`*Coordinator`・`*Service`。「基準が読み取れない」懸念。
- 2026-07-09 の棚卸しで実体を確認したところ、**各サフィックスは概ね一貫した役割に対応しており、
  誤解を招く命名は乏しい**:
  - ViewModel: `DashboardViewModel` `SessionViewModel` `ChatSessionViewModel` `SessionTreeViewModel`（`@Observable` の UI 状態ハブ）
  - Store: `TranscriptStore`/`FileTranscriptStore`/`NoOpTranscriptStore` `ComposerAttachmentStore` `TeamTimelineStore` `LastUsedChatSettingsStore`（永続化・状態コンテナ）
  - Manager: `CodexHooksManager` `CodexUserHooksManager` `CursorHooksManager`（外部フックファイルのライフサイクル管理）
  - Provider: `UsageProvider` 系（`Claude/Codex/Cursor/Empty/Preview...`）`CursorModelListProvider`（外部データの供給元）
  - Coordinator: `SessionPersistenceCoordinator` `SessionRestoreCoordinator`（多段の永続化/復元の手順を統括）
  - Service: `MessagingService` `SessionSpawnService`（横断的な操作の実行）
- よって R5 は「命名の混乱の是正」ではなく「**既に成立している語彙の明文化（規約化）**」が本質。

## 決定

**役割サフィックスの基準を次のとおり定義する**（型の「隠している秘密」＝責務で選ぶ。P2）:

| サフィックス | 使う条件（隠す秘密） | 使わない条件 |
|---|---|---|
| **ViewModel** | View が観測する `@Observable` な UI 状態のハブ。1 画面/1 コンポーネントの表示状態と入力ハンドリングを持つ | UI 非依存のドメインロジック → 純関数/ドメイン型へ |
| **Store** | データの保持・永続化・読み書きの詳細を隠す（メモリ/ファイル/UserDefaults）。CRUD 的な状態コンテナ | 手順の統括や外部プロセス管理 → Coordinator/Manager |
| **Provider** | 外部（CLI・API・計測）から**読み取り専用データを供給**する源。差し替え可能な実装が複数（Empty/Preview 含む） | 書き込み・永続化を伴う → Store |
| **Manager** | 外部リソース（フックファイル等）の**ライフサイクル**（生成/更新/削除）を管理する | アプリ内状態の保持 → Store。汎用の受け皿名として乱用しない |
| **Coordinator** | 複数の下位コンポーネントに跨る**多段の手順**を統括する（永続化/復元のオーケストレーション） | 単一責務の操作 → Service |
| **Service** | 副作用を伴う**横断的な操作**を実行する（メッセージ送信・spawn）。状態を主に持たない | 状態保持が主 → Store/ViewModel |

**適用方針（rename の可否）**:
- **既存型の大量 rename は行わない**。棚卸しの結果、上表への準拠度が高く、rename の便益（軽微な一貫性向上）に
  対して import・`Localizable.xcstrings`・App リンクへの波及コストと回帰リスクが見合わない（P3・churn 回避）。
- 以後、**新規型は本基準に従う**。既存型で本基準に**明確に反する**もの（名前が責務を誤認させる）が見つかった
  場合に限り、単発 rename で是正する。現時点で該当する明白な違反は検出していない。

## 棄却した案

- **6 サフィックスを 2〜3 種へ統合する大規模 rename**: 一貫性の名目で数十型を横断改名すると、公開 API の
  破壊・`Localizable` 同時更新・App リンク更新の波及が大きく、振る舞い保存の検証負荷に見合わない。基準の
  明文化で将来ドリフトは防げるため不要（趣味的統一の churn を作らない）。
- **`Manager` を全廃**（「Manager は責務が曖昧になりがち」という一般論）: 実体（フックファイル管理）は
  ライフサイクル管理として一貫しており、誤認を招いていない。一般論で機械的に消さない。

## 帰結

- R5 の判定は「**基準を明文化（本 ADR）／既存 rename は不要／新規と明白な違反のみ本基準で是正**」で確定。
  R5 として実施するソース rename は **なし**。
- 将来この語彙に反する型が導入されたら、レビューで本 ADR を根拠に是正する。
- `AppBootstrap` の命名（ADR 0055 からの引き継ぎ）は「層の責務を表す名前か」の観点で別途検討する（本 ADR の
  役割サフィックス基準とは別軸＝パッケージ名の問題のため、ここでは扱わない）。
