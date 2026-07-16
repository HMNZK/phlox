import SwiftUI
import DesignSystem
import AgentDomain

/// カンプ固定のセマンティックカラー。テーマ差分を吸収し design.md §2.1 の実値を参照する。
public extension DSColor {
  private static var campTheme: AppTheme { ThemeStore.active }
  private static var isCampLight: Bool { campTheme.preferredColorScheme == .light }

  /// 強調行・承認バー面（ダーク `#221A33` / ライト `#EDE7F7`）。
  static var campSurfaceEmphasis: Color {
    isCampLight ? RGB(0xED, 0xE7, 0xF7).color : RGB(0x22, 0x1A, 0x33).color
  }
  /// ダイアログ・アクションシート面（ダーク `#1F1830` / ライト `#F3EFF8`）。
  static var campSurfaceDialog: Color {
    isCampLight ? RGB(0xF3, 0xEF, 0xF8).color : RGB(0x1F, 0x18, 0x30).color
  }
  /// ターミナル風出力背景（ダーク `#0C0A14` / ライト `#E8E3F0`）。
  static var campOutputBackground: Color {
    isCampLight ? RGB(0xE8, 0xE3, 0xF0).color : RGB(0x0C, 0x0A, 0x14).color
  }
  /// ダイアログ補足・idle テキスト（ダーク `#B0A8BE` / ライト `#7A7289`）。
  static var campTextQuaternary: Color {
    isCampLight ? RGB(0x7A, 0x72, 0x89).color : RGB(0xB0, 0xA8, 0xBE).color
  }
  /// 明るいアクセント（戻るシェブロン等。ダーク `#C084FC` / ライト `#9333EA`）。
  static var campAccentBright: Color {
    isCampLight ? RGB(0x93, 0x33, 0xEA).color : RGB(0xC0, 0x84, 0xFC).color
  }
  /// 「あなたの番」attention ピンク（ダーク `#F472B6` / ライト `#DB2777`）。
  static var campAttention: Color {
    isCampLight ? RGB(0xDB, 0x27, 0x77).color : RGB(0xF4, 0x72, 0xB6).color
  }
  /// カード枠線（`rgba(255,255,255,.05–.08)` / ライトは黒系の同程度不透明度）。
  static var campCardBorder: Color {
    isCampLight ? Color.black.opacity(0.06) : Color.white.opacity(0.06)
  }
  /// ブランドグラデ・濃色 CTA・ユーザーチャットバブル上の前景（カンプ `#FFFFFF`）。
  static let textOnBrand = RGB(0xFF, 0xFF, 0xFF).color
  /// モーダル暗転の下地 brightness（design.md §5 ⑤。ダーク `.45` / ライト `.55`）。
  static var campModalBackdropBrightness: CGFloat {
    isCampLight ? 0.55 : 0.45
  }
  /// モーダル暗転オーバーレイ不透明度（`1 - campModalBackdropBrightness`）。
  static var campModalBackdropOpacity: CGFloat {
    1 - campModalBackdropBrightness
  }
  /// モーダル暗転オーバーレイ（削除確認⑤等）。
  static var campModalBackdrop: Color {
    Color.black.opacity(campModalBackdropOpacity)
  }

  /// カンプ ios-design.html のエージェント識別色（design.md §2.1）。
  static func campAgentColor(for kind: AgentKind) -> Color {
    if isCampLight {
      switch kind {
      case .claudeCode: return RGB(0xC4, 0x6D, 0x42).color
      case .codex: return RGB(0x10, 0xB9, 0x81).color
      case .cursor: return RGB(0x6B, 0x7F, 0xE8).color
      default: return agentColor(for: kind)
      }
    }
    switch kind {
    case .claudeCode: return RGB(0xE0, 0x8B, 0x63).color
    case .codex: return RGB(0x34, 0xD3, 0x99).color
    case .cursor: return RGB(0x8A, 0xA0, 0xFF).color
    default: return agentColor(for: kind)
    }
  }
}
