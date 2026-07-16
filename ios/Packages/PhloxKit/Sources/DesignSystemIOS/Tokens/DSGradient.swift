import SwiftUI
import DesignSystem

/// カンプ由来のブランドグラデーション。design.md §2.1 の実値をトークン化する。
public enum DSGradient {
  /// グラデ開始色（ブランド紫 `#A855F7`）。
  public static let brandStart = RGB(0xA8, 0x55, 0xF7)
  /// グラデ終端色（attention ピンク `#F472B6`）。
  public static let brandEnd = RGB(0xF4, 0x72, 0xB6)
  /// CSS `linear-gradient` 相当の角度（135°）。
  public static let brandAngleDegrees: Double = 135

  /// 主要 CTA・FAB・送信ボタン用ブランドグラデ（`#A855F7 → #F472B6` @ 135°）。
  public static var brand: LinearGradient {
    LinearGradient(
      colors: [brandStart.color, brandEnd.color],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// カンプ⑪ CTA 等の水平ブランドグラデ（左紫 → 右ピンク）。
  public static var brandHorizontal: LinearGradient {
    LinearGradient(
      colors: [brandStart.color, brandEnd.color],
      startPoint: .leading,
      endPoint: .trailing
    )
  }
}
