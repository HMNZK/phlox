import SwiftUI
import DesignSystem

public extension DSShadow {
  private static var brandGlowColor: Color {
    RGB(0xA8, 0x55, 0xF7).color.opacity(0.6)
  }

  /// 主要 CTA の紫グロー。Camp: `0 8px 24px -6px rgba(168,85,247,.6)`。
  static let ctaGlow = DSShadow(color: brandGlowColor, radius: 24, x: 0, y: 8)

  /// FAB / 送信丸ボタンの紫グロー。Camp: `0 6px 16px -4px rgba(168,85,247,.6)`。
  static let fabGlow = DSShadow(color: brandGlowColor, radius: 16, x: 0, y: 6)

  /// ダイアログ elevation。Camp: `0 30px 60px -15px rgba(0,0,0,.7)`。
  static let dialog = DSShadow(color: Color.black.opacity(0.7), radius: 60, x: 0, y: 30)
}
