---
status: active
last-verified: 2026-07-14
---

# Phlox iOS デザインシステム仕様

- **ステータス**: Draft（提案）
- **作成日**: 2026-06-19
- **対象**: iOS コンパニオンアプリ（PRD ファイルへの参照は所在不明・確認できず）
- **関連**: `Packages/DesignSystem`（既存。`platforms` は 2026-06-19 時点で `[.macOS(.v14), .iOS(.v17)]` 済み）, `AgentDomain/SessionStatus.swift`

---

## 0. 結論（先に要点）

**既存のデザインシステムは存在する。パッケージの `platforms` は既に `[.macOS(.v14), .iOS(.v17)]`（2026-06-19 時点）で、共有コアは iOS からもビルド可能**。ただし iOS 固有のコンポーネント層（本書 §4 の Atoms/Molecules/Organisms）は未実装。
トークン・セマンティックカラー・複数テーマ・状態語彙（色＋SF Symbol の二重符号化）まで作り込まれている。

iOS では**ゼロから作らず、既存トークンを唯一の真実源（single source of truth）として共有**し、その上に iOS（HIG・タッチ）固有の薄い層を重ねる。理由はドリフト防止 ── 同じ「色・間隔・状態の意味」を 2 箇所で定義すると必ずズレる（デザインシステム最大の失敗モード）。

---

## 1. 既存資産の棚卸し（再利用するもの）

| 区分 | 既存定義（`Packages/DesignSystem`） | iOS で |
|---|---|---|
| スペーシング | `DSSpacing`（8pt グリッド: 2/4/8/12/16/24/32） | そのまま共有 |
| 角丸 | `DSRadius`（4/8/12） | 共有＋カード用に追加検討 |
| フォント | `DSFont`（caption〜heroTitle, mono） | 共有（`Font` は iOS 互換） |
| シャドウ | `DSShadow`（card/cardHover） | 共有 |
| プリミティブ色 | `RGB` 型＋ `AppTheme`（`phloxLight` を含む複数テーマ） | 共有 |
| セマンティック色 | `DSColor`（background/surface/text/status/accent…） | 共有 |
| 状態語彙 | `StatusBadge`（label/color/iconName、色＋形の二重符号化） | 共有（最重要） |

**移植の障壁だった `platforms` の macOS 限定は 2026-06-19 に解消済み**（`.iOS(.v17)` 追加）。`RGB.color` も `DSFont` も SwiftUI の `Color`/`Font` ベースで iOS 互換。`OSAllocatedUnfairLock`（ThemeStore）も iOS 利用可。残るのは §4 の iOS 固有コンポーネント実装。

---

## 2. アーキテクチャ方針（ドリフトを作らない）

二段階で構成する。

**Phase 1 — トークンを多プラットフォーム化（共有コア）**（**完了・2026-06-19**）
`DesignSystem` の `platforms` に `.iOS(.v17)` を追加し、プラットフォーム非依存部分（`DSSpacing`/`DSRadius`/`DSFont`/`DSShadow`/`RGB`/`AppTheme`/`DSColor`/`StatusBadge`）を iOS からも import できるようにする。macOS 固有のコンポーネント（hover 前提の `*_Hover` 系など）は `#if os(macOS)` で隔離する。

**Phase 2 — iOS 固有レイヤー（`DesignSystemIOS` ターゲット or モジュール）**
タッチ・ナビゲーション・モバイル特有の事情だけを iOS 側に置く。共有コアに依存し、コアを複製しない。

```
DesignSystem (multiplatform core)         ← 唯一の真実源（色・間隔・状態）
   ├── #if os(macOS): hover系・カンバン寸法
   └── #if os(iOS):   なし（コアは純粋トークンのみ）
        ▲
        │ depends
DesignSystemIOS (iOS only)                ← タッチ・HIG・モバイル部品
   └── Button / Card / StatusChip / ApprovalBar / InputBar ...
```

中央化する判断: 色・タイポgrafi・間隔・状態の意味・アクセシビリティ。
ローカルに残す判断: 画面レイアウト・コピー・機能ロジック（PRD の各画面側）。

---

## 3. デザイントークン（iOS）

### 3.1 プリミティブ（参照）
既存 `AppTheme.phlox` の `RGB` をそのまま参照（再定義しない）。主要値の抜粋:

| 役割 | 値 |
|---|---|
| background | `#120F1D` |
| surface | `#16121​F` 系（`surface`/`surfaceElevated`） |
| accent（ブランド紫） | `#A855F7` |
| status running | `#34D399`（緑） |
| status awaiting（承認待ち） | `#FBBF24`（黄） |
| status error | `#EC4899`（ピンク） |
| status completed | `#6EE7B7` |
| attention（あなたの番） | ダーク `#F472B6` / ライト `#DB2777` |

### 3.2 セマンティック（iOS 追加分）
共有 `DSColor` に加え、タッチ UI 固有のセマンティックを iOS 層で定義する。

| トークン | 用途 | 既定値（案） |
|---|---|---|
| `dsBrandGradient` | 主要 CTA（New Task） | 既存 `newSessionGradient`（紫→ピンク）を流用 |
| `dsDestructive` | 削除・却下 | `DSColor.statusError` |
| `dsApprove` | 承認 | `DSColor.statusRunning`（緑） |
| `dsSurfacePressed` | タップ押下面 | `fillSelected` 相当 |

### 3.3 iOS 固有トークン（新規）
タッチ／HIG のために**新設**するトークン。

```swift
public enum DSTouch {
    /// HIG 推奨の最小タップ領域（44x44pt）。
    public static let minTarget: CGFloat = 44
    /// リスト行の最小高さ。
    public static let rowMinHeight: CGFloat = 56
    /// 主要ボタンの高さ。
    public static let primaryButtonHeight: CGFloat = 50
    /// safe-area 内の標準水平インセット。
    public static let screenInset: CGFloat = DSSpacing.l // 16
}

public enum DSMotion {
    public static let quick: Double = 0.18   // タップフィードバック
    public static let standard: Double = 0.28 // 画面遷移補助
}
```

### 3.4 タイポグラフィ（Dynamic Type 必須）
既存 `DSFont` を共有しつつ、**iOS では固定サイズではなく Dynamic Type 準拠**を原則とする。`DSFont` は `Font.body` 等のテキストスタイル由来なので Dynamic Type に追従する（`iconTiny` の生サイズ `9pt` のような固定値はバッジ専用に限定し、本文には使わない）。

---

## 4. コンポーネントカタログ（Atomic Design）

PRD の 4 操作（追加・回答・承認・削除）と状態表示を満たす最小セット。コア 10 に相当する優先順で示す。

### Atoms（原子）
| 部品 | variant / state | アクセシビリティ |
|---|---|---|
| `DSButton` | `primary / secondary / ghost / destructive`、`disabled / loading` | 44pt 確保、`accessibilityLabel`、loading 時は VoiceOver で「実行中」 |
| `DSStatusChip` | 6 状態（starting/idle/running/awaiting/completed/error） | **色＋SF Symbol＋テキスト**の三重符号化（`StatusBadge` 流用） |
| `DSAgentBadge` | claudeCode / codex / cursor / … | エージェント色（`DSColor.agentColor`） |
| `DSTextField` | default / focus / error | ラベル関連付け、エラーは色＋文言 |

### Molecules（分子）
| 部品 | 構成 | 用途 |
|---|---|---|
| `DSSessionRow` | AgentBadge + 名前 + StatusChip + 補助テキスト | 一覧の 1 行（FR-2） |
| `DSInputBar` | TextField + 送信ボタン | 質問回答・指示送信（FR-3/4） |
| `DSApprovalBar` | 承認ボタン + 却下ボタン（破壊的色）＋プロンプト | 承認・却下（FR-5、二段確認） |

### Organisms（有機体）
| 部品 | 構成 | 画面 |
|---|---|---|
| `DSSessionList` | 承認/質問待ちを上部強調 + SessionRow 群 + プルリフレッシュ | 一覧画面 |
| `DSSessionDetailHeader` | 名前 + StatusChip + 削除メニュー | 詳細画面 |
| `DSConnectionForm` | 読み取り専用の接続先 + QR 接続ボタン + 疎通テストボタン | 接続設定画面 |

### Templates / Pages
PRD の 4 画面（接続設定／一覧／詳細／spawn）＝ Pages。テンプレートは `NavigationStack` ベースの標準遷移。

---

## 5. 状態の視覚言語（最重要・既存流用）

`StatusBadge` の対応をそのまま iOS UI の正典とする:

| 状態 | 色 | SF Symbol | 日本語ラベル |
|---|---|---|---|
| starting | statusStarting | `circle.dotted` | 起動中 |
| idle | statusIdle | `pause.circle` | 待機中 |
| running | statusRunning（緑） | `play.circle.fill` | 実行中 |
| **awaitingApproval** | statusAwaiting（黄） | `exclamationmark.bubble.fill` | **承認待ち** |
| completed(0) | statusCompleted | `checkmark.circle.fill` | 完了 |
| error | statusError | `exclamationmark.triangle.fill` | エラー |

「承認待ち／質問待ち＝あなたの番」は `attention` 色のアクセントで一覧上部に持ち上げる（macOS の `idleHighlight` 思想を踏襲）。

---

## 6. アクセシビリティ（最初から組み込む）

- **タップ領域 44x44pt 以上**（`DSTouch.minTarget`）。
- **色のみに依存しない**: 状態は必ず色＋アイコン＋テキスト。
- **Dynamic Type 対応**: テキストスタイル由来フォントを使い、固定 pt を本文に使わない。レイアウトは折り返し許容。
- **VoiceOver**: 各行は「<エージェント名>、<状態>」を 1 ラベルに合成。破壊的操作は明示。
- **Reduce Motion**: `DSMotion` を使う箇所はトランジションを縮退できるようにする。
- **コントラスト**: ライト／ダーク双方で、`textSecondary/textTertiary` の小サイズ利用時は WCAG AA を別途検証（Open Q）。

---

## 7. 運用・ガバナンス（ハイブリッド）

- **共有コア（色・間隔・状態）は中央管理＝強制**。iOS 側で hex 直書き・固定間隔を禁止し、トークン経由のみ許可。
- **iOS 固有コンポーネントは採用ベース**で増やす（必要になった部品だけ作る＝「製品なしのデザインシステム」を避ける）。
- **テーマ**: iOS は外観設定としてシステム／ライト／ダークを切り替えられる。ライト用に `AppTheme.phloxLight`（id: `phlox-light`）を追加し、`DSColor+IOS.swift` の `camp*` トークンは `ThemeStore.active.preferredColorScheme` に連動する。変更は `AppRoot` で即時反映する。
- **ドリフト検出**: iOS コードに対し「`Color(red:` 直書き」「`.font(.system(size:`」を CI/grep で検出する軽い lint を置く。

---

## 8. 受け入れ条件（このデザインシステムの DoD）

- `DesignSystem` が iOS でビルドでき、`DSSpacing`/`DSColor`/`StatusBadge` を iOS から import できる（**達成済み・2026-06-19**）。
- Atoms（Button/StatusChip/TextField）＋ Molecules（SessionRow/InputBar/ApprovalBar）が実装され、44pt・Dynamic Type・VoiceOver を満たす。
- 6 状態すべてが色＋アイコン＋テキストで表示される。
- iOS コードに色・間隔の生値直書きが無い（lint green）。
- `swift test`（共有コアの iOS ビルド確認を含む）が green。

---

## 9. 未決事項（Open Questions）

- **Q1**: 共有コアを「既存 `DesignSystem` の多プラットフォーム化」で行うか、「`DesignSystemCore` を切り出して macOS/iOS が依存」する形にリファクタするか（後者は安全だが移行コスト）。
- **Q2**: iOS アプリは既存 SwiftPM を参照する Xcode プロジェクトにするか、別リポジトリにするか（参照可否に影響）。
- **Q3**: ライト／ダーク双方で小サイズ二次テキストが WCAG AA を満たすか、要コントラスト検証。
- **Q4（解決済み）**: iOS でもシステム／ライト／ダークの外観切替を提供する。ライブ反映方式の判断は [iOS ADR 0004](../../../ios/docs/adr/0004-ios-appearance-live-switch-via-root-remount.md) に記録する。

---

## 10. 次アクション

1. **Q1/Q2 を確定**（多プラットフォーム化 vs コア切り出し、プロジェクト構成）。
2. `DesignSystem` に `.iOS(.v17)` を追加し、macOS 固有部を `#if os(macOS)` で隔離（小さな PR で検証）。
3. `DesignSystemIOS` に Atoms 3＋Molecules 3 を実装し、Xcode Preview で 6 状態を目視確認。
