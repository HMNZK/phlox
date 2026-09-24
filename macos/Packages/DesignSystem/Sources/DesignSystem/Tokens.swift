import SwiftUI
import AgentDomain

/// アプリ全体で参照するスペーシング。8pt グリッドに準拠。
public enum DSSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    /// チップの間（再設計で追加した 6pt）。
    public static let chip: CGFloat = 6
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum DSRadius {
    public static let s: CGFloat = 4       // タグ・キー
    public static let row: CGFloat = 6     // ボタン・行
    public static let m: CGFloat = 8       // カード
    public static let attention: CGFloat = 10 // 対応待ちカード・パネル
    public static let l: CGFloat = 12      // 入力欄・シート
}

public enum DSFont {
    /// 旧来の小さい文字。再設計の段の最小（11）に揃える（macOS の `Font.caption` は 10pt で段の外）。
    public static let caption = Font.system(size: 11)
    public static let captionStrong = Font.system(size: 11, weight: .medium)
    public static let body = Font.body
    public static let bodyMedium = Font.body.weight(.medium)
    public static let sectionHeader = Font.subheadline.weight(.semibold)
    public static let title = Font.title3.weight(.semibold)
    public static let heroTitle = Font.title2.weight(.semibold)
    public static let mono = Font.system(.body, design: .monospaced)
    public static let monoCaption = Font.system(size: 11, design: .monospaced)
    /// バッジ等の極小アイコン用。生値 `.system(size: 9)` の直書きを排除する。
    public static let iconTiny = Font.system(size: 9, weight: .bold)

    // 再設計の文字の段（12 Design System）。和文はシステムがヒラギノ角ゴシックへ落とす。
    /// 24 / Bold — 空の画面の見出し
    public static let emptyTitle = Font.system(size: 24, weight: .bold)
    /// 17 / Bold — シート・アラートの見出し
    public static let sheetTitle = Font.system(size: 17, weight: .bold)
    /// 14 / Semibold — セッションヘッダのタイトル
    public static let sessionTitle = Font.system(size: 14, weight: .semibold)
    /// 13 / Regular — 本文・一覧の行・ボタン
    public static let row = Font.system(size: 13)
    /// 12.5 / Regular — 密な本文（タイル・カード）
    public static let dense = Font.system(size: 12.5)
    /// 12 / Regular — 補助の説明・表
    public static let auxiliary = Font.system(size: 12)
    /// 11.5 / Semibold — 状態の文言（サイドバー・タイル）
    public static let stateLabel = Font.system(size: 11.5, weight: .semibold)
    /// 11 / Regular — 時刻・メタ・キー
    public static let meta = Font.system(size: 11)

    /// `body` の実寸。`Font` から実寸を取り出せないため、CATextLayer 等の
    /// Core Animation 経路（`ShimmerTextView`）に渡す値として明示する。
    #if os(macOS)
    public static let bodyPointSize: CGFloat = 13
    #else
    public static let bodyPointSize: CGFloat = 17
    #endif
}

/// レイアウト寸法のトークン。8pt グリッドに乗らない固有寸法（進捗バー高）を
/// マジックナンバー直書きから引き上げて一元管理する。
public enum DSLayout {
    /// 進捗バー高。Compact（旧 4）と本体（5）の値ドリフトを 5 に統一。
    public static let progressBarHeight: CGFloat = 5

    // 再設計の高さ・幅（12 Design System / README「全体の決定事項」）。
    public static let toolbarHeight: CGFloat = 52
    public static let tabBarHeight: CGFloat = 32
    public static let childTabBarHeight: CGFloat = 32
    public static let listRowHeight: CGFloat = 28
    public static let cardHeaderHeight: CGFloat = 32
    /// 分割線の当たり（見た目は 1pt、ホバーで accent 3pt）。
    public static let dividerHitWidth: CGFloat = 8
    public static let sidebarWidth = WidthRange(ideal: 260, min: 220, max: 360)
    public static let inspectorWidth = WidthRange(ideal: 280, min: 260, max: 340)

    public struct WidthRange: Sendable, Equatable {
        public let ideal: CGFloat
        public let min: CGFloat
        public let max: CGFloat

        public func clamped(_ value: CGFloat) -> CGFloat { Swift.min(max, Swift.max(min, value)) }
    }
}

/// SF Symbol などアイコングリフの固有サイズ。本文フォント(DSFont)とは別系統で、
/// 頻出する実寸を一元化する（weight は利用箇所で指定）。一回限りの特大アイコンは対象外。
public enum DSIconSize {
    public static let s: CGFloat = 10
    public static let m: CGFloat = 12
    public static let l: CGFloat = 15
}

/// 小さなアイコン操作の押せる範囲。絵柄（DSIconSize）とは別系統。
public enum DSHitTarget {
    public static let icon: CGFloat = 24            // サイドバー＋/…、タイル×
    public static let modeSegmentWidth: CGFloat = 30
    public static let modeSegmentHeight: CGFloat = 24 // 押せる範囲（task-34 で 24 以上）。見た目の 22 は ModeSegmentButton が内側に描く
}

/// elevation（面の持ち上げ）を表す影トークン。生値の `.shadow(...)` 直書きを排除し、
/// `View.dsShadow(_:)` 経由でのみ適用する。grid タイル（black 0.4/r10/y4）より一段弱い値を基準にする。
public struct DSShadow: Equatable, Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    /// カンバン／汎用カードの控えめな elevation。
    public static let card = DSShadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 3)
    /// hover 時の持ち上げ。
    public static let cardHover = DSShadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 6)
    // 再設計の影。SwiftUI の radius は CSS の blur のおよそ半分で同じ広がりになるので、blur / 2 を入れる。
    /// グリッドタイルの elevation（`0 1px 2px rgba(0,0,0,.06)`）。縁は別途 separator で描く。
    public static let gridTile = DSShadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
    /// ポップオーバー（ライト `0 10px 30px rgba(0,0,0,.16)` / ダーク `0 12px 34px rgba(0,0,0,.55)`）。
    public static var popover: DSShadow {
        DSColor.isDark
            ? DSShadow(color: Color.black.opacity(0.55), radius: 17, x: 0, y: 12)
            : DSShadow(color: Color.black.opacity(0.16), radius: 15, x: 0, y: 10)
    }
    /// ウィンドウ（`0 22px 60px rgba(0,0,0,.18)`）。
    public static let window = DSShadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 22)
}

public extension View {
    /// `DSShadow` を `.shadow` に適用する単一経路。生値の影を排除する。
    func dsShadow(_ token: DSShadow) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}

/// アプリのセマンティックカラー。実体は `ThemeStore.active` から引く。
/// 読み出しが `ThemeChangeSignal` に登録されるので、テーマ変更はこの色を使う View へ即時に反映される。
public enum DSColor {
    private static var theme: AppTheme { ThemeStore.active }

    // 背景ランプ（background 最暗 → surface → surfaceElevated）。
    public static var background: Color { theme.background.color }
    public static var surface: Color { theme.surface.color }
    public static var surfaceElevated: Color { theme.surfaceElevated.color }

    // 前景色由来の低不透明 hairline/fill。暗背景では白系、明背景では黒系として可視性を保つ。
    public static var border: Color { theme.textPrimary.color.opacity(0.14) }
    public static var separator: Color { theme.textPrimary.color.opacity(0.10) }
    /// ホバー面（12 Design System `--hov`: ライト 0.05 / ダーク 0.06）。
    public static var fillSubtle: Color { theme.textPrimary.color.opacity(AppTheme.sidebarHoverOpacity(isDark: isDark)) }
    /// 無彩色の選択・アクティブ面（`--sel`: ライト 0.075 / ダーク 0.09）。
    public static var fillSelected: Color { theme.textPrimary.color.opacity(AppTheme.sidebarSelectedOpacity(isDark: isDark)) }
    public static var chatBackground: Color { theme.background.color }
    public static var chatCard: Color { theme.surface.color }
    public static var chatElevated: Color { theme.surfaceElevated.color }
    /// 会話の accent（輪・点）。文字に使うときは `accentInk`。
    public static var chatAccent: Color { accent }
    /// 成功の印。実行中・完了は無彩色で出す（README 決定事項 4）ので補助の文字色。
    public static var chatSuccess: Color { textSecondary }
    public static var chatTextPrimary: Color { theme.textPrimary.color }
    public static var chatTextSecondary: Color { theme.textSecondary.color }
    /// ツール呼び出しの本文色。テーマの前景色を無彩色のまま半透明化し、チャット本文より控えめにする。
    public static var chatToolCallText: Color { theme.textPrimary.color.opacity(0.68) }
    // コードのシンタックスハイライト色（ChatMessageCells の自前ハイライタが使用）。
    // ライトテーマでは白地でも沈まない濃色へ切り替える。
    public static var codeSyntaxKeyword: Color {
        theme.preferredColorScheme == .light ? RGB(0x5B, 0x21, 0xB6).color : RGB(0xC4, 0xB5, 0xFD).color
    }
    public static var codeSyntaxString: Color {
        theme.preferredColorScheme == .light ? RGB(0x16, 0x65, 0x34).color : RGB(0x86, 0xEF, 0xAC).color
    }
    public static var codeSyntaxComment: Color {
        theme.preferredColorScheme == .light ? RGB(0x6B, 0x72, 0x80).color : RGB(0x8A, 0x81, 0x9E).color
    }
    public static var codeSyntaxNumber: Color {
        theme.preferredColorScheme == .light ? RGB(0x9D, 0x17, 0x4D).color : RGB(0xF0, 0xAB, 0xFC).color
    }
    /// 入力欄のキーワード強調（ultrathink 等）。PhloxReply.dc.html の kw（--stlInk）。
    public static var composerKeyword: Color { attentionInk(.stalled) }
    /// ユーザー発言バブルの面。AI 返信が無背景のため、右寄せ＋この面で話者を区別する。
    /// アクセント面ではなく、テーマ前景由来のニュートラルな薄い面で示す。
    public static var userBubble: Color { theme.textPrimary.color.opacity(0.08) }

    /// 入力欄（composer）パネルの枠線（05 Reply Area: 本文色 14%。ライト・ダーク共通）。
    public static var composerBorder: Color { border }

    /// ファイル差分の色（再設計: 追加=緑・削除=赤。各テーマで 4.5:1 以上に導出）。
    public static var diffAdded: Color { theme.palette.diffAdded.color }
    public static var diffRemoved: Color { theme.palette.diffRemoved.color }
    /// 差分の追加・削除行の面（PhloxChat.dc.html の --addTint / --delTint。ライト 10%/9%、ダーク 12%）。
    public static var diffAddedTint: Color { diffAdded.opacity(theme.palette.isLight ? 0.10 : 0.12) }
    public static var diffRemovedTint: Color { diffRemoved.opacity(theme.palette.isLight ? 0.09 : 0.12) }

    // セッション行のホバー（面＋枠）。前景色由来の低不透明値で明度に追随する。
    public static var sessionRowHover: Color {
        fillSubtle
    }
    public static var sessionRowHoverBorder: Color {
        border
    }
    public static var sessionRowSelected: Color { fillSelected }
    public static var sessionRowSelectedBorder: Color { Color.clear }

    public static var textPrimary: Color { theme.textPrimary.color }
    public static var textSecondary: Color { theme.textSecondary.color }
    public static var textTertiary: Color { theme.textTertiary.color }

    /// フォーカス輪・未読の点・選択の accent（再設計: ダークでは #E08865）。ブランドのコーラルは `AppTheme.accent`。
    public static var accent: Color { theme.palette.accent.color }

    public static var statusStarting: Color { theme.statusStarting.color }
    public static var statusIdle: Color { theme.statusIdle.color }

    // 未確認完了=「あなたの番」。テーマの attention 色を不透明度違いで使い回す。
    private static var attention: Color { theme.attention.color }
    /// サイドバーで未確認完了セッション行の背景面。
    public static var idleHighlight: Color { attention.opacity(AppTheme.sidebarAttentionOpacity) }
    /// 未確認完了行の左端アクセントバー（行コンテンツに直接描画）。
    public static var idleHighlightBar: Color { attention.opacity(0.95) }
    /// グリッドビューで未確認完了カードの背景面。
    public static var idleHighlightGrid: Color { attention.opacity(0.18) }
    /// グリッドビューで未確認完了カードの枠線。
    public static var idleHighlightGridBorder: Color { attention.opacity(0.95) }

    // 未確認の「停止＝要対応」（完了/承認待ち/エラー等でユーザーの番になったセッション）。
    // 完了(attention=黄系)より強い注意喚起として、テーマの error 色（赤系）で描く。
    /// グリッドビューで未確認停止カードの枠線（エラーの記号色）。
    public static var stoppedHighlightGridBorder: Color { attentionMark(.error) }
    /// グリッドビューで未確認停止カードの背景面（エラーの淡い面）。
    public static var stoppedHighlightGrid: Color { attentionTint(.error) }

    public static var statusRunning: Color { theme.statusRunning.color }
    /// 承認待ちの記号・縁の色。文字には `statusAwaitingApprovalForeground` を使う。
    public static var statusAwaitingApproval: Color { attentionMark(.approval) }
    public static var statusAwaitingApprovalFill: Color { attentionTint(.approval) }
    public static var statusAwaitingApprovalBorder: Color { attentionMark(.approval) }
    public static var statusAwaitingApprovalForeground: Color { attentionInk(.approval) }
    public static var statusCompleted: Color { theme.statusCompleted.color }
    /// エラーの文字色（記号・縁は `attentionMark(.error)`、面は `attentionTint(.error)`）。
    public static var statusError: Color { attentionInk(.error) }

    /// 暗いテーマか。影・面の明暗の出し分けに使う。
    public static var isDark: Bool { theme.preferredColorScheme == .dark }

    /// New session ボタンのブランドグラデ（紫→ピンク）。テーマ由来にすると、両端が同色になる
    /// テーマ（例: Tokyo Night は accent と ansi[5] がともに 0xBB9AF7）でフラット化するため、
    /// テーマに依らずブランド色で固定する。
    public static var newSessionGradient: LinearGradient {
        LinearGradient(
            colors: [RGB(0xA8, 0x55, 0xF7).color, RGB(0xEC, 0x48, 0x99).color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - 再設計の面・accent・対応待ち（12 Design System）

    private static var palette: DesignPalette { theme.palette }

    public static var windowBackground: Color { palette.window.color }
    public static var sidebarBackground: Color { palette.sidebar.color }
    public static var toolbarBackground: Color { palette.toolbar.color }
    public static var panelBackground: Color { palette.panel.color }
    public static var cardBackground: Color { palette.card.color }
    public static var codeBackground: Color { palette.code.color }
    public static var fieldBackground: Color { palette.field.color }
    public static var popoverBackground: Color { palette.popover.color }
    /// ポップオーバーの縁（`--shadow` の 0.5px: ライト 黒 20% / ダーク 白 16%）。
    public static var popoverEdge: Color { isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.20) }
    public static var tabBarBackground: Color { palette.tabBar.color }
    public static var terminalBackground: Color { palette.terminal.color }

    /// 白文字を載せる accent の面（主ボタン）。
    public static var accentFill: Color { palette.accentFill.color }
    /// accent の文字（リンク・選択中タブ）。
    public static var accentInk: Color { palette.accentInk.color }
    /// 選択中の行（`rgba(217,119,87,.17)` / `.24`。ダークでも輪の色ではなくブランドのコーラルを基にする）。
    public static var selectionFill: Color { RGB(0xD9, 0x77, 0x57).color.opacity(palette.selectionOpacity) }
    /// 選択した文字・フォーカスの輪（`--selText`: ライト coral 0.25 / ダーク #E08865 0.30）。
    public static var focusRing: Color { accent.opacity(isDark ? 0.30 : 0.25) }
    /// ツリーの縦の案内線（`--guide`: 黒 0.13 / 白 0.14）。
    public static var guide: Color { theme.textPrimary.color.opacity(isDark ? 0.14 : 0.13) }
    /// 無彩色の状態記号（待機・実行中・完了の輪。`--neutralGlyph`: #6E6E73 / #A1A1A7）。
    public static var neutralGlyph: Color { (isDark ? RGB(0xA1, 0xA1, 0xA7) : RGB(0x6E, 0x6E, 0x73)).color }

    // 操作部品の面（12 Design System P）。
    /// 副ボタン・セグメントの選択中の面（`--ctl`: `#FFFFFF` / `#3A3A3E`）。
    public static var controlBackground: Color {
        guard isDark else { return palette.card.color }
        // 既定ダークはモックの確定値。他のダークテーマは窓の面から同じ明るさだけ持ち上げる。
        return theme.id == AppTheme.phlox.id ? RGB(0x3A, 0x3A, 0x3E).color : palette.window.lightened(0x1C).color
    }
    /// グリッドの領域（`--area`: #F4F4F6 / #18181A）。タイル（`--bg`）より一段沈める。導出テーマは窓の面から同じだけ沈める。
    public static var gridAreaBackground: Color {
        switch theme.id {
        case AppTheme.phloxLight.id: RGB(0xF4, 0xF4, 0xF6).color
        case AppTheme.phlox.id: RGB(0x18, 0x18, 0x1A).color
        default: palette.window.darkened(isDark ? 0x06 : 0x0B).color
        }
    }
    /// 副ボタンの 0.5pt の縁（`--ctlBorder`: 黒 0.16 / 白 0.10）。
    public static var controlBorder: Color { theme.textPrimary.color.opacity(isDark ? 0.10 : 0.16) }
    /// セグメントのトラック（`--segBg`: 黒 0.065 / 白 0.08）。
    public static var segmentTrack: Color { theme.textPrimary.color.opacity(isDark ? 0.08 : 0.065) }
    /// 入力欄の縁（`--fieldBorder`: 0.14）。
    public static var fieldBorder: Color { border }
    /// トグルのオフの面（`--off`: 黒 0.13 / 白 0.16）。
    public static var toggleOff: Color { theme.textPrimary.color.opacity(isDark ? 0.16 : 0.13) }

    public static var statusStalled: Color { palette.stalled.mark.color }

    public static func attentionColors(_ kind: AttentionKind) -> AttentionColors {
        switch kind {
        case .approval: palette.approval
        case .question: palette.question
        case .error: palette.error
        case .stalled: palette.stalled
        }
    }

    /// 対応待ちの記号・縁。
    public static func attentionMark(_ kind: AttentionKind) -> Color { attentionColors(kind).mark.color }
    /// 対応待ちの文言。
    public static func attentionInk(_ kind: AttentionKind) -> Color { attentionColors(kind).ink.color }
    /// 対応待ちの淡い面。
    public static func attentionTint(_ kind: AttentionKind) -> Color {
        let c = attentionColors(kind)
        return c.mark.color.opacity(c.tintOpacity)
    }

    /// エージェント頭文字の淡い面（不透明度 30%）。行とタイル見出しでは使わない。
    public static func agentInitialFill(for descriptor: AgentDescriptor) -> Color {
        let rgb: RGB
        switch descriptor.ref.builtinKind {
        case .claudeCode: rgb = RGB(0xD4, 0x93, 0x75)   // oklch(0.72 0.09 45)
        case .codex: rgb = RGB(0x7A, 0xB3, 0x9A)        // oklch(0.72 0.07 165)
        case .cursor: rgb = RGB(0x8B, 0xA6, 0xD1)       // oklch(0.72 0.07 260)
        case nil: rgb = RGB(descriptor.colorRGB)         // agents.json の colorHex
        }
        return rgb.color.opacity(0.30)
    }

    public static func agentColor(for kind: AgentKind) -> Color {
        (theme.agentColors[kind] ?? RGB(AgentRegistry.descriptor(for: kind).colorRGB)).color
    }

    public static func agentColor(for descriptor: AgentDescriptor) -> Color {
        if let kind = descriptor.ref.builtinKind {
            return agentColor(for: kind)
        }
        return RGB(descriptor.colorRGB).color
    }
}

public extension AgentDescriptor {
    /// 種類を見分ける短い記号（Cl / Cx / Cu）。組み込み以外は表示名の先頭 2 文字。
    /// タブ・会話の字下げ列の印で共通に使う。
    var tabInitials: String {
        switch ref.builtinKind {
        case .claudeCode: "Cl"
        case .codex: "Cx"
        case .cursor: "Cu"
        case nil: String(displayName.prefix(2))
        }
    }
}
