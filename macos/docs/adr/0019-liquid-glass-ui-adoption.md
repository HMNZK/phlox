---
status: active
last-verified: 2026-07-04
---

# ADR 0019: UI を Apple Liquid Glass へ刷新する（機能層限定・macOS 26 条件採用）

- ステータス: 採択（2026-06-28・設計確定 / Codex レビュー反映 rev.2）— **実装未着手**
- last-verified: 未実装のため該当なし
- 関連: `docs/specs/liquid-glass-ui.md`（実装プラン・用語）, `docs/architecture/design-system.md`（実装対応の正典。実装完了時に追記更新）, ADR 0010 / 0011（loopflow kanban の描画・ライフサイクル）

> 「UI 全体を Apple のグラスリキッド（Liquid Glass）へ刷新したい」という要望に対する採用方針。Apple の Liquid Glass は**機能層専用のマテリアルで macOS 26（Tahoe）以降専用 API**である一方、Phlox は最低対応 macOS 14・主コンテンツがターミナル文字のダッシュボードである。本 ADR で「どこに・どの OS で・どう適用するか」を決める。

> **改訂 (2026-06-29 / gate② 再計画 — 重要)**: pilot 実機検証＋Web リサーチ(WWDC25 Session 219＋出荷実装者)により、本 ADR の**「クロームのペイン背景を `glassEffect` でガラス化する」前提が誤りと判明**。Liquid Glass は背後コンテンツをレンズ屈折して見栄えを作るため、(a) 平坦で暗い下地＝屈折原資ゼロ、(b) ペイン全面＝構造/コンテンツ層への適用(Apple が明示的に避けよとするパターン)、(c) 大面 tint、で flat 化する。**是正後のモデル**: glass は「コンテンツ上に浮かぶ小さなコントロール層」に限定、ペインは material/solid、コンテンツは `backgroundExtensionEffect`/scroll-under でコントロール背後へ潜らせる、rim/sheen の手作りは撤去(fighting the API)、暗色ターミナル背景では本物 glass も仕様上控えめ。詳細は decision-log(2026-06-29)。**下記「決定」のうち適用面に関する 1/3/4/5 は是正モデルで読み替えること**(OS 戦略・可用性集約・アクセシビリティ・検証の枠組みは有効)。

## コンテキスト

- 要望: UI 全体を Apple Liquid Glass へ刷新（参照: developer.apple.com/documentation/technologyoverviews/liquid-glass）。
- API 制約: 本物の `glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)` / 標準コントロールの自動採用は **macOS 26.0+ 専用**。Phlox の最低対応は **macOS 14.0**（`project.yml:6`, 各 `Package.swift`）。
- コンテンツの性質: 主コンテンツはターミナル/ログの**密なモノスペース文字**（AppKit `NSView` / SwiftTerm）。Apple は「ガラスは機能層（ツールバー・ナビ・操作・一時 UI）専用、リスト/メディア/本文などコンテンツ層には適用しない」と規定。**文字 on glass・glass-on-glass はアンチパターン**（可読性低下）。
- 既存実装: `.preferredColorScheme(.dark)` で forced dark（`PhloxApp.swift:78`）、全6テーマ暗色。マテリアルは未使用（`DSColor` 単色塗り＋`DSShadow`）。
- 検証環境: 開発機は macOS 26.3.1 / Xcode 26.2 / Swift 6.2.3（macOS 26 SDK）。VM ツール不在。

## 決定

1. **適用範囲は機能層クローム限定**。ターミナル/ログ本体・ターミナルを内包するタイル/シェルは不透明・高コントラスト維持。
2. **OS 戦略: 最低対応は macOS 14 据え置き**。`if #available(macOS 26, *)` で **26+ は本物ガラス / <26 は既存の見た目を再現**。
3. **可用性分岐は DesignSystem の glass 層に閉じ込める**。`glassContainer` / `glassIdentity` / `glassSurface` family の薄い wrapper 群を新設し、`#available` を call site・他パッケージへ漏らさない（`GlassEffectContainer`・`glassEffectID` も macOS 26+ 専用のため wrapper 化する）。**<26 の見た目等価は「構造保証」ではなく before/after スナップショットで検証する**。`glassSurface` は fill だけでなく既存の shadow/stroke を fallback で再現し、accent bar/pill 等の意味的 overlay は両系統で維持する。
4. **テーマ×ガラス**: 下地レイヤー（ペイン背景・ターミナル・不透明な列/タイル）はテーマ単色のまま。ガラスクロームは暗い `.regular` ＋テーマごとの低不透明度・低彩度 tint（`glassTint`）を一様適用。装飾目的の面別 tint は禁止。
5. **カンバン**: 列は不透明（現状・`DSColor.surface`）、カード本体のみガラス（fill は `surfaceElevated`）。列ごとに `glassContainer` でまとめ、折畳⇄展開は `glassIdentity` で morph。
6. **AppKit/SwiftTerm 合成**: glass surface は `TerminalView` の bounds と重ねない（上部 chrome は予約 gutter）。既に操作系は NSView 被りを overlay 前面化で回避している（`DashboardView.swift:201-202`）。やむを得ず重なる箇所は macOS 26 実機でターミナル出力中・リサイズ中・グリッド切替中の描画を gate にする。
7. **アクセシビリティ**: glass 層が `accessibilityReduceTransparency`（不透明 fallback）と `colorSchemeContrast == .increased`（border/scrim 強化）を**自前で処理**する（自動適応任せにしない）。`glassTint` は実機でコントラスト/可読性の合格基準を満たすまで採用しない。
8. **標準コントロール / Info.plist**: 標準部品（segmented picker・borderedProminent 等）は 26 SDK 自動採用に委ね、カスタム置換しない。**Info.plist の Liquid Glass opt-out は設定しない**（26+ でガラスを得るのが目的）。
9. **スコープ OUT**: アプリアイコン刷新 / ライトモード対応 / ネイティブ window-toolbar 移行 / コンテンツ層・本文・カンバン列・グリッドタイル・ターミナル内包シェルのガラス化。
10. **検証**: 26+ 経路は開発機（macOS 26.3.1 / Xcode 26.2）で実機検証（全6テーマ ×{Reduce Transparency / Increased Contrast}× 主要画面 × ターミナル出力/リサイズの matrix）。**<26 経路はコンパイル検証＋スナップショット等価のみ（VM 不在のため実機未検証と明記）**。既存 E2E は visual/AppKit/a11y を検出しないことを前提に、各面は実 Debug 目視を done 条件とする。

## 結果

- 既存 macOS 14/15（Sonoma/Sequoia）ユーザーは**現状 UI のまま動作継続**（切り捨てない）。macOS 26+ ユーザーのみガラス体験を得る。
- DesignSystem に glass 層（複数の薄い wrapper）が増える。call site は glass 層を呼ぶことで <26 fallback を得るが、**見た目等価は構造保証ではなく面ごとのスナップショットで確認する**（surface 以外に shadow/stroke/overlay を持つ面があるため）。
- 残存リスク: <26 経路は実機未検証（新 SDK リンクによる旧 OS の寸法ズレ等が観測されない）。許容済み。

## 根拠（棄却した代替）

- **macOS 26 必須化**: 最もシンプルだが Sonoma/Sequoia を切り捨てる。「旧 OS は現状維持で残す」という要望により棄却。
- **`.ultraThinMaterial` 等で全 OS ガラス風**: 本物の Liquid Glass（レンズ・モーフィング・自動追随）ではなく Apple リファレンスと別物。「グラスリキッドに刷新」の要望に反するため棄却。
- **全面ガラス化（コンテンツ層含む）**: 密なモノスペース文字の可読性低下という Apple 公認アンチパターン。棄却。
- 条件採用＋ヘルパー集約を採ったのは、**旧 OS 後方互換を構造的に保証しつつ本物のガラスを 26+ で得る唯一の両立点**だから。
