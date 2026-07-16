---
status: active
last-verified: 2026-07-09
---

# ADR 0057: `FilePatchChange` の wire デコード型とドメイン型を分離したまま据え置く（R4-1）

> **このファイルの役割**: Run 3 リファクタリング R4-1 で、`CodexAppServerKit` と `StructuredChatKit` に
> それぞれ定義された同名構造体 `FilePatchChange` を「見かけの重複」として機械統合せず、役割の異なる
> 2 型（wire デコード型 / 共有ドメイン型）として据え置く判断と根拠を記録する。
> **書かないもの**: 実装経緯・作業ログ（→ `delivery/0030`）。型定義の現行事実の一覧（→ `architecture/`）。

## 文脈

- rearchitecture 計画は R4 で「型重複の統合」を掲げ、`FilePatchChange` を統合候補（監査時点 4 系統の 1 つ）に挙げた。
  計画 line 132 は「`kind` の型差 `JSONValue?` vs `String?` は契約差分なので、**機械的統合ではなく差分の意味を
  確認してから**」と条件を付し、WP-B（Stage 1）は「統合は Stage 2 へ持ち越し・報告のみ」とした。
- Phase 1 相当の裏取り（2026-07-09）で、2 型の実態が確定した:
  - `Packages/StructuredChatKit/Sources/StructuredChatKit/StructuredChatTypes.swift:3-13`
    — `FilePatchChange { path: String; diff: String; kind: String? }`（`Codable`）。**共有ドメイン型**。
    11 ファイル（SessionFeature/ClaudeAgentKit/CursorAgentKit/AppBootstrap/DashboardFeature ほか）が直接使用。
  - `Packages/CodexAppServerKit/Sources/CodexAppServerKit/AppServerCommonTypes.swift:340-350`
    — `FilePatchChange { path: String; diff: String; kind: JSONValue? }`（`Codable`）。**codex app-server の
    wire デコード型**。参照は CodexAppServerKit 内 3 ファイルに閉じる（`AppServerCommonTypes`・`Notifications`・
    `CodexAppServerClient`）。
- `kind: JSONValue?` は codex app-server の通知 JSON をデコードする際、`kind` が文字列以外（object/array/number/
  bool/null）で来ても**例外を投げずに保持する寛容性**のために使われている。唯一の消費点
  `CodexAppServerClient.swift:402` で `kind: $0.kind?.stringValue` によりドメイン型へ写像し、`.stringValue` は
  文字列以外を問答無用で `nil` に潰す（`JSONValue.swift:53-56`）。すなわち **CodexAppServerKit の境界を出た瞬間、
  `kind` は常に `String?`** であり、パッケージ外へ生の `JSONValue` が漏れる経路は存在しない。

## 決定

**2 型を統合せず、役割の異なる別型として据え置く。** R4-1 として実施するソース変更は **なし**。

- `StructuredChatKit.FilePatchChange`（`kind: String?`）= **共有ドメイン型**。Phlox のチャット表示・各クライアントが
  使う正本。変わる理由は「Phlox のチャットモデルの変化」。
- `CodexAppServerKit.FilePatchChange`（`kind: JSONValue?`）= **codex app-server プロトコルの wire デコード型**。
  変わる理由は「codex 側 wire プロトコルの変化」。CodexAppServerKit 内に閉じ、境界でドメイン型へ写像する。

両者はフィールド名こそ一致するが**変更理由（変化の軸）が異なる**——Parnas の情報隠蔽に従えば、codex wire の
デコード寛容性は CodexAppServerKit の境界内に隠すべき詳細であり、共有ドメイン型へ漏らすべきではない。したがって
「見かけの重複」であって「真の重複」ではない。

## 棄却した案

- **`StructuredChatKit` を正本に統合し `CodexAppServerKit` 版を削除する**（計画 line 251 の素朴解釈）:
  正本の `kind: String?` は合成 `Codable` のため、wire が `kind` を非文字列で送ると**デコード例外を投げ、
  `FilePatchUpdated` 通知のパース全体が失敗する**（振る舞い退行＝メッセージ欠落）。現状この decode を守る
  特性化テストが無く、安全網なしの wire プロトコル変更となる。振る舞い保存の要件（Fowler・P9）を満たせないため棄却。
- **正本型に寛容デコード（非文字列 `kind`→`nil`）を足して統合する**（task-28 案）: 振る舞い保存は達成できるが、
  codex 固有の wire 寛容性を**共有ドメイン型へ恒久的に持ち込む**ことになる。共有型が特定クライアントのプロトコル
  都合で複雑化するのは、上記「情報隠蔽」の逆行。得られるのは重複型カウント −1 のみで、代償（凝集低下・
  共有型への codex 結合）が上回るため棄却。ユーザー裁定（2026-07-09）でも本 ADR 起票（据え置き）を選択。

## 帰結

- R4 の重複型統合は **ApprovalDecision（→ AgentDomain 正本化・ADR 相当実施済み・task-22）**、
  **HTTPResponseBuilder 共通部（→ LocalHTTPServer へ `HTTPStatusText`/`HTTPResponseSerializer` を引き上げ・task-16）**、
  **ChatScaledFont（Run 2 で統合）** の 3 系統で完了。`FilePatchChange` は本 ADR により「役割分離を明文化して
  据え置く」で決着し、監査時点 4 系統の型重複は**実質的に解消**（残る 1 は真の重複ではないと確定）。
- フォローアップは不要。将来 codex wire が `kind` を非文字列で恒常的に送るようになった場合のみ、ドメイン型側の
  `kind` 表現を再検討する（その時は本 ADR を supersede する新 ADR を起こす）。
