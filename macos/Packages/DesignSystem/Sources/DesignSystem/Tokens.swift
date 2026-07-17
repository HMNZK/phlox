import SwiftUI
import AgentDomain

/// アプリ全体で参照するスペーシング。8pt グリッドに準拠。
public enum DSSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum DSRadius {
    public static let s: CGFloat = 4
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
}

public enum DSFont {
    public static let caption = Font.caption
    public static let captionStrong = Font.caption.weight(.medium)
    public static let body = Font.body
    public static let sectionHeader = Font.subheadline.weight(.semibold)
    public static let title = Font.title3.weight(.semibold)
    public static let heroTitle = Font.title2.weight(.semibold)
    public static let mono = Font.system(.body, design: .monospaced)
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    /// バッジ等の極小アイコン用。生値 `.system(size: 9)` の直書きを排除する。
    public static let iconTiny = Font.system(size: 9, weight: .bold)
}

/// レイアウト寸法のトークン。8pt グリッドに乗らない固有寸法（進捗バー高）を
/// マジックナンバー直書きから引き上げて一元管理する。
public enum DSLayout {
    /// 進捗バー高。Compact（旧 4）と本体（5）の値ドリフトを 5 に統一。
    public static let progressBarHeight: CGFloat = 5
}

/// SF Symbol などアイコングリフの固有サイズ。本文フォント(DSFont)とは別系統で、
/// 頻出する実寸を一元化する（weight は利用箇所で指定）。一回限りの特大アイコンは対象外。
public enum DSIconSize {
    public static let s: CGFloat = 10
    public static let m: CGFloat = 12
    public static let l: CGFloat = 15
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
    /// グリッドタイルの elevation（card より一段強い。設計の基準値）。
    public static let gridTile = DSShadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
}

public extension View {
    /// `DSShadow` を `.shadow` に適用する単一経路。生値の影を排除する。
    func dsShadow(_ token: DSShadow) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}

/// アプリのセマンティックカラー。実体は `ThemeStore.active`（起動時に確定するカラースキーマ）から引く。
/// テーマ変更は再起動で反映される。
public enum DSColor {
    private static var theme: AppTheme { ThemeStore.active }

    // 背景ランプ（background 最暗 → surface → surfaceElevated）。
    public static var background: Color { theme.background.color }
    public static var surface: Color { theme.surface.color }
    public static var surfaceElevated: Color { theme.surfaceElevated.color }

    // 前景色由来の低不透明 hairline/fill。暗背景では白系、明背景では黒系として可視性を保つ。
    public static var border: Color { theme.textPrimary.color.opacity(0.14) }
    public static var separator: Color { theme.textPrimary.color.opacity(0.10) }
    public static var fillSubtle: Color { theme.textPrimary.color.opacity(0.05) }   // ホバー
    public static var fillSelected: Color { theme.textPrimary.color.opacity(0.10) } // 選択・アクティブ
    public static var chatBackground: Color { theme.background.color }
    public static var chatCard: Color { theme.surface.color }
    public static var chatElevated: Color { theme.surfaceElevated.color }
    public static var chatAccent: Color { theme.accent.color }
    public static var chatSuccess: Color { theme.statusCompleted.color }
    public static var chatTextPrimary: Color { theme.textPrimary.color }
    public static var chatTextSecondary: Color { theme.textSecondary.color }
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
    /// ユーザー発言バブルの面。AI 返信が無背景のため、右寄せ＋この面で話者を区別する。
    /// アクセント面ではなく、テーマ前景由来のニュートラルな薄い面で示す。
    public static var userBubble: Color { theme.textPrimary.color.opacity(0.08) }

    /// ファイル差分の色。追加行=青・削除行=赤（全テーマ共通のセマンティック色。明度で微調整）。
    public static var diffAdded: Color {
        theme.preferredColorScheme == .light ? RGB(0x25, 0x63, 0xEB).color : RGB(0x60, 0xA5, 0xFA).color
    }
    public static var diffRemoved: Color {
        theme.preferredColorScheme == .light ? RGB(0xDC, 0x26, 0x26).color : RGB(0xF8, 0x71, 0x71).color
    }

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

    public static var accent: Color { theme.accent.color }

    public static var statusStarting: Color { theme.statusStarting.color }
    public static var statusIdle: Color { theme.statusIdle.color }

    // 未確認完了=「あなたの番」。テーマの attention 色を不透明度違いで使い回す。
    private static var attention: Color { theme.attention.color }
    /// サイドバーで未確認完了セッション行の背景面。
    public static var idleHighlight: Color { attention.opacity(0.22) }
    /// 未確認完了行の左端アクセントバー（行コンテンツに直接描画）。
    public static var idleHighlightBar: Color { attention.opacity(0.95) }
    /// グリッドビューで未確認完了カードの背景面。
    public static var idleHighlightGrid: Color { attention.opacity(0.18) }
    /// グリッドビューで未確認完了カードの枠線。
    public static var idleHighlightGridBorder: Color { attention.opacity(0.95) }

    // 未確認の「停止＝要対応」（完了/承認待ち/エラー等でユーザーの番になったセッション）。
    // 完了(attention=黄系)より強い注意喚起として、テーマの error 色（赤系）で描く。
    /// グリッドビューで未確認停止カードの枠線（赤）。
    public static var stoppedHighlightGridBorder: Color { statusError.opacity(0.95) }
    /// グリッドビューで未確認停止カードの背景面（赤・淡）。
    public static var stoppedHighlightGrid: Color { statusError.opacity(0.16) }

    public static var statusRunning: Color { theme.statusRunning.color }
    public static var statusAwaitingApproval: Color { theme.statusAwaiting.color }
    public static var statusCompleted: Color { theme.statusCompleted.color }
    public static var statusError: Color { theme.statusError.color }

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
