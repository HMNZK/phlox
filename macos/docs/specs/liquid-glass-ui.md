---
status: active
last-verified: 2026-07-08
---

# 実装プラン: Liquid Glass UI 刷新

- **ステータス**: Plan（設計確定・実装未着手・Codex 再レビュー反映 rev.3）
- **作成日**: 2026-06-28（rev.2: Codex 初回レビュー反映 / rev.3: 再レビューの実装不能2点（glassIdentity の Sendable 制約・AdaptiveGlass への fallbackFill 伝播）を解消）
- **決定の出所**: ADR 0019（採用方針・OS 戦略・適用境界・棄却代替）
- **レビュー記録**: `docs/agent-output/codex-liquid-glass-plan-review.md`（初回）, `docs/agent-output/codex-liquid-glass-plan-review-rev2.md`（再レビュー）
- **正典**: 実装完了後は `docs/architecture/design-system.md`（as-built）へ反映し、本プランは履歴化する

---

## 0. 結論（先に要点）

macOS 26+ では本物の Liquid Glass を**機能層クロームに限定**して適用し、macOS 14/15 では**既存の見た目を再現**する。可用性分岐（`#available(macOS 26)`）は DesignSystem の **glass 層（複数の薄い wrapper）** だけに閉じ込め、call site と他パッケージへ漏らさない。`<26 の見た目等価は「構造保証」ではなく before/after スナップショットで検証する`。テーマは「下地を染め、ガラスは暗い `.regular`＋低不透明度 tint で透かす」方式。アクセシビリティ（Reduce Transparency / Increased Contrast）は自動適応任せにせず glass 層で明示処理する。

---

## 1. 用語（このプランの ubiquitous language）

**機能層 / functional（chrome）layer**: ツールバー・サイドバー・インスペクター・ヘッダ・フローティング操作・メニュー等。ガラス化対象。
**コンテンツ層 / content layer**: ターミナル/ログ本文・本文テキスト・カンバン列の本文・**ターミナルを内包するタイル/シェル**。不透明維持。
**ガラスクローム**: 機能層のうち実際に `glassEffect` を当てる面。
**下地レイヤー / backdrop**: ガラスが透かしてサンプリングする背後。Phlox ではテーマ単色のペイン背景（`DSColor.background`）。edge-to-edge でターミナルを潜らせない。
**glassTint**: テーマごとに 1 つ持つ低不透明度・低彩度 harmonizing tint トークン。装飾 tint と区別。
**glass 層**: `#available` を閉じ込めた DesignSystem の薄い wrapper 群（`glassContainer` / `glassIdentity` / `glassSurface` family）。call site はこれだけを呼ぶ。
**意味的 overlay**: アクセントバー・ドロップ先ハイライト・選択 border・解決 pill など。ガラス/不透明の**両系統で維持**し、glass 層の外（呼び出し側）に置く。

---

## 2. 適用境界（component 単位の inventory）

扱い区分: **glass**（glassEffect 適用）/ **opaque**（不透明・現状維持）/ **standard-auto**（macOS 26 SDK の標準コントロール自動採用に委ねる）/ **no-change**。

> パスは特記なき限り `Packages/DashboardFeature/Sources/DashboardFeature/` 配下（`MissionControlView` / `LoopflowDashboardView` は `Loopflow/`、`DashboardView` / `UsageTopBarView` は `Dashboard/`、`SessionView` / `SessionGridView` は `Session/`）。DS 部品は `Packages/DesignSystem/Sources/DesignSystem/`、`SettingsView` は `App/`。
>
> **2026-07-08 注記**: `LoopflowBoardColumnView` / `LoopflowKanbanCard` / `MissionControlView` / `LoopflowDashboardView` / `LoopflowEventDetailPanel` は Loopflow サブシステムの一部として **ADR 0020 で削除済み・対象消滅**（下表の該当行は歴史的記録）。本プラン自体は未実装のまま（`docs/architecture/design-system.md` に as-built 反映なし）で ADR 0019 は active を維持しているため、実装着手時は Loopflow 関連行を除外した対象で再設計すること。

| component | file:line | 扱い | <26 fallback fill | 装飾の維持方針 |
|---|---|---|---|---|
| サイドバーペイン | `DashboardView.swift:168` | glass（sidebar material） | `DSColor.background` | 区切り線据え置き |
| 詳細ペイン背景 | `DashboardView.swift:178` | **opaque（下地）** ガラスが透かす themed backdrop | `DSColor.background` | — |
| インスペクターペイン | `DashboardView.swift:186` | glass | `DSColor.background` | 区切り線据え置き |
| トップ操作系オーバーレイ | `DashboardView.swift:203-235` | standard-auto（必要なら floating glass） | — | 既に最前面 overlay |
| 使用量チップ | `Dashboard/UsageTopBarView.swift:46-79` | **no-change（既定）**: 現状 bg 無し。ターミナル上で読みづらい場合のみ glass capsule を新規付与 | （新規時のみ） | `.help` 維持 |
| セッションヘッダ/ツールバー | `SessionView.swift` | glass（枠のみ） | `surface` | 中身ターミナルは opaque |
| グリッドタイル | `SessionGridView.swift:113-145` | **opaque**（TerminalView/Chat を内包） | `tileBackground`（動的） | 動的 border/shadow 維持。ガラス化しない |
| カンバン列 | `LoopflowBoardColumnView.swift:38` | **opaque**（現状維持） | `DSColor.surface` | — |
| カンバンカード | `LoopflowKanbanCard.swift:139-162` | glass（`glassCardChrome`） | `surfaceElevated` | shadow/stroke は **<26 のみ**、accent bar/pill は両系統で維持 |
| エージェントバッジ | `DesignSystem/AgentKindBadge.swift:23-24` | **no-change（既定）**: 据え置き。glass capsule 化は実機で映えれば採用 | `surfaceElevated` | 色付き stroke 維持 |
| MissionControl header/live bar | `Loopflow/MissionControlView.swift:87,188` | glass（暫定・実装時に再確認） | 実装時確認 | — |
| Loopflow launcher 入力 | `LoopflowDashboardView.swift:148-162` | standard-auto/glass（暫定） | 実装時確認 | — |
| Event detail terminal shell | `LoopflowEventDetailPanel.swift:189-195` | **opaque**（ターミナル内包・暫定） | 実装時確認 | — |
| 標準コントロール | `ChatSessionView.swift:30-34`（segmented picker）, `LoopflowEventDetailPanel.swift:201-210`（borderedProminent）, `App/SettingsView.swift:67,114`（Picker/Toggle）, `Loopflow/LoopflowDashboardView.swift:260`（menu picker） | **standard-auto** | — | カスタム置換しない |

> **要判断**（使用量チップ・バッジに glass を新規付与するか）は実機で「ターミナル/下地の上で読めるか」を見て決める。デフォルトは「付与しない（no-change）」。

---

## 3. テーマ×ガラス

- 下地（ペイン背景・ターミナル・不透明列/タイル）は**テーマ単色のまま**。
- ガラスクロームは暗い `.regular` ＋ `DSColor.glassTint`（低不透明度・低彩度）を**一様適用**。
- テーマ accent は prominent ボタン・選択・ステータスの `tint` だけに**節約使用**。
- 濃さは数値でなく**実機の見た目**で決める（濃すぎるとガラス感が消える）。

---

## 4. 実装構造（glass 層に `#available` を閉じ込める）

`#available(macOS 26)` は **DesignSystem の glass 層だけ**に置く。call site と他パッケージには一切書かない。

```swift
// DesignSystem/Glass.swift（新規・唯一の #available 箇所）

// (1) コンテナ: 列単位でカードをまとめる（glass は他の glass をサンプリングできないため必須）
@ViewBuilder
public func glassContainer<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
    if #available(macOS 26.0, *) { GlassEffectContainer(spacing: spacing) { content() } }
    else { content() }                                   // <26: 素通し
}

// (2) morph 用 ID（SDK の glassEffectID は Hashable & Sendable を要求するため制約を合わせる）
public extension View {
    @ViewBuilder
    func glassIdentity<ID: Hashable & Sendable>(_ id: ID, in ns: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) { glassEffectID(id, in: ns) } else { self }
    }
}

// 立体・stroke の方針を 1 値に束ねる（hover で shadow/stroke が変わる面に対応）
public struct GlassElevation {
    var restShadow: DSShadow?     // 例: .card
    var hoverShadow: DSShadow?    // 例: .cardHover
    var stroke: Color?            // 例: 通常 border / hover で fillSelected
    var isHovering: Bool = false
    public static let none = GlassElevation()
}

// (3) サーフェス: fill＋立体(shadow)＋frosting を availability で吸収。
//     fallbackFill / elevation は 26+ 側にも渡す（Reduce Transparency の不透明 fallback と
//     Increased Contrast の stroke 強化に必要）。意味的 overlay(accent bar/pill) は呼び出し側に残す。
public extension View {
    @ViewBuilder
    func glassSurface(
        fallbackFill: Color = DSColor.surface,
        in shape: some Shape = .rect(cornerRadius: DSRadius.m),
        elevation: GlassElevation = .none
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(AdaptiveGlass(shape: AnyShape(shape), fallbackFill: fallbackFill, elevation: elevation))
        } else {
            modifier(LegacyGlassFallback(fill: fallbackFill, shape: AnyShape(shape), elevation: elevation))
        }
    }
}

// 26+: 環境を見てガラス or 不透明 fallback を選ぶ（fallbackFill を受け取るのがポイント）
@available(macOS 26.0, *)
struct AdaptiveGlass: ViewModifier {
    let shape: AnyShape; let fallbackFill: Color; let elevation: GlassElevation
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.modifier(LegacyGlassFallback(fill: fallbackFill, shape: shape, elevation: elevation))
        } else {
            content
                .glassEffect(.regular.tint(DSColor.glassTint), in: shape)
                .modifier(ContrastStroke(shape: shape, increased: contrast == .increased, base: elevation.stroke))
        }
    }
}

// <26 と「26+ かつ Reduce Transparency」が共有する不透明再現（fill＋rest/hover shadow＋stroke）
struct LegacyGlassFallback: ViewModifier {
    let fill: Color; let shape: AnyShape; let elevation: GlassElevation
    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .dsShadow(elevation.isHovering ? (elevation.hoverShadow ?? elevation.restShadow) : elevation.restShadow)
            .overlay { if let s = elevation.stroke { shape.stroke(s, lineWidth: 1) } }
    }
}
```

- カンバンカードは `glassCardChrome`（上記 (3) ＋ accent bar/pill overlay を両系統で付与）。列単位で `glassContainer(spacing:)` に包み、各カードへ `glassIdentity` を付与（折畳⇄展開 morph）。
- `glassTint` は `AppTheme` の各テーマに 1 トークン追加（`Tokens.swift` / `AppTheme.swift`）。
- **<26 等価は構造保証しない**。各面で before/after の `ImageRenderer` スナップショット（または view test）を取り、既存と一致することを確認する。

---

## 5. AppKit / SwiftTerm との合成（HIGH リスク）

- ターミナルは layer-backed の `NSViewRepresentable`（`TerminalView.swift:6` / `TerminalCoordinator.swift:100-138`）。**前面を覆うため、既に操作系は overlay 前面化で回避している**（`DashboardView.swift:201-202, 236-239`）。
- ルール: **glass surface は `TerminalView` の bounds と重ねない**。上部 chrome は予約 gutter に置く。
- やむを得ず重なる箇所は、macOS 26 実機で **ターミナル出力中・リサイズ中・グリッド切替中**の描画（z-order / hit-testing / stale layer）を確認するまで done としない。

---

## 6. アクセシビリティ（自動適応任せにしない）

glass 層が環境を見て明示処理する（現コードは Reduce Motion しか見ていない）:
- `@Environment(\.accessibilityReduceTransparency)` が true → ガラスを `.identity`＋不透明 fallback fill に切替。
- `@Environment(\.colorSchemeContrast) == .increased` → border/scrim を強化。
- カードの morph は既存の `accessibilityReduceMotion`（`LoopflowKanbanCard.swift:21` 他）を流用し抑制。
- テーマ別 `glassTint` は実機でコントラスト/可読性の合格基準を満たすまで採用しない。

---

## 7. 標準コントロールと Info.plist

- 26 SDK ビルドで標準コントロール（segmented picker・borderedProminent 等）は自動採用される。**カスタム置換せず OS 標準に委ねる**対象として一覧化（§2 末尾）。
- **Info.plist の opt-out は設定しない**（26+ でガラスを得るのが目的）。理由を ADR 0019 に明記済み。
- 26+ で標準部品とカスタム glass が混在するため、寸法・統一感は実機 matrix（§8）で確認。

---

## 8. 検証ゲート

既存 E2E（PTY/ControlServer ロジック寄り）は glass/AppKit/a11y/visual regression を**検出できない**。以下を gate 化する:
- **各面**: `swift test`（対象パッケージ）→ 実 Debug 起動で目視（ガラスに見えるか / 文字が読めるか / CPU 収束）。
- **macOS 26 実機 matrix**: 全6テーマ × {通常 / Reduce Transparency / Increased Contrast} × {サイドバー・グリッド・Loopflow・Mission Control} × {ターミナル出力中・リサイズ中}。
- **<26 等価**: before/after スナップショット（`ImageRenderer`）で既存一致を確認。実機 14/15 は VM 入手時に 1 回回帰（現状は未検証と明記）。
- 全面後にヘッドレス E2E（`PHLOX_E2E=1 ... --filter E2E --no-parallel`）を 1 回。

---

## 9. ロールアウト順序（各面で §8 ゲートを通す）

1. **glass 層の新設**（`glassContainer` / `glassIdentity` / `glassSurface` family ＋ `glassTint` トークン）。call site 変更なしでビルド通過を確認。
2. **サイドバー**（パイロット）→ §8 ゲート。
3. インスペクター → 4. セッションヘッダ/ツールバー。
4. **カンバンカード**（`glassContainer`＋`glassCardChrome`＋morph。展開×テーマ最明色の可読性を重点確認）。
5. 暫定対象（MissionControl・launcher・チップ/バッジの要判断）を実機で確認しつつ確定。

---

## 10. スコープ OUT（今回やらない）

アプリアイコン刷新 / ライトモード対応 / ネイティブ window-toolbar 移行 / コンテンツ層・本文・カンバン列・グリッドタイル・ターミナル内包シェルのガラス化。

---

## 11. 未解決・残存リスク

- **<26 経路は実機未検証**（VM 不在）。スナップショット等価確認＋コンパイル通過まで。新 SDK リンクによる旧 OS 寸法ズレは観測できない。
- glass × AppKit 合成の最終可否は macOS 26 実機検証（§5）に依存。
- 使用量チップ・バッジへの glass 新規付与は実機判断（デフォルト no-change）。
- MissionControl / launcher / Event detail の扱いは実装着手時にコードを確認して確定（暫定値）。
- `glassTint` の各テーマ具体値は実機で詰める（未確定）。
