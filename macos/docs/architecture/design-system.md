---
status: active
last-verified: 2026-07-08
---

# Phlox デザインシステム（macOS 本体）

> 2026-07-07: カラースキーマをモノクロ基調＋Claude コーラルへ刷新、ライトテーマ3種追加、hairline のテーマ追随化、`AgentSessionIcon`・diff トークン新設（ADR 0042）。CLI は claude/codex/cursor の3種に限定（ADR 0041）。

- **ステータス**: Reference（実装に対応する正典）
- **作成日**: 2026-06-19
- **対象**: macOS アプリ本体の UI 基盤（`Packages/DesignSystem`）
- **真実源（single source of truth）**: `Packages/DesignSystem/Sources/DesignSystem`。本書はその解説であり、値・挙動はコードが優先する（齟齬があればコードが正）。
- **関連**: `docs/specs/design-system-ios.md`（iOS コンパニオン向けの拡張計画）, `Packages/AgentDomain/Sources/AgentDomain/SessionStatus.swift`（状態語彙の出所）

---

## 0. 結論（先に要点）

Phlox には独立した SwiftUI パッケージ `DesignSystem` が存在し、**トークン層・テーマ層・コンポーネント層**の3層で構成される。

- **トークン**: スペーシング（8pt グリッド）・角丸・フォント・レイアウト寸法・シャドウ・セマンティックカラーを一元定義（`Tokens.swift`）。
- **テーマ**: UI chrome とターミナルを統合したテーマ群（ダーク6＋ライト3＝9テーマ）。既定は `Phlox`。**UI 基調はモノクロ（グレー階調）、アクセントは全テーマ共通で Claude コーラル `#D97757`**（ADR 0042）。起動時に確定し、切替は再起動で反映（`AppTheme.swift`）。明度は `AppTheme.preferredColorScheme`（background 相対輝度 ≥0.5 で `.light`）で単一導出し、ルート/設定/Usage が追随する。
- **コンポーネント**: 状態・エージェント・ホバー操作の共有部品。クロスプラットフォーム部品と macOS 固有部品を `#if os(macOS)` で隔離。

設計の中核思想は **「生値の直書きを排除し、色・間隔・状態の意味を1箇所でだけ定義する」**。同じ意味を2箇所で定義するとドリフト（ズレ）が必ず生じる、というデザインシステム最大の失敗モードを避けるための規律。

`Package.swift` は既に `platforms: [.macOS(.v14), .iOS(.v17)]` を宣言済みで、純トークン部はクロスプラットフォーム。AppKit 依存部（hover・カーソル・実行中スピナー）だけが macOS に隔離されている。

---

## 1. パッケージ構成

```
Packages/DesignSystem/
├── Package.swift                 platforms: [.macOS(.v14), .iOS(.v17)] / depends: AgentDomain
└── Sources/DesignSystem/
    ├── Tokens.swift              DSSpacing / DSRadius / DSFont / DSLayout / DSShadow / DSColor
    ├── AppTheme.swift            RGB / AppTheme（6テーマ）/ ThemeStore
    ├── StatusBadge.swift         状態の語彙（ラベル・色・SF Symbol・ヘルプ）※純ロジック
    ├── StatusLabel.swift         状態をテキスト1行で表示          [cross-platform]
    ├── StatusCapsuleBadge.swift  状態をカプセル（ドット+アイコン+文字）で表示 [cross-platform]
    ├── CapsuleBadge.swift        汎用カプセルバッジ                [cross-platform]
    ├── AgentKindBadge.swift      エージェント名バッジ（CLI 識別色） [cross-platform]
    ├── AgentBrandIcon.swift      builtin CLI のブランドアイコン（SVG/SF Symbol フォールバック、ADR 0032） [cross-platform]
    ├── AgentSessionIcon.swift    セッション行/ヘッダー用アイコン（AgentBrandIcon 非丸囲み、ADR 0042） [cross-platform]
    ├── RunningCountBadge.swift   「N running」集計バッジ           [cross-platform]
    ├── AppIconStore.swift        選択中アプリアイコンの id↔アセット名解決・永続化 [cross-platform]
    ├── Icons.xcassets            builtin CLI ブランドアイコンの SVG アセット（preserves-vector） [asset catalog]
    ├── StatusDot.swift           状態ドット / 実行中スピナー        [#if os(macOS)]
    └── Interaction.swift         ホバー・カーソル・ButtonStyle 群   [#if os(macOS)]
```

依存は `AgentDomain` のみ（`AgentKind` / `AgentDescriptor` / `AgentRegistry` / `SessionStatus`）。

---

## 2. デザイントークン（`Tokens.swift`）

### 2.1 スペーシング `DSSpacing`（8pt グリッド）

| トークン | 値 (pt) |
|---|---|
| `xxs` | 2 |
| `xs` | 4 |
| `s` | 8 |
| `m` | 12 |
| `l` | 16 |
| `xl` | 24 |
| `xxl` | 32 |

### 2.2 角丸 `DSRadius`

| トークン | 値 (pt) |
|---|---|
| `s` | 4 |
| `m` | 8 |
| `l` | 12 |

### 2.3 フォント `DSFont`

テキストスタイル由来を基本とし、本文は Dynamic Type に追従する。固定 pt は `iconTiny` のバッジ用途のみに限定。

| トークン | 定義 | 用途 |
|---|---|---|
| `caption` | `Font.caption` | 補助テキスト・バッジ |
| `captionStrong` | `caption.weight(.medium)` | 強調補助 |
| `body` | `Font.body` | 本文 |
| `sectionHeader` | `subheadline.semibold` | セクション見出し |
| `title` | `title3.semibold` | タイトル |
| `heroTitle` | `title2.semibold` | 大見出し |
| `mono` | `system(.body, .monospaced)` | コード・ID |
| `monoCaption` | `system(.caption, .monospaced)` | コード補助 |
| `iconTiny` | `system(size: 9, weight: .bold)` | バッジ等の極小アイコン（**本文に使わない**） |

**アイコングリフ寸法 `DSIconSize`**（SF Symbol 等の固有サイズ。本文フォントとは別系統で、weight は利用箇所で指定する）

| トークン | 値 (pt) | 用途 |
|---|---|---|
| `s` | 10 | 小アイコン・chevron |
| `m` | 12 | 中アイコン |
| `l` | 15 | 大アイコン |

頻出する実寸（10/12/15）のみを一元化する。一回限りの特大アイコン（32/40/48/64pt 等）はトークン化せず許容例外とする（§7）。

### 2.4 レイアウト寸法 `DSLayout`

8pt グリッドに乗らない固有寸法をマジックナンバー直書きから引き上げて一元管理する。

| トークン | 値 | 用途 |
|---|---|---|
| `progressBarHeight` | 5 | 進捗バー高（Compact と本体の値ドリフトを統一） |

### 2.5 シャドウ `DSShadow`

elevation（面の持ち上げ）を表す。生値の `.shadow(...)` 直書きを排除し、`View.dsShadow(_:)` 経由でのみ適用する。

| トークン | color / radius / x / y | 用途 |
|---|---|---|
| `card` | black 0.28 / 8 / 0 / 3 | カードの控えめな elevation |
| `cardHover` | black 0.40 / 12 / 0 / 6 | hover 時の持ち上げ |
| `gridTile` | black 0.40 / 10 / 0 / 4 | グリッドタイルの elevation（card の設計基準値） |

```swift
SomeCard().dsShadow(.card)   // 生 .shadow を書かない単一経路
```

### 2.6 セマンティックカラー `DSColor`

実体は `ThemeStore.active`（起動時に確定するテーマ）から引く。**テーマ依存**の色と**テーマ非依存（固定値）**の色が混在する点に注意。

**テーマ依存（テーマで色が変わる）**

| トークン | 意味 |
|---|---|
| `background` / `surface` / `surfaceElevated` | 背景ランプ（最暗→面→持ち上げ面） |
| `textPrimary` / `textSecondary` / `textTertiary` | テキスト3階層 |
| `accent` | アクセント（ブランド） |
| `statusStarting` / `statusIdle` / `statusRunning` / `statusAwaitingApproval` / `statusCompleted` / `statusError` | 状態色（§4） |
| `idleHighlight` 系（`attention` の不透明度違い4種） | 「あなたの番」（未確認完了）の強調面・枠・バー |
| `sessionRowSelected` / `sessionRowSelectedBorder` | セッション行の選択 |

**テーマ非依存（固定値）**

| トークン | 値 | 用途 |
|---|---|---|
| `newSessionGradient` | 紫 `#A855F7` → ピンク `#EC4899` | 設定/Usage の一部で使用（New session ボタンは撤去済。脱コーラル基調で浮くため将来再検討・ADR 0042） |

> **ADR 0042 で刷新（テーマ追随化）**: 旧「テーマ非依存の白 opacity 固定」だった `border` / `separator` / `fillSubtle` / `fillSelected` / `sessionRowHover(Border)` は、**`theme.textPrimary` 由来の opacity**（前景色基準＝常に背景と対比）へ変更され、ライトテーマでも不可視化しない。選択トークンは `sessionRowSelectedBorder`=`Color.clear`（枠強調撤去）・`sessionRowSelected`=`fillSelected`（薄グレー）・`userBubble`=前景 8% のグレー面。diff 用に `diffAdded`（青）/`diffRemoved`（赤）を新設（明度追随）。`codeSyntax*` はライト/ダークの明度分岐。旧 `AppTheme.rowSelected/rowSelectedBorder` は dead 化のため除去。

**エージェント識別（関数 API・ブランドアイコン）**

| API | 役割 |
|---|---|
| `agentColor(for: AgentKind)` / `agentColor(for: AgentDescriptor)` | CLI エージェントの識別色 |
| `AgentBrandIcon(descriptor:size:)` | エージェントのブランドアイコン。builtin claude/codex/cursor は `Icons.xcassets` の SVG（preserves-vector）を描画、他は SF Symbol／頭文字フォールバック（ADR 0032） |
| `AgentSessionIcon(descriptor:status:size:)` | セッション行/ヘッダー用。`AgentBrandIcon` を**丸で囲わず**描画する（StatusDot＋エージェント名バッジの置換、ADR 0042）。**running インジケータ overlay は ADR 0044 で撤去**（`showsRunningIndicator` は常に false）。 |

> **ワークスペース（プロジェクト）識別色は 2026-07-05 に廃止**（`projectColorPalette` / `projectColor(at:)` / `AppTheme.projectPalette` は削除。並び順ベースの自動割当てだったため永続データなし・移行不要）。プロジェクト表示はニュートラルトークン（`textSecondary`）に統一。
>
> **swift test では `Icons.xcassets` は actool コンパイルされない**（ブランド画像は空白描画になる）。ブランド実描画の検証は xcodebuild 経路のみ有効——テストにブランド画像のピクセルアサーションを書かないこと（ADR 0032）。

> グラデの注意（コード内コメント由来）: `newSessionGradient` をテーマ由来にすると、両端が同色になるテーマ（例: Tokyo Night は accent と ansi[5] がともに `#BB9AF7`）でフラット化するため、**意図的にブランド色で固定**している。

---

## 3. テーマシステム（`AppTheme.swift`）

### 3.1 プリミティブ `RGB`

0–255 の RGB 値。SwiftUI `Color` とターミナル用生値の双方へ変換でき、`lightened(_:)`（面のレイヤー段差づくり）・`mixed(_:_:)`（背景への沈め込み）の導出計算を持つ。色は `RGB` で定義し、`Color` は描画時に導出する。

### 3.2 `AppTheme`

UI chrome（背景ランプ・テキスト・アクセント・状態色・識別色）とターミナル（bg/fg/ANSI16）を**1つの構造体に統合**したカラースキーマ。`fromPalette(...)` ファクトリで「標準ターミナルパレット（bg/fg/ANSI16）から UI トークンを導出」でき、人気テーマを少ない記述で取り込める。

### 3.3 同梱テーマ（`ThemeStore.all`、先頭が既定）

UI accent は**全テーマ共通で Claude コーラル `#D97757`**（`AppTheme.fromPalette` は入力 accent を無視し共有色に統一。`phlox` も手書きで coral）。background/surface/text は各テーマの明度に応じたグレー階調（`fromPalette` は `bg.grayscale`/`fg.grayscale` から導出）。

| id | 名前 | 明度 |
|---|---|---|
| `phlox` | **Phlox（既定）** | dark |
| `tokyo-night` | Tokyo Night | dark |
| `dracula` | Dracula | dark |
| `catppuccin-mocha` | Catppuccin Mocha | dark |
| `gruvbox-dark` | Gruvbox Dark | dark |
| `nord` | Nord | dark |
| `catppuccin-latte` | Catppuccin Latte | **light** |
| `solarized-light` | Solarized Light | **light** |
| `github-light` | GitHub Light | **light** |

**既定 Phlox の主要値**（抜粋）:

| 役割 | 値 |
|---|---|
| background / surface / surfaceElevated | `#111111` / `#181818` / `#202020`（モノクロ・グレー階調） |
| textPrimary / Secondary / Tertiary | `#E6E6E6` / `#969696` / `#6C6C6C` |
| accent（Claude コーラル） | `#D97757` |
| statusRunning（緑） | `#34D399` |
| statusAwaiting（黄・承認待ち） | `#FBBF24` |
| statusError（赤） | `#EF4444` |
| statusCompleted | `#6EE7B7` |
| attention（あなたの番） | `#D97757`（coral） |

### 3.4 `ThemeStore`（起動時確定 + キャッシュ）

- 選択値は `UserDefaults` キー `phlox.theme` に保持。未知 id・未設定はいずれも既定 `phlox` へフォールバック。
- **変更は再起動で反映**（`DSColor` とターミナルが起動時にこの値を読む）。
- 解決結果（テーマ実体 + Color 変換済みパレット）は選択 id が変わらない限りキャッシュし、描画ホットパスでのテーマ線形探索と Color 配列構築を回避する（`OSAllocatedUnfairLock` で保護）。

---

## 4. 状態の視覚言語（最重要・`StatusBadge`）

`SessionStatus`（`AgentDomain`）の各状態を **ラベル・色・SF Symbol・ヘルプ** に対応づける純ロジックの名前空間。**色だけに頼らず、冗長な形（アイコン）とテキストで二重／三重に符号化**する（色覚多様性ケア）。`StatusLabel` / `StatusDot` / `StatusCapsuleBadge` はすべてここから引く。

| 状態 | 色トークン | SF Symbol | 日本語 / 英語 |
|---|---|---|---|
| `starting` | `statusStarting` | `circle.dotted` | 起動中 / starting |
| `idle` | `statusIdle` | `pause.circle` | 待機中 / idle |
| `running` | `statusRunning`（緑） | `play.circle.fill` ※`StatusDot` では回転スピナー | 実行中 / running |
| `awaitingApproval` | `statusAwaitingApproval`（黄） | `exclamationmark.bubble.fill` | 承認待ち / awaiting |
| `completed(exitCode == 0)` | `statusCompleted` | `checkmark.circle.fill` | 完了 (0) / done |
| `completed(exitCode != 0)` | `statusCompleted` | `xmark.octagon.fill` | 完了 (n) / exited |
| `error(message)` | `statusError` | `exclamationmark.triangle.fill` | エラー / error（`message` を `.help` に出す） |

- ラベルは `localizedLabel(for:locale:)` がロケール（ja か否か）で日本語／英語を出し分ける。
- `helpText(for:)` は `error` のときだけ `message` を返す（他は空）。
- 「承認待ち／質問待ち＝あなたの番」は `attention` 由来の `idleHighlight` 系で一覧上部に持ち上げる思想（サイドバー行・グリッドカードで面・枠・左バーを出す）。

---

## 5. コンポーネントカタログ

### 5.1 クロスプラットフォーム（コア）

| 部品 | 表現 | 主な用途 |
|---|---|---|
| `StatusLabel` | 状態色のテキスト1行（`caption`） | 省スペースな状態表示 |
| `StatusCapsuleBadge` | カプセル: ドット + アイコン + 文字 | 状態の標準バッジ（色＋形＋文字の三重符号化） |
| `CapsuleBadge` | 汎用カプセル（label / iconName / tint） | `StatusCapsuleBadge` の下地・任意バッジ |
| `AgentKindBadge` | エージェント名カプセル（識別色枠） | CLI 種別の表示（`AgentDescriptor.displayName`） |
| `RunningCountBadge` | 緑ドット + 「N running」（nested 併記可） | 実行中セッション数の集計表示。**ADR 0044 で本番描画から撤去**（型定義は残置・未使用） |

### 5.2 macOS 固有（`#if os(macOS)`）

AppKit／ポインティングデバイス前提のため macOS に隔離。iOS（タッチ）には hover・カーソルの概念がないため、iOS 向けは将来 `DesignSystemIOS` で別途定義する方針（`docs/specs/design-system-ios.md`）。

| 部品 | 内容 |
|---|---|
| `StatusDot` | 状態ドット（8×8、12×12 枠）。実行中は `RunningSpinner` に切替 |
| `RunningSpinner` | **Core Animation 駆動**の `NSViewRepresentable`。SwiftUI の repeat-forever アニメがメインスレッドを占有し埋め込みターミナル描画を飢餓させる回帰を避けるため、`CAShapeLayer` + `CABasicAnimation` で回転を描画サーバー側に逃がす |
| カーソル修飾子 | `pointingHandCursor()` / `dsColumnResizeCursor()` / `dsInteractiveCursor(isEnabled:)`。macOS 15+ は `.pointerStyle`、14 は `NSCursor` push/pop フォールバック |
| `hoverableControlSurface(...)` | Picker など ButtonStyle を当てられないクリック面に共通ホバー面＋指差しを付与 |
| `HoverableIconButtonStyle` | アイコンボタン: ホバー／押下で角丸ハイライト面 |
| `HoverableSoftButtonStyle` | ソフト塗りテキストボタン: 常時淡い面、ホバー／押下で明るく |
| `HoverableSurfaceButtonStyle` | 行／ヘッダ／選択肢用: 既定は面なし、ホバー／押下で面・枠を強める（押下時 `scaleEffect` 0.995） |
| `HoverCursorState` | `NSCursor` の push/pop 対応ずれ（祖先のカーソルを誤って pop する）を防ぐ純粋ロジック。disabled へのホバーでは push しない |

> 設計メモ: `RunningSpinner` と hover 系を macOS 専用にしているのは「移植しないため」ではなく、**AppKit 依存で iOS に存在しない**ため。状態の「語彙」（`StatusBadge`）と、純 SwiftUI の視覚表現（`StatusCapsuleBadge` / `StatusLabel`）はコアで共有されている。

---

## 6. アクセシビリティ

- **色のみに依存しない**: 状態は必ず色＋アイコン（＋多くはテキスト）で表す（`StatusBadge`／`CapsuleBadge`）。
- **VoiceOver**: `StatusDot`・各バッジは `accessibilityLabel` にローカライズ済み状態名を設定。`CapsuleBadge` は `accessibilityElement(children: .combine)` で1ラベルに合成。`RunningCountBadge` は nested を含む読み上げ文を別途用意。
- **ヘルプ（ツールチップ）**: `error` の詳細メッセージは `.help(...)` で提示。
- **Dynamic Type**: 本文はテキストスタイル由来フォントで追従。固定 pt（`iconTiny` の 9pt 等）はバッジの装飾アイコンに限定。

---

## 7. 利用規律・ガバナンス

中核は **「生値を直書きせず、トークン経由でのみ色・間隔・影・寸法を使う」**。

- **色**: `Color(red:green:blue:)` 等の直書きを禁止し、`DSColor` 経由のみ。新しい意味の色が要るなら `DSColor`／`AppTheme` に足す。
- **間隔・角丸・影・固有寸法**: それぞれ `DSSpacing` / `DSRadius` / `DSShadow`（`dsShadow`） / `DSLayout` を使う。
- **状態の見た目**: `StatusBadge` の対応を唯一の正典とし、画面側で色やアイコンを独自に決めない。
- **テーマ追加**: `AppTheme.fromPalette(...)` でターミナルパレットから導出し、`ThemeStore.all` に登録する。

**現状（2026-06-19 時点）**:
- 監査で検出したトークン迂回（生フォント・固定 pt・生影・グリッド値余白・固有寸法）を `App/`・`DashboardFeature` で一括トークン化した（feature/ds-token-compliance）。同値置換（A）と承認済みの軽微な値変更（B）に分け、土台として `DSShadow.gridTile`・`DSIconSize` を新設。
- `StatusBadge`（状態語彙）バイパスは元から 0 件で不変。
- **CI/lint による自動検出ガードは未整備**（grep ベースの目視確認のみ）。`docs/specs/design-system-ios.md` §7 は将来の lint 導入（`Color(red:` / `.font(.system(size:` 検出）を提案している。

### 許容例外（トークン化しない生値）

対応するトークンが存在しない／一回限りで、トークン化が不適切と判断した生値。**生値の放置を黙殺しないため明文化**する。これらは違反ではなく意図的な例外として扱う。

- **使用率グラデの中間色**: `Usage/UsageDisplay.swift` の緑→黄→赤の連続補間（statusline `rate_color` 移植）と警告赤 `urgentResetColor`。中間色は段階補間のためトークン化不可。
- **IME 未確定オーバーレイ色**: `TerminalUI/MarkedTextOverlayView.swift` の固定 sRGB（Claude 純正キャレットに寄せた色）。対応トークンなし。
- **accent 発光シャドウ**: `Packages/DesignSystem/Sources/DesignSystem/ResizeGripView.swift` の accent 色グロー。`DSShadow` は黒影のみで glow 概念を持たない。（Run 2 で DashboardFeature から DesignSystem へ下層化・public 化・`#if os(macOS)` 化。DS 真実源内に置かれた生値の一回限り例外。）
- **一回限りのアイコン pt**: 14/18/32/40/48/64pt 等、`DSIconSize`(10/12/15) に無い特大・単発サイズ。
- **半端な角丸**: `cornerRadius` 2 / 1.5 / 3、`DSRadius.s + 3` 等（`DSRadius` の 4/8/12 に乗らない極小チップ）。
- **グリッド外の余白**: `.padding` の 1 / 5 / 6 / 28 / 78 等、`DSSpacing`(2/4/8/12/16/24/32) に無い値。
- **ノブ影／ドロップ強調色**: `SettingsView` トグルノブの小影、`SessionGridView` のドロップ対象ハイライト（`white.opacity(0.35)`）。専用の一回限り値。

---

## 8. 既知の制約・補足

- **テーマ切替は即時反映されない**（再起動が必要）。`DSColor`・ターミナルが起動時に `ThemeStore.active` を読む設計のため。
- **macOS 固有部の隔離は「ロジック不変」が原則**。`StatusDot` / `Interaction.swift` の macOS ブランチは隔離前と byte-equivalent（挙動不変）であることをコメントで明示している。NSView ベースのドット表現を純 SwiftUI へ置換すると新たな挙動が混入するため、当面 macOS 専用のまま据え置き。
- **`platforms` は既に iOS を含む**が、iOS 向けの実コンポーネント（タッチ・HIG 部品）は未実装。iOS の青写真は `docs/specs/design-system-ios.md` を参照。

---

## 9. 関連ドキュメント

- `Packages/DesignSystem/Sources/DesignSystem/`（真実源）
- `Packages/DesignSystem/Tests/DesignSystemTests/`（トークン・状態語彙・テーマ解決の検証）
- `docs/specs/design-system-ios.md`（iOS コンパニオン向けの拡張計画・未決事項）
- `Packages/AgentDomain/Sources/AgentDomain/SessionStatus.swift`（状態語彙の出所）
